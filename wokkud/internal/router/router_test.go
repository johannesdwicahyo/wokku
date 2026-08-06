package router

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

type fakeFetcher struct {
	cfg   *control.RouterConfig
	err   error
	calls atomic.Int32
}

func (f *fakeFetcher) GetRouterConfig() (*control.RouterConfig, error) {
	f.calls.Add(1)
	if f.err != nil {
		return nil, f.err
	}
	return f.cfg, nil
}

func fakeResolver(dials map[string][]string) resolveFunc {
	return func(ctx context.Context, apps []control.RouterApp) (map[string][]string, error) {
		return dials, nil
	}
}

func erroringResolver(err error) resolveFunc {
	return func(ctx context.Context, apps []control.RouterApp) (map[string][]string, error) {
		return nil, err
	}
}

func newTestManager(t *testing.T, f *fakeFetcher, adminOK bool, validateErr error) (*Manager, *atomic.Int32) {
	t.Helper()
	var loads atomic.Int32
	admin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/load" {
			loads.Add(1)
			if !adminOK {
				http.Error(w, "boom", 500)
			}
		}
	}))
	t.Cleanup(admin.Close)

	m := &Manager{
		fetch:           f,
		dir:             t.TempDir(),
		adminURL:        admin.URL,
		askURL:          "https://cp/ask?token=t",
		resolve:         fakeResolver(map[string][]string{"alpha": {"a:1"}}),
		validate:        func(ctx context.Context, path string) error { return validateErr },
		validateTimeout: 10 * time.Second,
	}
	return m, &loads
}

func testCfg(version string) *control.RouterConfig {
	return &control.RouterConfig{
		Version: version, ListenMode: "shadow",
		Apps: []control.RouterApp{{
			Name: "alpha", ContainerPort: 5000,
			Domains:   []control.RouterDomain{{Hostname: "alpha.wokku.app", TLS: "wildcard"}},
			Upstreams: []control.RouterUpstream{{Local: true}},
		}},
	}
}

// testCfg2 renders to different bytes than testCfg (extra domain hostname)
// so tests can force a real re-apply rather than a bytes.Equal no-op.
func testCfg2(version string) *control.RouterConfig {
	cfg := testCfg(version)
	cfg.Apps[0].Domains = append(cfg.Apps[0].Domains, control.RouterDomain{Hostname: "alpha2.wokku.app", TLS: "wildcard"})
	return cfg
}

func TestSyncAppliesOnVersionChange(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, loads := newTestManager(t, f, true, nil)

	m.Sync(context.Background(), "v1")
	if loads.Load() != 1 {
		t.Fatalf("loads = %d, want 1", loads.Load())
	}
	if _, applied := m.Status(context.Background()); applied != "v1" {
		t.Errorf("applied = %q", applied)
	}
	data, err := os.ReadFile(filepath.Join(m.dir, "config.json"))
	if err != nil || !strings.Contains(string(data), "alpha.wokku.app") {
		t.Errorf("persisted config bad: %v", err)
	}

	// Same version, same rendered bytes → no re-apply, no re-fetch.
	m.Sync(context.Background(), "v1")
	if loads.Load() != 1 || f.calls.Load() != 1 {
		t.Errorf("loads=%d fetches=%d, want 1/1", loads.Load(), f.calls.Load())
	}
}

func TestSyncFailStaticOnValidateError(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, loads := newTestManager(t, f, true, os.ErrInvalid)

	m.Sync(context.Background(), "v1")
	if loads.Load() != 0 {
		t.Errorf("load called despite validate failure")
	}
	if _, applied := m.Status(context.Background()); applied != "" {
		t.Errorf("applied = %q, want empty", applied)
	}
	if _, err := os.Stat(filepath.Join(m.dir, "config.json")); !os.IsNotExist(err) {
		t.Errorf("broken config persisted")
	}
}

func TestSyncFailStaticOnAdminError(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, _ := newTestManager(t, f, false, nil)

	m.Sync(context.Background(), "v1")
	if _, applied := m.Status(context.Background()); applied != "" {
		t.Errorf("applied = %q, want empty after admin failure", applied)
	}
	// Next beat retries (version still != applied → refetch + retry).
	f2 := f.calls.Load()
	m.Sync(context.Background(), "v1")
	if f.calls.Load() != f2+1 {
		t.Errorf("no retry on next beat")
	}
}

func TestSyncReappliesOnUpstreamChurn(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, loads := newTestManager(t, f, true, nil)
	m.Sync(context.Background(), "v1")

	m.resolve = fakeResolver(map[string][]string{"alpha": {"b:2"}}) // container restarted, new IP
	m.Sync(context.Background(), "v1")
	if loads.Load() != 2 {
		t.Errorf("loads = %d, want 2 (re-applied for new upstream)", loads.Load())
	}
}

func TestSyncFailStaticOnResolveError(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, loads := newTestManager(t, f, true, nil)
	m.resolve = erroringResolver(errors.New("docker daemon unreachable"))

	m.Sync(context.Background(), "v1")
	if loads.Load() != 0 {
		t.Errorf("admin /load called despite resolve failure")
	}
	if _, applied := m.Status(context.Background()); applied != "" {
		t.Errorf("applied = %q, want empty after resolve failure", applied)
	}
	if _, err := os.Stat(filepath.Join(m.dir, "config.json")); !os.IsNotExist(err) {
		t.Errorf("config.json written despite resolve failure")
	}
}

func TestSyncFailStaticOnFetchError(t *testing.T) {
	f := &fakeFetcher{err: errors.New("control plane unreachable")}
	m, loads := newTestManager(t, f, true, nil)

	m.Sync(context.Background(), "v1")
	if loads.Load() != 0 {
		t.Errorf("admin /load called despite fetch failure")
	}
	if _, applied := m.Status(context.Background()); applied != "" {
		t.Errorf("applied = %q, want empty after fetch failure", applied)
	}
	if _, err := os.Stat(filepath.Join(m.dir, "config.json")); !os.IsNotExist(err) {
		t.Errorf("config.json written despite fetch failure")
	}
}

// TestSyncRollbackKeepsLastGoodOnReapplyFailure applies v1 successfully,
// then a new version arrives while the admin /load starts failing (Caddy
// restart, bad config, etc). Fail-static must leave the on-disk config.json
// and m.applied exactly as they were after v1 — no partial/broken rollback.
func TestSyncRollbackKeepsLastGoodOnReapplyFailure(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	var failLoad atomic.Bool
	var loads atomic.Int32
	admin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/load" {
			loads.Add(1)
			if failLoad.Load() {
				http.Error(w, "boom", 500)
			}
		}
	}))
	t.Cleanup(admin.Close)

	m := &Manager{
		fetch:           f,
		dir:             t.TempDir(),
		adminURL:        admin.URL,
		askURL:          "https://cp/ask?token=t",
		resolve:         fakeResolver(map[string][]string{"alpha": {"a:1"}}),
		validate:        func(ctx context.Context, path string) error { return nil },
		validateTimeout: 10 * time.Second,
	}

	m.Sync(context.Background(), "v1")
	if loads.Load() != 1 {
		t.Fatalf("loads = %d, want 1 after v1 apply", loads.Load())
	}
	v1Data, err := os.ReadFile(filepath.Join(m.dir, "config.json"))
	if err != nil {
		t.Fatalf("read v1 config.json: %v", err)
	}

	// New config version with a different rendered body; admin /load
	// starts rejecting the re-apply.
	f.cfg = testCfg2("v2")
	failLoad.Store(true)
	m.Sync(context.Background(), "v2")

	if _, applied := m.Status(context.Background()); applied != "v1" {
		t.Errorf("applied = %q, want v1 (rollback held)", applied)
	}
	data, err := os.ReadFile(filepath.Join(m.dir, "config.json"))
	if err != nil {
		t.Fatalf("read config.json after failed re-apply: %v", err)
	}
	if string(data) != string(v1Data) {
		t.Errorf("config.json on disk changed after failed re-apply; want v1 content unchanged")
	}
}

// TestStatusRaceWithSync exercises Status and Sync concurrently under
// `go test -race`: Status must never read m.applied outside m.mu.
func TestStatusRaceWithSync(t *testing.T) {
	f := &fakeFetcher{cfg: testCfg("v1")}
	m, _ := newTestManager(t, f, true, nil)

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			m.Sync(context.Background(), "v1")
		}()
		go func() {
			defer wg.Done()
			m.Status(context.Background())
		}()
	}
	wg.Wait()
}

// writeFakeCaddy installs a stub `caddy` binary on PATH that exits 0
// immediately, or — when the FAKE_CADDY_HANG env var is set at exec time —
// sleeps 30s first, simulating a wedged `caddy validate` subprocess.
func writeFakeCaddy(t *testing.T, dir string) {
	t.Helper()
	// `exec sleep 30` (not a plain `sleep 30`) replaces the shell's process
	// image instead of forking a child — so killing this one process on
	// context cancellation also closes CombinedOutput's stdout/stderr pipe.
	// A forked grandchild would keep the pipe open and Wait() would still
	// block for the full 30s despite the kill.
	script := "#!/bin/sh\nif [ -n \"$FAKE_CADDY_HANG\" ]; then exec sleep 30; fi\nexit 0\n"
	if err := os.WriteFile(filepath.Join(dir, "caddy"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// TestNewAskURLCarriesToken guards the on-demand TLS ask endpoint: Rails'
// tls_allowed action authenticates via `?token=<ingest_token>` query param
// (no header path). If New() ever stops embedding it, every on-demand cert
// request 401s at cutover.
func TestNewAskURLCarriesToken(t *testing.T) {
	writeFakeCaddy(t, t.TempDir())

	m := New(&fakeFetcher{}, "https://cp.example", "secret-token")
	if m == nil {
		t.Fatal("New returned nil with caddy on PATH")
	}
	if !strings.Contains(m.askURL, "token=secret-token") {
		t.Errorf("askURL = %q, want it to carry ?token=secret-token", m.askURL)
	}
	if !strings.HasPrefix(m.askURL, "https://cp.example/api/v1/agent/router/tls_allowed") {
		t.Errorf("askURL = %q, want tls_allowed endpoint", m.askURL)
	}
}

func TestNewNilWithoutCaddyOnPath(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if m := New(&fakeFetcher{}, "https://cp.example", "secret-token"); m != nil {
		t.Errorf("New() = %v, want nil without caddy on PATH", m)
	}
}

// TestSyncBoundsHungCaddyValidate is the regression guard for the
// unbounded-blocking fix: Sync runs synchronously inside the 15s heartbeat
// loop, so a wedged `caddy validate` subprocess must be killed by
// validateTimeout — never left to block forever and freeze every future
// heartbeat.
func TestSyncBoundsHungCaddyValidate(t *testing.T) {
	writeFakeCaddy(t, t.TempDir())
	t.Setenv("FAKE_CADDY_HANG", "1")

	m := New(&fakeFetcher{cfg: testCfg("v1")}, "https://cp.example", "secret-token")
	if m == nil {
		t.Fatal("New returned nil with caddy on PATH")
	}
	m.dir = t.TempDir() // New() hardcodes /etc/wokku/caddy, unwritable in CI
	m.resolve = fakeResolver(map[string][]string{"alpha": {"a:1"}})
	m.validateTimeout = 100 * time.Millisecond // real 10s default would just make the test slow, not wedge it

	done := make(chan struct{})
	go func() {
		m.Sync(context.Background(), "v1")
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Sync did not return; hung caddy validate wedged the beat loop")
	}

	// Fail-static: a validate timeout must leave nothing applied — same
	// contract as TestSyncFailStaticOnValidateError, checked here too since
	// this is the regression guard for the hang path specifically.
	if _, applied := m.Status(context.Background()); applied != "" {
		t.Errorf("applied = %q, want empty after validate timeout", applied)
	}
	if _, err := os.Stat(filepath.Join(m.dir, "config.json")); !os.IsNotExist(err) {
		t.Errorf("config.json present after validate timeout, want absent")
	}
}

func TestHasLocalUpstream(t *testing.T) {
	cases := []struct {
		name string
		ups  []control.RouterUpstream
		want bool
	}{
		{"local only", []control.RouterUpstream{{Local: true}}, true},
		{"dial only (B5a)", []control.RouterUpstream{{Dial: "127.0.0.1:31005"}}, false},
		{"mesh only (B8)", []control.RouterUpstream{{MeshIP: "10.0.0.1", Port: 3000}}, false},
		{"mixed local+mesh", []control.RouterUpstream{{Local: true}, {MeshIP: "10.0.0.1", Port: 3000}}, true},
		{"empty", nil, false},
	}
	for _, c := range cases {
		app := control.RouterApp{Name: "app", Upstreams: c.ups}
		if got := hasLocalUpstream(app); got != c.want {
			t.Errorf("%s: hasLocalUpstream = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestIsWebProcessName(t *testing.T) {
	cases := []struct {
		name string
		want bool
	}{
		{"/app.web.1", true},
		{"/app.web.12", true},
		{"/app.web.1.upcoming-32552", false}, // dokku staging container (shadow soak catch)
		{"/app.web.", false},
		{"/app.web.x", false},
		{"/app.worker.1", false},
		{"/other-app.web.1", false},
	}
	for _, c := range cases {
		if got := isWebProcessName(c.name, "/app.web."); got != c.want {
			t.Errorf("isWebProcessName(%q) = %v, want %v", c.name, got, c.want)
		}
	}
}
