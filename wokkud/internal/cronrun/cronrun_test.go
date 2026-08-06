package cronrun

import (
	"errors"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeRunner struct {
	mu    sync.Mutex
	calls []Entry
	envs  []map[string]string
	block chan struct{} // non-nil => Run blocks until closed
	exit  int
	out   string
}

func (f *fakeRunner) Run(e Entry, env map[string]string) (int, string) {
	f.mu.Lock()
	f.calls = append(f.calls, e)
	f.envs = append(f.envs, env)
	f.mu.Unlock()
	if f.block != nil {
		<-f.block
	}
	out := f.out
	if out == "" {
		out = "out"
	}
	return f.exit, out
}

type fakeAPI struct {
	cfg     *Config
	runs    []Run
	mu      sync.Mutex
	envErr  error
	env     map[string]string
	postErr error
}

func (f *fakeAPI) GetCronConfig() (*Config, error) { return f.cfg, nil }
func (f *fakeAPI) GetAppEnv(string) (map[string]string, error) {
	if f.envErr != nil {
		return nil, f.envErr
	}
	if f.env != nil {
		return f.env, nil
	}
	return map[string]string{"A": "1"}, nil
}
func (f *fakeAPI) PostCronRuns(rs []Run) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.runs = append(f.runs, rs...)
	return f.postErr
}

func TestApplySwapsSchedule(t *testing.T) {
	s := NewScheduler(&fakeAPI{}, &fakeRunner{})
	cfg := &Config{Version: "v1", Entries: []Entry{{ID: "t1", App: "a", Schedule: "* * * * *", Command: "true"}}}
	if err := s.Apply(cfg); err != nil {
		t.Fatal(err)
	}
	if s.AppliedVersion() != "v1" {
		t.Fatalf("version %s", s.AppliedVersion())
	}
	if err := s.Apply(&Config{Version: "v2"}); err != nil { // empty entries = all removed
		t.Fatal(err)
	}
	if got := len(s.cron.Entries()); got != 0 {
		t.Fatalf("expected empty schedule, got %d", got)
	}
	if s.AppliedVersion() != "v2" {
		t.Fatalf("version after second apply = %s", s.AppliedVersion())
	}
}

func TestApplyRejectsBadSchedule(t *testing.T) {
	s := NewScheduler(&fakeAPI{}, &fakeRunner{})
	err := s.Apply(&Config{Version: "vX", Entries: []Entry{{ID: "t", Schedule: "not-cron", Command: "x"}}})
	if err == nil {
		t.Fatal("want error")
	}
	if s.AppliedVersion() == "vX" {
		t.Fatal("bad config must not become applied")
	}
}

// A bad new config must not tear down a previously-applied good schedule
// (fail-static: old schedule keeps running).
func TestApplyRejectsBadScheduleKeepsOldRunning(t *testing.T) {
	s := NewScheduler(&fakeAPI{}, &fakeRunner{})
	good := &Config{Version: "v1", Entries: []Entry{{ID: "t1", Schedule: "* * * * *", Command: "true"}}}
	if err := s.Apply(good); err != nil {
		t.Fatal(err)
	}
	bad := &Config{Version: "v2", Entries: []Entry{{ID: "t2", Schedule: "garbage", Command: "x"}}}
	if err := s.Apply(bad); err == nil {
		t.Fatal("want error for bad schedule")
	}
	if s.AppliedVersion() != "v1" {
		t.Fatalf("version should remain v1, got %s", s.AppliedVersion())
	}
	if got := len(s.cron.Entries()); got != 1 {
		t.Fatalf("old schedule should still have 1 entry, got %d", got)
	}
}

func TestOverlapSkips(t *testing.T) {
	api := &fakeAPI{}
	r := &fakeRunner{block: make(chan struct{})}
	s := NewScheduler(api, r)
	e := Entry{ID: "t1", App: "a", Schedule: "* * * * *", Command: "sleep"}
	go s.fire(e) // occupies the slot
	time.Sleep(20 * time.Millisecond)
	s.fire(e) // must skip
	close(r.block)
	time.Sleep(20 * time.Millisecond)
	api.mu.Lock()
	defer api.mu.Unlock()
	var skipped int
	for _, run := range api.runs {
		if run.SkippedReason == "overlap" {
			skipped++
		}
	}
	if skipped != 1 {
		t.Fatalf("want 1 overlap skip, got %d (%+v)", skipped, api.runs)
	}
}

func TestExcerptTail(t *testing.T) {
	if got := tail(strings.Repeat("x", 20000), 16384); len(got) != 16384 {
		t.Fatalf("tail len %d", len(got))
	}
}

// Carry-forward #1: a scheduled task on a never-deployed app has an
// image_ref that won't exist on the host, so the docker run fails at fire
// time. That must degrade to a typed FAILED run (nonzero exit code + log
// excerpt) — not a panic, not a dropped report.
func TestFireReportsDockerFailureAsFailedRun(t *testing.T) {
	api := &fakeAPI{}
	r := &fakeRunner{exit: 125, out: "docker: Error response from daemon: pull access denied"}
	s := NewScheduler(api, r)
	e := Entry{ID: "t1", App: "never-deployed", Schedule: "* * * * *", Command: "true", ImageRef: "dokku/never-deployed:latest"}

	s.fire(e) // must not panic

	api.mu.Lock()
	defer api.mu.Unlock()
	if len(api.runs) != 1 {
		t.Fatalf("want 1 reported run, got %d", len(api.runs))
	}
	run := api.runs[0]
	if run.ExitCode == nil || *run.ExitCode != 125 {
		t.Fatalf("want exit code 125, got %+v", run.ExitCode)
	}
	if !strings.Contains(run.LogExcerpt, "pull access denied") {
		t.Fatalf("want log excerpt to carry the docker error, got %q", run.LogExcerpt)
	}
	if run.SkippedReason != "" {
		t.Fatalf("a completed (failed) run is not a skip: %+v", run)
	}
}

// Env must be fetched fresh at fire time (not cached from Apply/config
// fetch), so config changes to app env land on the next run without a
// schedule rebuild.
func TestFireFetchesEnvAtFireTime(t *testing.T) {
	api := &fakeAPI{env: map[string]string{"DATABASE_URL": "postgres://x"}}
	r := &fakeRunner{}
	s := NewScheduler(api, r)
	e := Entry{ID: "t1", App: "a", Schedule: "* * * * *", Command: "true"}

	s.fire(e)

	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.envs) != 1 || r.envs[0]["DATABASE_URL"] != "postgres://x" {
		t.Fatalf("runner did not receive fetched env: %+v", r.envs)
	}
}

// A failed env fetch must not crash the fire and must be reported as a
// skip, not silently swallowed.
func TestFireSkipsOnEnvFetchFailure(t *testing.T) {
	api := &fakeAPI{envErr: errors.New("control plane unreachable")}
	r := &fakeRunner{}
	s := NewScheduler(api, r)
	e := Entry{ID: "t1", App: "a", Schedule: "* * * * *", Command: "true"}

	s.fire(e)

	r.mu.Lock()
	ran := len(r.calls)
	r.mu.Unlock()
	if ran != 0 {
		t.Fatalf("runner must not run without env, got %d calls", ran)
	}
	api.mu.Lock()
	defer api.mu.Unlock()
	if len(api.runs) != 1 || api.runs[0].SkippedReason != "env_fetch_failed" {
		t.Fatalf("want env_fetch_failed skip, got %+v", api.runs)
	}
}

// Sync() (called from the heartbeat loop on version mismatch) must never
// propagate an error up — a bad fetch or a bad config both just log.
func TestSyncNeverPanicsOnFetchError(t *testing.T) {
	s := NewScheduler(&erroringAPI{}, &fakeRunner{})
	s.Sync() // must not panic
	if s.AppliedVersion() != "" {
		t.Fatalf("version should stay empty on fetch failure, got %s", s.AppliedVersion())
	}
}

type erroringAPI struct{}

func (erroringAPI) GetCronConfig() (*Config, error) { return nil, errors.New("boom") }
func (erroringAPI) GetAppEnv(string) (map[string]string, error) {
	return nil, errors.New("boom")
}
func (erroringAPI) PostCronRuns([]Run) error { return errors.New("boom") }

func TestSyncAppliesFetchedConfig(t *testing.T) {
	cfg := &Config{Version: "v9", Entries: []Entry{{ID: "t1", Schedule: "* * * * *", Command: "true"}}}
	s := NewScheduler(&fakeAPI{cfg: cfg}, &fakeRunner{})
	s.Sync()
	if s.AppliedVersion() != "v9" {
		t.Fatalf("version %s", s.AppliedVersion())
	}
}

type panicRunner struct {
	panicFor map[string]bool // entry IDs that should panic; empty map = panic always
}

func (p panicRunner) Run(e Entry, env map[string]string) (int, string) {
	if p.panicFor == nil || p.panicFor[e.ID] {
		panic("boom: runner exploded")
	}
	return 0, "ok"
}

// A panicking job must not crash the process, must surface as a failed
// (not silently swallowed) run, and must clear inFlight so the task isn't
// stuck marked-running forever.
func TestFireRecoversPanicAndReportsFailedRun(t *testing.T) {
	api := &fakeAPI{}
	s := NewScheduler(api, panicRunner{})
	e := Entry{ID: "t1", App: "a", Schedule: "* * * * *", Command: "true"}

	s.fire(e) // must not panic

	api.mu.Lock()
	if len(api.runs) != 1 {
		api.mu.Unlock()
		t.Fatalf("want 1 reported run, got %d", len(api.runs))
	}
	run := api.runs[0]
	api.mu.Unlock()
	if run.ExitCode == nil || *run.ExitCode == 0 {
		t.Fatalf("want nonzero exit code, got %+v", run.ExitCode)
	}
	if !strings.Contains(run.LogExcerpt, "panic") {
		t.Fatalf("want log excerpt to mention panic, got %q", run.LogExcerpt)
	}

	s.mu.Lock()
	inFlight := s.inFlight[e.ID]
	s.mu.Unlock()
	if inFlight {
		t.Fatal("inFlight must be cleared after a panicking fire")
	}

	// A subsequent fire must run (not be skipped as an overlap), proving
	// inFlight was actually cleared.
	s.fire(e)
	api.mu.Lock()
	defer api.mu.Unlock()
	if len(api.runs) != 2 {
		t.Fatalf("want 2 reported runs after second fire, got %d", len(api.runs))
	}
	if api.runs[1].SkippedReason == "overlap" {
		t.Fatal("second fire must not be skipped as overlap")
	}
}

// A panicking job must not take down the scheduler for other jobs — a
// subsequent, unrelated job on the same scheduler must still fire normally.
func TestSchedulerSurvivesPanicAndFiresNextJob(t *testing.T) {
	api := &fakeAPI{}
	s := NewScheduler(api, panicRunner{panicFor: map[string]bool{"bad": true}})

	s.fire(Entry{ID: "bad", App: "a", Schedule: "* * * * *", Command: "true"}) // must not propagate
	s.fire(Entry{ID: "good", App: "a", Schedule: "* * * * *", Command: "true"})

	api.mu.Lock()
	defer api.mu.Unlock()
	if len(api.runs) != 2 {
		t.Fatalf("want 2 reported runs, got %d (%+v)", len(api.runs), api.runs)
	}
	good := api.runs[1]
	if good.TaskID != "good" || good.ExitCode == nil || *good.ExitCode != 0 {
		t.Fatalf("want good job to complete normally, got %+v", good)
	}
}

// Apply(nil) must not nil-deref — treat it as an empty config.
func TestApplyNilConfigDoesNotPanic(t *testing.T) {
	s := NewScheduler(&fakeAPI{}, &fakeRunner{})
	if err := s.Apply(nil); err != nil {
		t.Fatalf("Apply(nil) should not error, got %v", err)
	}
	if got := len(s.cron.Entries()); got != 0 {
		t.Fatalf("expected empty schedule, got %d", got)
	}
}

func TestEntryFieldsRoundTripThroughRunnerCall(t *testing.T) {
	// networks/image_ref/command must reach the runner unmodified — the
	// docker invocation depends on all of them.
	api := &fakeAPI{}
	r := &fakeRunner{}
	s := NewScheduler(api, r)
	e := Entry{ID: "t1", App: "a", Schedule: "* * * * *", Command: "echo hi",
		ImageRef: "dokku/a:latest", Networks: []string{"n1", "n2"}, TimeoutSeconds: 5}
	s.fire(e)
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.calls) != 1 || !reflect.DeepEqual(r.calls[0], e) {
		t.Fatalf("entry not passed through intact: %+v", r.calls)
	}
}
