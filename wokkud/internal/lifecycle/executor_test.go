package lifecycle

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

// fakeRunner records which op IDs ran; blocks on the given op id until
// released, so a test can prove ops on different apps run concurrently.
type fakeRunner struct {
	mu      sync.Mutex
	ran     []string
	blockOn string
	block   chan struct{}
}

func (r *fakeRunner) run(ctx context.Context, op *queuedOp) {
	r.mu.Lock()
	r.ran = append(r.ran, op.id)
	block := r.blockOn == op.id
	r.mu.Unlock()
	if block {
		<-r.block
	}
}

func (r *fakeRunner) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.ran...)
}

// mapSource is a test opSource: a fixed table of ops keyed by id.
type mapSource map[string]*queuedOp

func (m mapSource) claim(id string) (*queuedOp, error) {
	op, ok := m[id]
	if !ok {
		return nil, nil
	}
	cp := *op
	cp.id = id
	return &cp, nil
}

func newExecutorForTest(ctx context.Context, runner opRunner, ops map[string]*queuedOp) *Executor {
	e := &Executor{
		source:   mapSource(ops),
		runner:   runner,
		queue:    make(chan string, 16),
		inFlight: map[string]bool{},
	}
	for i := 0; i < lifecycleWorkers; i++ {
		go e.work(ctx)
	}
	return e
}

// TestExecutorParallelizesAcrossApps proves the 2-worker property: op2 (a
// different app) runs to completion while op1 is still blocked — unlike the
// B4 services executor, converges on different apps must not serialize.
func TestExecutorParallelizesAcrossApps(t *testing.T) {
	r := &fakeRunner{blockOn: "op1", block: make(chan struct{})}
	defer close(r.block)
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op1": {appName: "blog"}, "op2": {appName: "shop"},
	})
	e.Enqueue("op1")
	e.Enqueue("op2")

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(r.snapshot()) == 2 {
			return // op2 ran while op1 was blocked — parallel
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("op2 never ran while op1 was blocked, ran=%v", r.snapshot())
}

// TestExecutorDedupsSameID proves the inFlight map drops a re-enqueue of an
// id already queued/running (the heartbeat re-announces pending ids every
// 15s — the same op must never run twice concurrently).
func TestExecutorDedupsSameID(t *testing.T) {
	r := &fakeRunner{blockOn: "op1", block: make(chan struct{})}
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op1": {appName: "blog"},
	})
	e.Enqueue("op1")
	e.Enqueue("op1") // already in flight — must not double-queue

	close(r.block)
	time.Sleep(50 * time.Millisecond)
	if got := r.snapshot(); len(got) != 1 || got[0] != "op1" {
		t.Fatalf("want op1 to run exactly once, got %v", got)
	}
}

// TestExecutorDropsRefusedClaim: a nil claim (control plane refused) is
// dropped without running, and the workers keep draining.
func TestExecutorDropsRefusedClaim(t *testing.T) {
	r := &fakeRunner{}
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op2": {appName: "blog"}, // "op1" absent → claim refused
	})
	e.Enqueue("op1")
	e.Enqueue("op2")

	time.Sleep(50 * time.Millisecond)
	if got := r.snapshot(); len(got) != 1 || got[0] != "op2" {
		t.Fatalf("want only op2 to run, got %v", got)
	}
}

// reportRecorder is a fake control-plane report endpoint.
type reportRecorder struct {
	mu    sync.Mutex
	calls []map[string]any
}

func (rr *reportRecorder) server(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		rr.mu.Lock()
		rr.calls = append(rr.calls, body)
		rr.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
}

func (rr *reportRecorder) last(t *testing.T) map[string]any {
	t.Helper()
	rr.mu.Lock()
	defer rr.mu.Unlock()
	if len(rr.calls) == 0 {
		t.Fatal("no report received")
	}
	return rr.calls[len(rr.calls)-1]
}

// panicSwarm panics on ServiceList — drives the fail-static recover path.
type panicSwarm struct{ *fakeSwarm }

func (p *panicSwarm) ServiceList(ctx context.Context, appLabel string) ([]ServiceInfo, error) {
	panic("boom")
}

// TestDispatchRunnerFailStatic exercises the real dispatchRunner end to end:
// a panicking swarm call is recovered and reported failed; the guard error
// maps to error_code formation_would_empty; a subsequent op still runs and
// reports succeeded. The loop never dies.
func TestDispatchRunnerFailStatic(t *testing.T) {
	rr := &reportRecorder{}
	srv := rr.server(t)
	defer srv.Close()
	client := control.New(srv.URL, "tok", "0.7.0")

	params, _ := json.Marshal(map[string]any{
		"deploy_id": "d1", "image_ref": "img:1",
		"formation": map[string]int{"web": 1}, "env": map[string]string{"SECRET_TOKEN": "s3cr3t"},
	})

	// 1. Panic in the swarm layer → recovered, reported failed.
	d := &dispatchRunner{client: client, swarm: &panicSwarm{&fakeSwarm{}}}
	d.run(context.Background(), &queuedOp{id: "op-panic", kind: "stack.converge", appName: "blog", params: params, timeoutSeconds: 5})
	got := rr.last(t)
	if got["status"] != "failed" || got["error_code"] != lifecycleOpPanicErrorCode {
		t.Fatalf("panic report = %v", got)
	}

	// 2. Empty-formation guard → error_code formation_would_empty.
	live := &fakeSwarm{live: []ServiceInfo{{Name: "wokku-blog-web", App: "blog", Process: "web", Replicas: 1}}}
	emptyParams, _ := json.Marshal(map[string]any{"formation": map[string]int{"worker": 1}})
	d = &dispatchRunner{client: client, swarm: live}
	d.run(context.Background(), &queuedOp{id: "op-guard", kind: "stack.converge", appName: "blog", params: emptyParams, timeoutSeconds: 5})
	got = rr.last(t)
	if got["status"] != "failed" || got["error_code"] != ErrCodeFormationWouldEmpty {
		t.Fatalf("guard report = %v", got)
	}

	// 3. Same runner still works: a good converge reports succeeded.
	d = &dispatchRunner{client: client, swarm: &fakeSwarm{}}
	d.run(context.Background(), &queuedOp{id: "op-ok", kind: "stack.converge", appName: "blog", params: params, timeoutSeconds: 5})
	got = rr.last(t)
	if got["status"] != "succeeded" {
		t.Fatalf("success report = %v", got)
	}

	// 4. Unknown kind fails static too.
	d.run(context.Background(), &queuedOp{id: "op-weird", kind: "stack.dance", appName: "blog", timeoutSeconds: 5})
	if got = rr.last(t); got["status"] != "failed" {
		t.Fatalf("unknown-kind report = %v", got)
	}
}

// TestDispatchRunnerStackRemove: stack.remove routes to Remove and reports.
func TestDispatchRunnerStackRemove(t *testing.T) {
	rr := &reportRecorder{}
	srv := rr.server(t)
	defer srv.Close()
	f := &fakeSwarm{live: []ServiceInfo{{Name: "wokku-blog-web", App: "blog", Process: "web", Replicas: 1}}}
	d := &dispatchRunner{client: control.New(srv.URL, "tok", "0.7.0"), swarm: f}
	d.run(context.Background(), &queuedOp{id: "op-rm", kind: "stack.remove", appName: "blog", timeoutSeconds: 5})
	if got := rr.last(t); got["status"] != "succeeded" {
		t.Fatalf("remove report = %v", got)
	}
	if got := f.writes(); len(got) != 1 || got[0] != "remove:wokku-blog-web" {
		t.Fatalf("writes = %v", got)
	}
}

// TestDispatchRunnerRegistryPrune: registry.prune decodes {"repo","keep_tags"}
// from op.params, calls Prune against an httptest registry (via the
// registryBaseURL seam, not the real host registry), and reports exactly
// {"deleted","kept","skipped_shared"} — the wire contract the control plane
// depends on.
func TestDispatchRunnerRegistryPrune(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v2/{repo}/tags/list", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string][]string{"tags": {"keep", "stale"}})
	})
	mux.HandleFunc("HEAD /v2/{repo}/manifests/{tag}", func(w http.ResponseWriter, r *http.Request) {
		digest := map[string]string{"keep": "sha256:keep", "stale": "sha256:stale"}[r.PathValue("tag")]
		w.Header().Set("Docker-Content-Digest", digest)
	})
	mux.HandleFunc("DELETE /v2/{repo}/manifests/{digest}", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted)
	})
	regSrv := httptest.NewServer(mux)
	defer regSrv.Close()

	orig := registryBaseURL
	registryBaseURL = regSrv.URL
	defer func() { registryBaseURL = orig }()

	rr := &reportRecorder{}
	srv := rr.server(t)
	defer srv.Close()

	docker := &dockerRecorder{images: "keep\nstale\n"}
	origDocker := registryDocker
	registryDocker = docker
	defer func() { registryDocker = origDocker }()

	d := &dispatchRunner{client: control.New(srv.URL, "tok", "0.7.0")}
	params, _ := json.Marshal(map[string]any{"repo": "myapp", "keep_tags": []string{"keep"}})
	d.run(context.Background(), &queuedOp{id: "op-prune", kind: "registry.prune", appName: "myapp", params: params, timeoutSeconds: 5})

	got := rr.last(t)
	if got["status"] != "succeeded" {
		t.Fatalf("prune report = %v", got)
	}
	result, ok := got["result"].(map[string]any)
	if !ok {
		t.Fatalf("result not a map: %v", got["result"])
	}
	if len(result) != 3 {
		t.Fatalf("result keys = %v, want exactly deleted/kept/skipped_shared", result)
	}
	if result["deleted"] != float64(1) || result["kept"] != float64(1) || result["skipped_shared"] != float64(0) {
		t.Fatalf("result = %v", result)
	}
	// The host's tagged local copy of the pruned tag is removed too (GC's
	// image prune never touches tagged images).
	if last := docker.calls[len(docker.calls)-1]; strings.Join(last, " ") != "docker rmi 127.0.0.1:5000/myapp:stale" {
		t.Fatalf("docker calls = %v", docker.calls)
	}
}

// dockerRecorder fakes the host docker CLI for registry.prune's local cleanup.
type dockerRecorder struct {
	images string
	calls  [][]string
}

func (d *dockerRecorder) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	d.calls = append(d.calls, append([]string{name}, args...))
	if len(args) > 0 && args[0] == "images" {
		return []byte(d.images), nil
	}
	return nil, nil
}

// TestDispatchStackRunReportsFailureWithResult: a failed stack.run must still
// report the result (output tail is the op's debugging surface), with
// error_code command_failed.
func TestDispatchStackRunReportsFailureWithResult(t *testing.T) {
	fastPoll(t)
	rr := &reportRecorder{}
	srv := rr.server(t)
	defer srv.Close()

	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "failed", ExitCode: 3}}}
	f.logs = map[string]string{name: "boom\n"}

	d := &dispatchRunner{client: control.New(srv.URL, "tok", "0.7.0"), swarm: f}
	d.run(context.Background(), &queuedOp{
		id: "0123456789abcdef", kind: "stack.run", appName: "myapp",
		params:         []byte(`{"image_ref":"img:1","command":"x","networks":[]}`),
		timeoutSeconds: 5,
	})
	got := rr.last(t)
	if got["status"] != "failed" || got["error_code"] != ErrCodeCommandFailed {
		t.Fatalf("report = %v", got)
	}
	if got["result"] == nil {
		t.Fatal("failed stack.run must still report the result (output tail)")
	}
}

// taskSwarm returns canned tasks for the heartbeat feed.
type taskSwarm struct {
	*fakeSwarm
	tasks []TaskInfo
}

func (s *taskSwarm) TaskList(ctx context.Context) ([]TaskInfo, error) { return s.tasks, nil }

// TestTaskStates maps TaskList to the heartbeat wire shape; nil executor is safe.
func TestTaskStates(t *testing.T) {
	started := time.Date(2026, 7, 16, 10, 0, 0, 0, time.UTC)
	e := &Executor{swarm: &taskSwarm{fakeSwarm: &fakeSwarm{}, tasks: []TaskInfo{
		{App: "blog", Process: "web", State: "running", DesiredState: "running", StartedAt: started, ExitCode: 0},
		{App: "blog", Process: "worker", State: "failed", DesiredState: "shutdown", ExitCode: 137},
	}}}
	got := e.TaskStates(context.Background())
	if len(got) != 2 {
		t.Fatalf("got %v", got)
	}
	if got[0] != (control.TaskState{App: "blog", Process: "web", State: "running", DesiredState: "running", StartedAt: started}) {
		t.Fatalf("got[0] = %+v", got[0])
	}
	if got[1].ExitCode != 137 || got[1].DesiredState != "shutdown" {
		t.Fatalf("got[1] = %+v", got[1])
	}

	var nilExec *Executor
	if states := nilExec.TaskStates(context.Background()); states != nil {
		t.Fatalf("nil executor must report no tasks, got %v", states)
	}
}
