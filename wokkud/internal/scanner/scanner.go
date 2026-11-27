// Package scanner is wokkud's image-scan worker (Security Scan Tier 0): claim
// a pending scan, `docker save` the already-pushed image to a temp tar, run
// Trivy on that tar in a locked-down container with no network and no docker
// socket, and report severity counts + the 50 most severe findings. Raw
// Trivy output never leaves this process. Informational only — a scan never
// touches a deploy, and all failures are REPORTED, never returned.
package scanner

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"

	"wokku.cloud/wokkud/internal/builder"
	"wokku.cloud/wokkud/internal/control"
)

// TrivyImage is the only scanner image wokkud runs. Bump deliberately, to a
// release at least two weeks old, by digest — never a tag, never latest.
const TrivyImage = "aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb" // v0.76.2, released 2026-11-05, pinned 2026-11-27

const (
	cacheVolume    = "wokku-trivy-cache"
	cacheDir       = "/root/.cache/trivy"
	dbMaxAge       = 24 * time.Hour
	javaDBMaxAge   = 7 * 24 * time.Hour
	refreshBackoff = time.Hour
	cleanupTimeout = 30 * time.Second
	diskHeadroom   = 2 << 30 // free space needed on top of the image size
	maxDiskUsedPct = 85
	defaultTimeout = 300
	maxFindings    = 50
	maxTitle       = 160
)

// refPattern: only images in the host's loopback registry, tag or digest —
// the scan must never pull from the internet on the control plane's say-so,
// and nothing that docker could read as a flag.
var refPattern = regexp.MustCompile(`^127\.0\.0\.1:5000/[a-z0-9._/-]+(:[\w.-]+|@sha256:[0-9a-f]{64})$`)

var unsafeName = regexp.MustCompile(`[^a-zA-Z0-9_.-]`)

type runFunc func(ctx context.Context, args ...string) ([]byte, error)

// Worker serialises scans: one at a time per host, never while a build runs
// (the heartbeat can hand out a new id while one is still claimed — it just
// queues). ponytail: single worker, same as builder.Executor.
type Worker struct {
	Busy func() bool // builder.Executor.Busy

	client   *control.Client
	run      runFunc
	now      func() time.Time
	statfs   func(path string) (free, total uint64, err error)
	queue    chan string
	mu       sync.Mutex
	inFlight map[string]bool

	// owned by the work goroutine
	db          dbInfo
	lastRefresh time.Time
}

type dbInfo struct {
	version      string
	updatedAt    string
	downloadedAt time.Time
	// From `trivy version --format json`'s JavaDB block (v0.76.2 prints it
	// when the Java DB is cached); zero when absent.
	javaDownloadedAt time.Time
}

func NewWorker(ctx context.Context, client *control.Client, busy func() bool) *Worker {
	w := newWorker(client, busy)
	go w.work(ctx)
	return w
}

func newWorker(client *control.Client, busy func() bool) *Worker {
	return &Worker{Busy: busy, client: client, run: execRun, now: time.Now, statfs: statfs,
		queue: make(chan string, 16), inFlight: map[string]bool{}}
}

func (w *Worker) Enqueue(id string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.inFlight[id] {
		return
	}
	select {
	case w.queue <- id:
		w.inFlight[id] = true
	default: // full — the next heartbeat re-delivers
	}
}

func (w *Worker) work(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case id := <-w.queue:
			// A build is running: drop the id unclaimed; it stays pending and
			// the next heartbeat (15 s) re-delivers it.
			if !w.Busy() {
				w.scanOne(ctx, id)
			}
			w.mu.Lock()
			delete(w.inFlight, id)
			w.mu.Unlock()
		}
	}
}

func (w *Worker) scanOne(parent context.Context, id string) {
	job, err := w.client.ClaimImageScan(id)
	if err != nil {
		log.Printf("wokkud: claim image scan %s: %v", id, err)
	}
	if job == nil {
		return
	}
	timeout := job.TimeoutSeconds
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	ctx, cancel := context.WithTimeout(parent, time.Duration(timeout)*time.Second)
	defer cancel()
	rep := w.scan(ctx, unsafeName.ReplaceAllString(id, ""), job.ImageRef)
	if parent.Err() != nil {
		return // agent shutting down; the control plane's janitor times the claim out
	}
	if rep.Status != "succeeded" {
		log.Printf("wokkud: image scan %s failed: %s %s", id, rep.ErrorCode, rep.Error)
	}
	if err := w.client.ReportImageScan(id, rep); err != nil {
		log.Printf("wokkud: report image scan %s: %v", id, err)
	}
}

// cleanup runs a best-effort docker command that must happen even after the
// scan's context timed out.
func (w *Worker) cleanup(args ...string) {
	ctx, cancel := context.WithTimeout(context.Background(), cleanupTimeout)
	defer cancel()
	w.run(ctx, args...)
}

func (w *Worker) scan(ctx context.Context, id, ref string) control.ImageScanReport {
	if rep, ok := checkRef(ref); !ok {
		return rep
	}
	fail := func(code string, err error) control.ImageScanReport {
		var ec interface{ ExitCode() int }
		switch {
		case errors.Is(ctx.Err(), context.DeadlineExceeded):
			code = "timeout"
		case errors.As(err, &ec) && ec.ExitCode() == 137: // SIGKILL under --memory
			code = "oom"
		case strings.Contains(err.Error(), "no space left on device"):
			code = "disk_full"
		}
		return failed(code, err.Error())
	}

	// Fetch the pinned scanner image up front so a registry hiccup on our
	// own image reads as pull_failed, not as a DB problem.
	if _, err := w.run(ctx, "docker", "image", "inspect", TrivyImage); err != nil {
		if _, err := w.run(ctx, "docker", "pull", "-q", TrivyImage); err != nil {
			return fail("pull_failed", err)
		}
	}
	if err := w.ensureDB(ctx, id); err != nil {
		return fail("db_unavailable", err)
	}

	size, err := w.imageSize(ctx, ref)
	if err != nil {
		if _, err := w.run(ctx, "docker", "pull", "-q", ref); err != nil {
			code := "pull_failed"
			if msg := err.Error(); strings.Contains(msg, "manifest unknown") || strings.Contains(msg, "not found") {
				code = "image_missing"
			}
			return fail(code, err)
		}
		// Pulled only for this scan — don't leave a tagged copy behind.
		defer w.cleanup("docker", "rmi", ref)
		if size, err = w.imageSize(ctx, ref); err != nil {
			return fail("image_missing", err)
		}
	}
	if err := w.checkDisk(size); err != nil {
		return fail("disk_full", err)
	}
	dir, err := os.MkdirTemp("", "wokkud-scan-")
	if err != nil {
		return fail("image_missing", err)
	}
	defer os.RemoveAll(dir)
	tar := filepath.Join(dir, "image.tar")
	if _, err := w.run(ctx, "docker", "save", "-o", tar, ref); err != nil {
		return fail("image_missing", err)
	}

	// A build claimed while we were saving: never run alongside it. Reported
	// as a timeout — the nightly job (or the next deploy) scans it again.
	if w.Busy() {
		return failed("timeout", "aborted: a build started on this host")
	}
	out, err := w.runNamed(ctx, "wokku-trivy-scan-"+id, scanArgs("wokku-trivy-scan-"+id, tar)...)
	if err != nil {
		code := ""                                // Rails records an unlisted code as "unknown"
		if strings.Contains(err.Error(), " DB") { // e.g. "--skip-db-update cannot be specified on the first run"
			code = "db_unavailable"
		}
		return fail(code, err)
	}
	counts, findings, err := parse(out)
	if err != nil {
		return fail("parse_failed", err)
	}
	return control.ImageScanReport{Status: "succeeded", Counts: counts, Findings: findings,
		ScannerVersion: w.db.version, DBUpdatedAt: w.db.updatedAt}
}

func checkRef(ref string) (control.ImageScanReport, bool) {
	if !refPattern.MatchString(ref) {
		return failed("image_missing", "image ref not in the local registry: "+ref), false
	}
	return control.ImageScanReport{}, true
}

func (w *Worker) imageSize(ctx context.Context, ref string) (uint64, error) {
	out, err := w.run(ctx, "docker", "image", "inspect", "--format", "{{.Size}}", ref)
	if err != nil {
		return 0, err
	}
	size, _ := strconv.ParseUint(strings.TrimSpace(string(out)), 10, 64) // unparseable: headroom alone
	return size, nil
}

// checkDisk: the tar lands in TMPDIR, as big as the image. Refuse when it
// wouldn't fit with 2 GiB to spare, or the disk is already 85% used.
func (w *Worker) checkDisk(size uint64) error {
	free, total, err := w.statfs(os.TempDir())
	if err != nil {
		return fmt.Errorf("statfs %s: %w", os.TempDir(), err)
	}
	if free < size+diskHeadroom || (total > 0 && (total-free)*100/total >= maxDiskUsedPct) {
		return fmt.Errorf("not enough disk for a %d-byte image: %d of %d bytes free", size, free, total)
	}
	return nil
}

func statfs(path string) (uint64, uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, 0, err
	}
	return st.Bavail * uint64(st.Bsize), st.Blocks * uint64(st.Bsize), nil
}

// failed builds a failure report; only the first line of the error goes
// over the wire.
func failed(code, msg string) control.ImageScanReport {
	msg, _, _ = strings.Cut(msg, "\n")
	if len(msg) > 500 {
		msg = msg[:500]
	}
	return control.ImageScanReport{Status: "failed", ErrorCode: code, Error: msg}
}

// ensureDB refreshes the vulnerability DB when it is 24 h old and the Java
// DB (~1 GB) when it is a week old or missing — at most one attempt an hour.
// A failed refresh with a DB already cached scans against the stale one (the
// report carries db_updated_at); with no vulnerability DB at all it's
// db_unavailable. Without a Java DB only JAR images fail (see scanArgs).
func (w *Worker) ensureDB(ctx context.Context, id string) error {
	if w.db.downloadedAt.IsZero() {
		w.db = w.readDB(ctx, id)
	}
	needDB := w.now().Sub(w.db.downloadedAt) >= dbMaxAge
	needJava := w.now().Sub(w.db.javaDownloadedAt) >= javaDBMaxAge // zero time: missing
	if !needDB && !needJava {
		return nil
	}
	if !w.lastRefresh.IsZero() && w.now().Sub(w.lastRefresh) < refreshBackoff {
		if w.db.downloadedAt.IsZero() {
			return errors.New("no trivy DB yet; last download attempt under an hour ago")
		}
		return nil
	}
	w.lastRefresh = w.now()
	// The only networked runs: default bridge network, their own container.
	name := "wokku-trivy-db-" + id
	download := func(flag string) error {
		_, err := w.runNamed(ctx, name, append(hardened(name), "-v", cacheVolume+":"+cacheDir, TrivyImage,
			"image", flag, "--cache-dir", cacheDir, "--quiet")...)
		return err
	}
	if needDB {
		if err := download("--download-db-only"); err != nil {
			if w.db.downloadedAt.IsZero() {
				return err
			}
			log.Printf("wokkud: trivy DB refresh failed, scanning with the DB from %s: %v", w.db.updatedAt, err)
		}
	}
	if needJava {
		if err := download("--download-java-db-only"); err != nil {
			log.Printf("wokkud: trivy Java DB refresh failed: %v", err)
		}
	}
	w.db = w.readDB(ctx, id)
	if w.db.downloadedAt.IsZero() {
		return errors.New("trivy DB missing after refresh")
	}
	return nil
}

// readDB asks the pinned Trivy for its version and the cached DBs' metadata
// (offline, cache read-only). Zero value when there is no DB yet.
func (w *Worker) readDB(ctx context.Context, id string) dbInfo {
	name := "wokku-trivy-version-" + id
	out, err := w.runNamed(ctx, name, append(hardened(name), "--network", "none",
		"-v", cacheVolume+":"+cacheDir+":ro", TrivyImage,
		"version", "--format", "json", "--cache-dir", cacheDir)...)
	if err != nil {
		return dbInfo{}
	}
	type meta struct{ UpdatedAt, DownloadedAt time.Time }
	var v struct {
		Version         string
		VulnerabilityDB *meta
		JavaDB          *meta
	}
	if json.Unmarshal(out, &v) != nil || v.VulnerabilityDB == nil {
		return dbInfo{}
	}
	info := dbInfo{version: v.Version, updatedAt: v.VulnerabilityDB.UpdatedAt.UTC().Format(time.RFC3339),
		downloadedAt: v.VulnerabilityDB.DownloadedAt}
	if v.JavaDB != nil {
		info.javaDownloadedAt = v.JavaDB.DownloadedAt
	}
	return info
}

// hardened is the shared `docker run` prefix: read-only rootfs, no caps, no
// privilege escalation, memory/pids/CPU caps (WOKKUD_SCAN_MEMORY / _PIDS /
// _CPUS override 2g / 512 / 2), a 1 GiB /tmp. Network is the caller's choice.
func hardened(name string) []string {
	mem := env("WOKKUD_SCAN_MEMORY", "2g")
	return []string{"docker", "run", "--rm", "--name", name,
		"--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
		"--memory", mem, "--memory-swap", mem, // swap == memory: no swap escape
		"--pids-limit", env("WOKKUD_SCAN_PIDS", "512"), "--cpus", env("WOKKUD_SCAN_CPUS", "2"),
		"--tmpfs", "/tmp:rw,size=1g"}
}

// scanArgs: the image arrives as a read-only `docker save` tar — no docker
// socket, no registry, no network inside the scanner. Trivy opens the Java
// DB lazily, only for images with JARs, so without one non-JAR images still
// scan and JAR images fail "Java DB update failed" (→ db_unavailable).
// (v0.76.2 has no CLI flag to turn the jar analyzer off.)
func scanArgs(name, tar string) []string {
	return append(hardened(name), "--network", "none",
		"-v", cacheVolume+":"+cacheDir+":ro",
		"-v", tar+":/scan/image.tar:ro",
		TrivyImage, "image", "--input", "/scan/image.tar",
		"--skip-db-update", "--skip-java-db-update", "--offline-scan",
		"--cache-backend", "memory", "--cache-dir", cacheDir,
		"--format", "json", "--quiet", "--scanners", "vuln")
}

// runNamed force-removes the named container before and after: killing the
// docker CLI on timeout leaves the container running, and a crash leaves a
// name collision behind. Names carry the scan id, so overlapping wokkud
// processes never remove each other's containers.
func (w *Worker) runNamed(ctx context.Context, name string, args ...string) ([]byte, error) {
	w.run(ctx, "docker", "rm", "-f", name)
	defer w.cleanup("docker", "rm", "-f", name)
	return w.run(ctx, args...)
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// execRun runs docker with the builder's env allowlist (never WOKKUD_TOKEN).
// Errors carry the head of stderr (for classification and the local log;
// the report keeps only the first line); stdout is returned separately.
func execRun(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Env = builder.BuildEnv(os.Environ())
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if len(msg) > 4000 {
			msg = msg[:4000]
		}
		return out, fmt.Errorf("%s %s: %w: %s", args[0], args[min(1, len(args)-1)], err, msg)
	}
	return out, nil
}

var severityRank = map[string]int{"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "UNKNOWN": 0}

type trivyVuln struct {
	VulnerabilityID, PkgName, InstalledVersion, FixedVersion, Severity, Title string
	CVSS                                                                      map[string]struct{ V2Score, V3Score float64 }
}

func (v trivyVuln) score() float64 {
	best := 0.0
	for _, c := range v.CVSS {
		s := c.V3Score
		if s == 0 {
			s = c.V2Score
		}
		best = max(best, s)
	}
	return best
}

// parse turns Trivy's JSON (schema v2) into counts by severity (+ fixable =
// has a FixedVersion) and the top 50 findings by severity, then CVSS.
func parse(raw []byte) (map[string]int, []control.ImageScanFinding, error) {
	var r struct {
		SchemaVersion int
		Results       []struct{ Vulnerabilities []trivyVuln }
	}
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, nil, fmt.Errorf("trivy json: %w", err)
	}
	if r.SchemaVersion != 2 {
		return nil, nil, fmt.Errorf("trivy json: unexpected schema version %d", r.SchemaVersion)
	}
	counts := map[string]int{"critical": 0, "high": 0, "medium": 0, "low": 0, "unknown": 0, "fixable": 0}
	var vulns []trivyVuln
	for _, res := range r.Results {
		for _, v := range res.Vulnerabilities {
			if _, ok := severityRank[v.Severity]; !ok {
				v.Severity = "UNKNOWN"
			}
			counts[strings.ToLower(v.Severity)]++
			if v.FixedVersion != "" {
				counts["fixable"]++
			}
			vulns = append(vulns, v)
		}
	}
	sort.SliceStable(vulns, func(i, j int) bool {
		a, b := vulns[i], vulns[j]
		if ra, rb := severityRank[a.Severity], severityRank[b.Severity]; ra != rb {
			return ra > rb
		}
		if sa, sb := a.score(), b.score(); sa != sb {
			return sa > sb
		}
		return a.VulnerabilityID < b.VulnerabilityID
	})
	findings := []control.ImageScanFinding{}
	for _, v := range vulns[:min(len(vulns), maxFindings)] {
		title := v.Title
		if utf8.RuneCountInString(title) > maxTitle {
			title = string([]rune(title)[:maxTitle])
		}
		findings = append(findings, control.ImageScanFinding{ID: v.VulnerabilityID, Package: v.PkgName,
			Installed: v.InstalledVersion, Fixed: v.FixedVersion, Severity: v.Severity, Title: title})
	}
	return counts, findings, nil
}
