package scanner

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"

	"wokku.cloud/wokkud/internal/control"
)

const ref = "127.0.0.1:5000/wokku/blog:7f0c1d2e"

func TestParseFixture(t *testing.T) {
	raw, err := os.ReadFile("testdata/trivy-0.76.2.json")
	if err != nil {
		t.Fatal(err)
	}
	counts, findings, err := parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{"critical": 1, "high": 3, "medium": 1, "low": 1, "unknown": 1, "fixable": 4}
	if !reflect.DeepEqual(counts, want) {
		t.Fatalf("counts %v", counts)
	}
	var ids []string
	for _, f := range findings {
		ids = append(ids, f.ID)
	}
	// severity, then highest CVSS, then id for ties
	wantIDs := []string{"CVE-2026-0002", "CVE-2026-0003", "CVE-2026-0001", "CVE-2026-0004", "GHSA-abcd-1234-efgh", "CVE-2025-9999", "CVE-2025-1234"}
	if !reflect.DeepEqual(ids, wantIDs) {
		t.Fatalf("order %v", ids)
	}
	if f := findings[2]; f.Package != "libssl3" || f.Installed != "3.0.15-1~deb12u1" || f.Fixed != "3.0.16-1~deb12u1" || f.Severity != "HIGH" {
		t.Fatalf("finding %+v", f)
	}
	if n := utf8.RuneCountInString(findings[1].Title); n != 160 {
		t.Fatalf("title not capped at 160: %d", n)
	}
}

func TestParseCapsAt50(t *testing.T) {
	var vulns []string
	for i := 0; i < 70; i++ {
		vulns = append(vulns, `{"VulnerabilityID":"CVE-`+string(rune('a'+i%26))+`","Severity":"LOW"}`)
	}
	raw := `{"SchemaVersion":2,"Results":[{"Vulnerabilities":[` + strings.Join(vulns, ",") + `]}]}`
	counts, findings, err := parse([]byte(raw))
	if err != nil || len(findings) != 50 || counts["low"] != 70 {
		t.Fatalf("%v %d %v", err, len(findings), counts)
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	for _, raw := range []string{"", "not json", `{"SchemaVersion":1}`} {
		if _, _, err := parse([]byte(raw)); err == nil {
			t.Errorf("%q parsed", raw)
		}
	}
}

// fake records every docker invocation and answers via respond.
type fake struct {
	mu      sync.Mutex
	calls   [][]string
	respond func(ctx context.Context, args []string) ([]byte, error)
}

func (f *fake) run(ctx context.Context, args ...string) ([]byte, error) {
	f.mu.Lock()
	f.calls = append(f.calls, args)
	f.mu.Unlock()
	if f.respond != nil {
		return f.respond(ctx, args)
	}
	return nil, nil
}

func (f *fake) find(sub string) []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, c := range f.calls {
		if strings.Contains(strings.Join(c, " "), sub) {
			return c
		}
	}
	return nil
}

func (f *fake) count(sub string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.calls {
		if strings.Contains(strings.Join(c, " "), sub) {
			n++
		}
	}
	return n
}

func versionJSON(downloaded time.Time, java bool, javaDownloaded time.Time) []byte {
	db := map[string]any{"UpdatedAt": "2026-11-27T00:00:00Z", "DownloadedAt": downloaded.Format(time.RFC3339)}
	v := map[string]any{"Version": "0.76.2", "VulnerabilityDB": db}
	if java {
		if javaDownloaded.IsZero() {
			javaDownloaded = downloaded
		}
		v["JavaDB"] = map[string]any{"UpdatedAt": "2026-11-26T00:00:00Z", "DownloadedAt": javaDownloaded.Format(time.RFC3339)}
	}
	b, _ := json.Marshal(v)
	return b
}

// host is a scriptable docker host: fresh DBs, the image in the local store.
type host struct {
	downloaded time.Time
	java       bool
	javaAt     time.Time // Java DB DownloadedAt; zero: same as downloaded
	local      bool      // image already in the local store
	fail       map[string]error
}

func (h *host) respond(ctx context.Context, args []string) ([]byte, error) {
	joined := strings.Join(args, " ")
	for sub, err := range h.fail {
		if strings.Contains(joined, sub) {
			return nil, err
		}
	}
	switch {
	case strings.Contains(joined, "docker pull -q "+ref):
		h.local = true
		return nil, nil
	case strings.Contains(joined, " version --format json"):
		return versionJSON(h.downloaded, h.java, h.javaAt), nil
	case strings.Contains(joined, "image inspect") && strings.Contains(joined, ref):
		if !h.local {
			return nil, errors.New("No such image")
		}
		return []byte("1000000\n"), nil
	case strings.Contains(joined, "--input"):
		return os.ReadFile("testdata/trivy-0.76.2.json")
	}
	return nil, nil
}

type controlPlane struct {
	srv     *httptest.Server
	mu      sync.Mutex
	claims  int
	reports []control.ImageScanReport
}

func newControlPlane(t *testing.T, timeout int) *controlPlane {
	cp := &controlPlane{}
	cp.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cp.mu.Lock()
		defer cp.mu.Unlock()
		switch {
		case strings.HasSuffix(r.URL.Path, "/claim"):
			cp.claims++
			json.NewEncoder(w).Encode(map[string]any{"image_ref": ref, "timeout_seconds": timeout})
		case strings.HasSuffix(r.URL.Path, "/report"):
			var rep control.ImageScanReport
			json.NewDecoder(r.Body).Decode(&rep)
			cp.reports = append(cp.reports, rep)
		}
	}))
	t.Cleanup(cp.srv.Close)
	return cp
}

var now = time.Date(2026, 11, 27, 12, 0, 0, 0, time.UTC)

func newTestWorker(cp *controlPlane, f *fake) *Worker {
	w := newWorker(control.New(cp.srv.URL, "tok", "test"), func() bool { return false })
	w.run = f.run
	w.now = func() time.Time { return now }
	w.statfs = func(string) (uint64, uint64, error) { return 100 << 30, 200 << 30, nil } // 100 of 200 GiB free
	return w
}

// scan runs one claimed scan against h and returns the single report.
func scan(t *testing.T, h *host, tweak func(*Worker)) (*fake, control.ImageScanReport) {
	t.Helper()
	cp := newControlPlane(t, 300)
	f := &fake{respond: h.respond}
	w := newTestWorker(cp, f)
	if tweak != nil {
		tweak(w)
	}
	w.scanOne(context.Background(), "scan-1")
	if len(cp.reports) != 1 {
		t.Fatalf("reports %+v", cp.reports)
	}
	return f, cp.reports[0]
}

func TestScanSucceedsWithIsolatedPinnedCommand(t *testing.T) {
	f, r := scan(t, &host{downloaded: now.Add(-time.Hour), java: true, local: true}, nil)
	if r.Status != "succeeded" || r.Counts["critical"] != 1 || len(r.Findings) != 7 {
		t.Fatalf("report %+v", r)
	}
	if r.ScannerVersion != "0.76.2" || r.DBUpdatedAt != "2026-11-27T00:00:00Z" {
		t.Fatalf("meta %+v", r)
	}
	scan := strings.Join(f.find("--input"), " ")
	for _, want := range []string{"--name wokku-trivy-scan-scan-1 ", "--network none", "--read-only", "--cap-drop ALL", "--security-opt no-new-privileges",
		"--memory 2g", "--pids-limit 512", "--cpus 2", "--tmpfs /tmp:rw,size=1g", "wokku-trivy-cache:/root/.cache/trivy:ro",
		":/scan/image.tar:ro", TrivyImage + " image", "--skip-db-update", "--skip-java-db-update", "--offline-scan", "--format json", "--quiet", "--scanners vuln"} {
		if !strings.Contains(scan, want) {
			t.Errorf("scan command missing %q: %s", want, scan)
		}
	}
	if strings.Contains(scan, "--disable-analyzers") {
		t.Errorf("--disable-analyzers is not a v0.76.2 CLI flag: %s", scan)
	}
	if strings.Contains(scan, "docker.sock") || strings.Contains(scan, ref) {
		t.Errorf("scanner must not get the docker socket or the registry ref: %s", scan)
	}
	if !strings.HasPrefix(TrivyImage, "aquasec/trivy@sha256:") || len(TrivyImage) != len("aquasec/trivy@sha256:")+64 {
		t.Errorf("TrivyImage not digest-pinned: %s", TrivyImage)
	}
	for _, c := range f.calls {
		if strings.Contains(strings.Join(c, " "), "latest") {
			t.Errorf("latest in %v", c)
		}
	}
	if f.find("--download-db-only") != nil {
		t.Error("fresh DB must not be refreshed")
	}
	if f.find("docker rmi") != nil {
		t.Error("an image that was already local must not be removed")
	}
	if v := strings.Join(f.find(" version "), " "); !strings.Contains(v, "--name wokku-trivy-version-scan-1 ") {
		t.Errorf("version container not named: %s", v)
	}
	if f.find("rm -f wokku-trivy-version-scan-1") == nil {
		t.Error("version container not cleaned up")
	}
	if save := f.find("docker save"); save == nil {
		t.Error("image must be docker-saved to a tar")
	} else if _, err := os.Stat(save[3]); !os.IsNotExist(err) {
		t.Errorf("temp tar left behind: %s", save[3])
	}
}

// v0.76.2 has no CLI flag to disable the jar analyzer: the scan always
// passes --skip-java-db-update, Java DB or not. A JAR image without one
// fails with "Java DB update failed" → db_unavailable.
func TestScanWithoutJavaDB(t *testing.T) {
	f, r := scan(t, &host{downloaded: now.Add(-time.Hour), local: true}, nil)
	if r.Status != "succeeded" {
		t.Fatalf("%+v", r)
	}
	args := strings.Join(f.find("--input"), " ")
	if !strings.Contains(args, "--skip-java-db-update") || strings.Contains(args, "--disable-analyzers") {
		t.Fatalf("scan args: %s", args)
	}
	_, r = scan(t, &host{downloaded: now.Add(-time.Hour), local: true,
		fail: map[string]error{"--input": errors.New("docker run: exit status 1: FATAL Java DB update failed: --skip-java-db-update cannot be specified on the first run")}}, nil)
	if r.ErrorCode != "db_unavailable" {
		t.Fatalf("%+v", r)
	}
}

func TestStaleDBRefreshesBothDBsWithNetwork(t *testing.T) {
	f, _ := scan(t, &host{downloaded: now.Add(-25 * time.Hour), java: true, javaAt: now.Add(-8 * 24 * time.Hour), local: true}, nil)
	for _, flag := range []string{"--download-db-only", "--download-java-db-only"} {
		dl := strings.Join(f.find(flag), " ")
		if dl == "" || strings.Contains(dl, "--network none") || !strings.Contains(dl, "wokku-trivy-cache:/root/.cache/trivy ") ||
			!strings.Contains(dl, TrivyImage) || !strings.Contains(dl, "--name wokku-trivy-db-scan-1 ") || !strings.Contains(dl, "--cache-dir /root/.cache/trivy --quiet") {
			t.Errorf("%s command: %q", flag, dl)
		}
	}
}

func TestJavaDBRefreshFailureOnlyLogs(t *testing.T) {
	_, r := scan(t, &host{downloaded: now.Add(-25 * time.Hour), local: true,
		fail: map[string]error{"--download-java-db-only": errors.New("boom")}}, nil)
	if r.Status != "succeeded" {
		t.Fatalf("%+v", r)
	}
}

func TestRefreshBacksOffForAnHour(t *testing.T) {
	cp := newControlPlane(t, 300)
	h := &host{downloaded: now.Add(-25 * time.Hour), java: true, local: true, fail: map[string]error{"--download-db-only": errors.New("no egress")}}
	f := &fake{respond: h.respond}
	w := newTestWorker(cp, f)
	w.scanOne(context.Background(), "scan-1")
	w.scanOne(context.Background(), "scan-2")
	if n := f.count("--download-db-only"); n != 1 {
		t.Fatalf("refresh attempts within the hour: %d", n)
	}
	w.now = func() time.Time { return now.Add(61 * time.Minute) }
	w.scanOne(context.Background(), "scan-3")
	if n := f.count("--download-db-only"); n != 2 {
		t.Fatalf("refresh not retried after the hour: %d", n)
	}
	for _, r := range cp.reports {
		if r.Status != "succeeded" { // stale DB still scans
			t.Fatalf("%+v", r)
		}
	}
}

func TestNoDBAndRefreshFailsIsDBUnavailable(t *testing.T) {
	_, r := scan(t, &host{local: true, fail: map[string]error{" version ": errors.New("boom"), "--download-db-only": errors.New("boom")}}, nil)
	if r.ErrorCode != "db_unavailable" {
		t.Fatalf("%+v", r)
	}
}

func TestPulledImageIsRemovedAfterTheScan(t *testing.T) {
	f, r := scan(t, &host{downloaded: now.Add(-time.Hour), java: true}, nil)
	if r.Status != "succeeded" || f.find("docker pull -q "+ref) == nil {
		t.Fatalf("%+v", r)
	}
	if rmi := f.find("docker rmi"); strings.Join(rmi, " ") != "docker rmi "+ref {
		t.Fatalf("rmi: %v", rmi)
	}
}

func TestDiskPrecheck(t *testing.T) {
	for name, fs := range map[string][2]uint64{
		"under size+2GiB": {2 << 30, 200 << 30}, // 2 GiB free < 1 MB + 2 GiB
		"85% used":        {29 << 30, 200 << 30},
	} {
		t.Run(name, func(t *testing.T) {
			f, r := scan(t, &host{downloaded: now.Add(-time.Hour), java: true, local: true}, func(w *Worker) {
				w.statfs = func(string) (uint64, uint64, error) { return fs[0], fs[1], nil }
			})
			if r.ErrorCode != "disk_full" || f.find("docker save") != nil {
				t.Fatalf("%+v", r)
			}
		})
	}
}

func TestTimeoutMapsToTimeout(t *testing.T) {
	cp := newControlPlane(t, 1)
	h := &host{downloaded: now, java: true, local: true}
	f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
		if strings.Contains(strings.Join(args, " "), "--input") {
			<-ctx.Done()
			return nil, ctx.Err()
		}
		return h.respond(ctx, args)
	}}
	newTestWorker(cp, f).scanOne(context.Background(), "scan-1")
	if len(cp.reports) != 1 || cp.reports[0].Status != "failed" || cp.reports[0].ErrorCode != "timeout" {
		t.Fatalf("%+v", cp.reports)
	}
	if f.find("rm -f wokku-trivy-scan-scan-1") == nil {
		t.Error("a timed-out scan container must be force-removed")
	}
}

func TestBuildStartingMidScanAborts(t *testing.T) {
	busy := false
	h := &host{downloaded: now.Add(-time.Hour), java: true, local: true}
	f, r := scan(t, h, func(w *Worker) {
		w.Busy = func() bool { return busy }
		inner := w.run
		w.run = func(ctx context.Context, args ...string) ([]byte, error) {
			if args[1] == "save" {
				busy = true // a build claimed while we were saving
			}
			return inner(ctx, args...)
		}
	})
	if r.ErrorCode != "timeout" || f.find("--input") != nil {
		t.Fatalf("scan ran alongside a build: %+v", r)
	}
}

type exitErr int

func (e exitErr) Error() string { return "exit" }
func (e exitErr) ExitCode() int { return int(e) }

func TestErrorCodes(t *testing.T) {
	for _, tc := range []struct {
		name, match, want string
		err               error
		local             bool
	}{
		{"oom", "--input", "oom", exitErr(137), true},
		{"pull", "docker pull -q " + ref, "pull_failed", errors.New("connection refused"), false},
		{"missing", "docker pull -q " + ref, "image_missing", errors.New("manifest unknown"), false},
		{"save", "docker save", "image_missing", errors.New("no such image"), true},
		{"save enospc", "docker save", "disk_full", errors.New("write /tmp/x: no space left on device"), true},
		{"scan enospc", "--input", "disk_full", errors.New("docker run: exit status 1: no space left on device"), true},
		{"trivy image pull", "docker pull -q " + TrivyImage, "pull_failed", errors.New("toomanyrequests"), true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fail := map[string]error{tc.match: tc.err}
			if tc.name == "trivy image pull" {
				fail["image inspect "+TrivyImage] = errors.New("No such image")
			}
			_, r := scan(t, &host{downloaded: now.Add(-time.Hour), java: true, local: tc.local, fail: fail}, nil)
			if r.ErrorCode != tc.want {
				t.Fatalf("%+v", r)
			}
		})
	}
	t.Run("parse", func(t *testing.T) {
		cp := newControlPlane(t, 300)
		h := &host{downloaded: now, java: true, local: true}
		f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
			if strings.Contains(strings.Join(args, " "), "--input") {
				return []byte("{garbage"), nil
			}
			return h.respond(ctx, args)
		}}
		newTestWorker(cp, f).scanOne(context.Background(), "scan-1")
		if len(cp.reports) != 1 || cp.reports[0].ErrorCode != "parse_failed" {
			t.Fatalf("%+v", cp.reports)
		}
	})
}

func TestErrorTextIsFirstStderrLine(t *testing.T) {
	_, r := scan(t, &host{downloaded: now.Add(-time.Hour), java: true, local: true,
		fail: map[string]error{"--input": errors.New("docker run: exit status 1: FATAL scan error\n  stack line\n  more")}}, nil)
	if r.Error != "docker run: exit status 1: FATAL scan error" {
		t.Fatalf("%q", r.Error)
	}
}

func TestRefOutsideLoopbackRegistryIsRefused(t *testing.T) {
	for _, bad := range []string{"docker.io/library/nginx:1", "--help", "127.0.0.1:5000", "127.0.0.1:5000/wokku/blog",
		"127.0.0.1:5000/Wokku/blog:1", "127.0.0.1:5000/wokku/blog:1 --rm", "127.0.0.1:5000/wokku/blog@sha256:abc"} {
		if rep, ok := checkRef(bad); ok || rep.ErrorCode != "image_missing" {
			t.Errorf("%q accepted", bad)
		}
	}
	for _, good := range []string{ref, "127.0.0.1:5000/wokku/blog@sha256:" + strings.Repeat("a", 64)} {
		if _, ok := checkRef(good); !ok {
			t.Errorf("%q refused", good)
		}
	}
}

func TestWorkerSkipsWhileBusy(t *testing.T) {
	cp := newControlPlane(t, 300)
	w := newWorker(control.New(cp.srv.URL, "tok", "test"), func() bool { return true })
	w.run = (&fake{}).run
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.work(ctx)
	w.Enqueue("scan-1")
	time.Sleep(100 * time.Millisecond)
	cp.mu.Lock()
	defer cp.mu.Unlock()
	if cp.claims != 0 {
		t.Fatal("claimed while a build was running")
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.inFlight["scan-1"] {
		t.Fatal("skipped id must be released so the next heartbeat re-delivers it")
	}
}

// The Java DB (~1 GB) refreshes weekly, the vulnerability DB daily.
func TestJavaDBRefreshesWeekly(t *testing.T) {
	for _, tc := range []struct {
		name           string
		db, java       time.Duration // age; java < 0: no Java DB
		wantDB, wantJV bool
	}{
		{"db stale, java 3 days", 25 * time.Hour, 3 * 24 * time.Hour, true, false},
		{"db fresh, java 8 days", time.Hour, 8 * 24 * time.Hour, false, true},
		{"db fresh, java missing", time.Hour, -1, false, true},
		{"both fresh", time.Hour, 6 * 24 * time.Hour, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := &host{downloaded: now.Add(-tc.db), local: true, java: tc.java >= 0}
			if tc.java >= 0 {
				h.javaAt = now.Add(-tc.java)
			}
			f, r := scan(t, h, nil)
			if r.Status != "succeeded" {
				t.Fatalf("%+v", r)
			}
			if got := f.find("--download-db-only") != nil; got != tc.wantDB {
				t.Errorf("vuln DB download = %v", got)
			}
			if got := f.find("--download-java-db-only") != nil; got != tc.wantJV {
				t.Errorf("Java DB download = %v", got)
			}
		})
	}
}
