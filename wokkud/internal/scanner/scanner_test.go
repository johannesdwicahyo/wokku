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

func versionJSON(downloaded time.Time) []byte {
	b, _ := json.Marshal(map[string]any{"Version": "0.76.2", "VulnerabilityDB": map[string]any{
		"UpdatedAt": "2026-11-27T00:00:00Z", "DownloadedAt": downloaded.Format(time.RFC3339)}})
	return b
}

// happy answers like a host with a fresh DB and the image in the local store.
func happy(t *testing.T, downloaded time.Time) func(context.Context, []string) ([]byte, error) {
	fixture, _ := os.ReadFile("testdata/trivy-0.76.2.json")
	return func(ctx context.Context, args []string) ([]byte, error) {
		joined := strings.Join(args, " ")
		switch {
		case strings.Contains(joined, " version --format json"):
			return versionJSON(downloaded), nil
		case strings.Contains(joined, "--input"):
			return fixture, nil
		}
		return nil, nil
	}
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

func newTestWorker(cp *controlPlane, f *fake, now time.Time) *Worker {
	w := newWorker(control.New(cp.srv.URL, "tok", "test"), func() bool { return false })
	w.run = f.run
	w.now = func() time.Time { return now }
	return w
}

func TestScanSucceedsWithIsolatedPinnedCommand(t *testing.T) {
	now := time.Date(2026, 11, 27, 12, 0, 0, 0, time.UTC)
	cp := newControlPlane(t, 300)
	f := &fake{respond: happy(t, now.Add(-time.Hour))}
	w := newTestWorker(cp, f, now)
	w.scanOne(context.Background(), "scan-1")

	if len(cp.reports) != 1 || cp.reports[0].Status != "succeeded" || cp.reports[0].Counts["critical"] != 1 || len(cp.reports[0].Findings) != 7 {
		t.Fatalf("reports %+v", cp.reports)
	}
	if r := cp.reports[0]; r.ScannerVersion != "0.76.2" || r.DBUpdatedAt != "2026-11-27T00:00:00Z" {
		t.Fatalf("meta %+v", r)
	}
	scan := strings.Join(f.find("--input"), " ")
	for _, want := range []string{"--network none", "--read-only", "--cap-drop ALL", "--security-opt no-new-privileges",
		"--memory 2g", "--pids-limit 512", "--cpus 2", "--tmpfs /tmp", "wokku-trivy-cache:/root/.cache/trivy:ro",
		":/scan/image.tar:ro", TrivyImage + " image", "--skip-db-update", "--offline-scan", "--format json", "--quiet", "--scanners vuln"} {
		if !strings.Contains(scan, want) {
			t.Errorf("scan command missing %q: %s", want, scan)
		}
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
	if save := f.find("docker save"); save == nil {
		t.Error("image must be docker-saved to a tar")
	} else if _, err := os.Stat(save[3]); !os.IsNotExist(err) {
		t.Errorf("temp tar left behind: %s", save[3])
	}
}

func TestStaleDBIsRefreshedWithNetwork(t *testing.T) {
	now := time.Date(2026, 11, 27, 12, 0, 0, 0, time.UTC)
	cp := newControlPlane(t, 300)
	f := &fake{respond: happy(t, now.Add(-25*time.Hour))}
	w := newTestWorker(cp, f, now)
	w.scanOne(context.Background(), "scan-1")

	dl := strings.Join(f.find("--download-db-only"), " ")
	if dl == "" || strings.Contains(dl, "--network none") || !strings.Contains(dl, "wokku-trivy-cache:/root/.cache/trivy ") || !strings.Contains(dl, TrivyImage) {
		t.Fatalf("refresh command: %q", dl)
	}
}

func TestNoDBAndRefreshFailsIsDBUnavailable(t *testing.T) {
	cp := newControlPlane(t, 300)
	f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
		if strings.Contains(strings.Join(args, " "), " version ") || strings.Contains(strings.Join(args, " "), "--download-db-only") {
			return nil, errors.New("boom")
		}
		return nil, nil
	}}
	newTestWorker(cp, f, time.Now()).scanOne(context.Background(), "scan-1")
	if len(cp.reports) != 1 || cp.reports[0].ErrorCode != "db_unavailable" {
		t.Fatalf("%+v", cp.reports)
	}
}

func TestTimeoutMapsToTimeout(t *testing.T) {
	now := time.Now()
	cp := newControlPlane(t, 1)
	h := happy(t, now)
	f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
		if strings.Contains(strings.Join(args, " "), "--input") {
			<-ctx.Done()
			return nil, ctx.Err()
		}
		return h(ctx, args)
	}}
	newTestWorker(cp, f, now).scanOne(context.Background(), "scan-1")
	if len(cp.reports) != 1 || cp.reports[0].Status != "failed" || cp.reports[0].ErrorCode != "timeout" {
		t.Fatalf("%+v", cp.reports)
	}
	if f.find("rm -f wokku-trivy-scan") == nil {
		t.Error("a timed-out scan container must be force-removed")
	}
}

type exitErr int

func (e exitErr) Error() string { return "exit" }
func (e exitErr) ExitCode() int { return int(e) }

func TestErrorCodes(t *testing.T) {
	now := time.Now()
	for _, tc := range []struct {
		name, match, want string
		err               error
	}{
		{"oom", "--input", "oom", exitErr(137)},
		{"pull", "docker pull", "pull_failed", errors.New("connection refused")},
		{"missing", "docker pull", "image_missing", errors.New("manifest unknown")},
		{"save", "docker save", "image_missing", errors.New("no such image")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cp := newControlPlane(t, 300)
			h := happy(t, now)
			f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
				j := strings.Join(args, " ")
				if strings.Contains(j, "image inspect") {
					return nil, errors.New("not local")
				}
				if strings.Contains(j, tc.match) {
					return nil, tc.err
				}
				return h(ctx, args)
			}}
			newTestWorker(cp, f, now).scanOne(context.Background(), "scan-1")
			if len(cp.reports) != 1 || cp.reports[0].ErrorCode != tc.want {
				t.Fatalf("%+v", cp.reports)
			}
		})
	}
	t.Run("parse", func(t *testing.T) {
		cp := newControlPlane(t, 300)
		h := happy(t, now)
		f := &fake{respond: func(ctx context.Context, args []string) ([]byte, error) {
			if strings.Contains(strings.Join(args, " "), "--input") {
				return []byte("{garbage"), nil
			}
			return h(ctx, args)
		}}
		newTestWorker(cp, f, now).scanOne(context.Background(), "scan-1")
		if len(cp.reports) != 1 || cp.reports[0].ErrorCode != "parse_failed" {
			t.Fatalf("%+v", cp.reports)
		}
	})
}

func TestRefOutsideLoopbackRegistryIsRefused(t *testing.T) {
	for _, bad := range []string{"docker.io/library/nginx:1", "--help", "127.0.0.1:5000"} {
		if rep, ok := checkRef(bad); ok || rep.ErrorCode != "image_missing" {
			t.Errorf("%q accepted", bad)
		}
	}
	if _, ok := checkRef(ref); !ok {
		t.Error("loopback ref refused")
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
