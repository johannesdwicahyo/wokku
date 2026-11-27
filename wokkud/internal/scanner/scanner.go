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
	"sort"
	"strings"
	"sync"
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
	scanContainer  = "wokku-trivy-scan"
	dbContainer    = "wokku-trivy-db"
	registryPrefix = "127.0.0.1:5000/" // scans only read the host's loopback registry
	dbMaxAge       = 24 * time.Hour
	defaultTimeout = 300
	maxFindings    = 50
	maxTitle       = 160
)

type runFunc func(ctx context.Context, args ...string) ([]byte, error)

// Worker serialises scans: one at a time per host, never while a build runs
// (the heartbeat can hand out a new id while one is still claimed — it just
// queues). ponytail: single worker, same as builder.Executor.
type Worker struct {
	Busy func() bool // builder.Executor.Busy

	client   *control.Client
	run      runFunc
	now      func() time.Time
	queue    chan string
	mu       sync.Mutex
	inFlight map[string]bool

	db dbInfo // owned by the work goroutine
}

type dbInfo struct {
	version      string
	updatedAt    string
	downloadedAt time.Time
}

func NewWorker(ctx context.Context, client *control.Client, busy func() bool) *Worker {
	w := newWorker(client, busy)
	go w.work(ctx)
	return w
}

func newWorker(client *control.Client, busy func() bool) *Worker {
	return &Worker{Busy: busy, client: client, run: execRun, now: time.Now, queue: make(chan string, 16), inFlight: map[string]bool{}}
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
	rep := w.scan(ctx, job.ImageRef)
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

func (w *Worker) scan(ctx context.Context, ref string) control.ImageScanReport {
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
		}
		return failed(code, err.Error())
	}

	if err := w.ensureDB(ctx); err != nil {
		return fail("db_unavailable", err)
	}

	if _, err := w.run(ctx, "docker", "image", "inspect", ref); err != nil {
		if _, err := w.run(ctx, "docker", "pull", "-q", ref); err != nil {
			code := "pull_failed"
			if msg := err.Error(); strings.Contains(msg, "manifest unknown") || strings.Contains(msg, "not found") {
				code = "image_missing"
			}
			return fail(code, err)
		}
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

	out, err := w.runNamed(ctx, scanContainer, scanArgs(tar)...)
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

// checkRef refuses anything but an image in the host's loopback registry —
// the scan must never pull from the internet on the control plane's say-so,
// and a ref starting with "-" would be read as a docker flag.
func checkRef(ref string) (control.ImageScanReport, bool) {
	if !strings.HasPrefix(ref, registryPrefix) || len(ref) == len(registryPrefix) {
		return failed("image_missing", "image ref not in the local registry: "+ref), false
	}
	return control.ImageScanReport{}, true
}

func failed(code, msg string) control.ImageScanReport {
	if len(msg) > 500 {
		msg = msg[len(msg)-500:]
	}
	return control.ImageScanReport{Status: "failed", ErrorCode: code, Error: msg}
}

// ensureDB refreshes the vulnerability DB when it is older than 24 h. A
// failed refresh with a DB already cached scans against the stale one (the
// report carries db_updated_at); with no DB at all it's db_unavailable.
// ponytail: a failing refresh is retried on every scan — add a backoff if a
// host with no egress ever scans often.
func (w *Worker) ensureDB(ctx context.Context) error {
	if w.db.downloadedAt.IsZero() {
		w.db = w.readDB(ctx)
	}
	if w.now().Sub(w.db.downloadedAt) < dbMaxAge {
		return nil
	}
	// The only networked run: default bridge network, its own container.
	_, err := w.runNamed(ctx, dbContainer, append(hardened(dbContainer),
		"-v", cacheVolume+":"+cacheDir, TrivyImage,
		"image", "--download-db-only", "--cache-dir", cacheDir, "--quiet")...)
	if err != nil {
		if w.db.downloadedAt.IsZero() {
			return err
		}
		log.Printf("wokkud: trivy DB refresh failed, scanning with the DB from %s: %v", w.db.updatedAt, err)
		return nil
	}
	w.db = w.readDB(ctx)
	if w.db.downloadedAt.IsZero() {
		return errors.New("trivy DB missing after refresh")
	}
	return nil
}

// readDB asks the pinned Trivy for its version and the cached DB's metadata
// (offline, cache read-only). Zero value when there is no DB yet.
func (w *Worker) readDB(ctx context.Context) dbInfo {
	out, err := w.run(ctx, append(hardened(""), "--network", "none",
		"-v", cacheVolume+":"+cacheDir+":ro", TrivyImage,
		"version", "--format", "json", "--cache-dir", cacheDir)...)
	if err != nil {
		return dbInfo{}
	}
	var v struct {
		Version         string
		VulnerabilityDB *struct {
			UpdatedAt    time.Time
			DownloadedAt time.Time
		}
	}
	if json.Unmarshal(out, &v) != nil || v.VulnerabilityDB == nil {
		return dbInfo{}
	}
	return dbInfo{version: v.Version, updatedAt: v.VulnerabilityDB.UpdatedAt.UTC().Format(time.RFC3339), downloadedAt: v.VulnerabilityDB.DownloadedAt}
}

// hardened is the shared `docker run` prefix: read-only rootfs, no caps, no
// privilege escalation, memory/pids/CPU caps (WOKKUD_SCAN_MEMORY / _PIDS /
// _CPUS override 2g / 512 / 2). Network is the caller's choice.
func hardened(name string) []string {
	mem := env("WOKKUD_SCAN_MEMORY", "2g")
	args := []string{"docker", "run", "--rm"}
	if name != "" {
		args = append(args, "--name", name)
	}
	return append(args, "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
		"--memory", mem, "--memory-swap", mem, // swap == memory: no swap escape
		"--pids-limit", env("WOKKUD_SCAN_PIDS", "512"), "--cpus", env("WOKKUD_SCAN_CPUS", "2"),
		"--tmpfs", "/tmp")
}

// scanArgs: the image arrives as a read-only `docker save` tar — no docker
// socket, no registry, no network inside the scanner.
func scanArgs(tar string) []string {
	return append(hardened(scanContainer), "--network", "none",
		"-v", cacheVolume+":"+cacheDir+":ro",
		"-v", tar+":/scan/image.tar:ro",
		TrivyImage, "image", "--input", "/scan/image.tar",
		"--skip-db-update", "--skip-java-db-update", "--offline-scan",
		"--cache-backend", "memory", "--cache-dir", cacheDir,
		"--format", "json", "--quiet", "--scanners", "vuln")
}

// runNamed force-removes the named container before and after: killing the
// docker CLI on timeout leaves the container running, and a crash leaves a
// name collision behind.
func (w *Worker) runNamed(ctx context.Context, name string, args ...string) ([]byte, error) {
	w.run(ctx, "docker", "rm", "-f", name)
	defer w.run(context.Background(), "docker", "rm", "-f", name)
	return w.run(ctx, args...)
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// execRun runs docker with the builder's env allowlist (never WOKKUD_TOKEN).
// Errors carry the stderr tail; stdout is returned separately (Trivy JSON).
func execRun(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Env = builder.BuildEnv(os.Environ())
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if len(msg) > 400 {
			msg = msg[len(msg)-400:]
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
