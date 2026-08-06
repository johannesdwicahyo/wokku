package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

// fakeRunner records which op IDs ran; blocks on the given op id until
// released, so a test can prove a later op didn't start until an earlier
// one's block was lifted.
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

// mapSource is a test opSource: a fixed table of ops keyed by id, id filled
// in on claim (mirrors clientSource setting queuedOp.id from control.ServiceOp.ID).
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
	go e.work(ctx)
	return e
}

// TestExecutorSerializesHostWide proves the single-worker property: op3
// (distinct service) must not start until op1 (blocked) completes — the
// executor is one blocking worker, not per-service concurrency, so this
// ordering is deterministic without any rendezvous machinery.
func TestExecutorSerializesHostWide(t *testing.T) {
	r := &fakeRunner{blockOn: "op1", block: make(chan struct{})}
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op1": {service: "db1"}, "op3": {service: "db2"},
	})
	e.Enqueue("op1")
	e.Enqueue("op3") // different service, but the worker is single — waits on op1

	time.Sleep(50 * time.Millisecond)
	r.mu.Lock()
	got := append([]string(nil), r.ran...)
	r.mu.Unlock()
	if len(got) != 1 || got[0] != "op1" {
		t.Fatalf("want only [op1] running while it's blocked, got %v", got)
	}

	close(r.block) // let op1 finish
	time.Sleep(50 * time.Millisecond)
	r.mu.Lock()
	got = append([]string(nil), r.ran...)
	r.mu.Unlock()
	if len(got) != 2 || got[0] != "op1" || got[1] != "op3" {
		t.Fatalf("want [op1 op3] in order, got %v", got)
	}
}

// TestExecutorDedupsSameID proves the inFlight map still drops a re-enqueue
// of an id already queued/running (heartbeat re-announce self-heal is
// distinct from this: this is the dedup guard within one still-queued op).
func TestExecutorDedupsSameID(t *testing.T) {
	r := &fakeRunner{blockOn: "op1", block: make(chan struct{})}
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op1": {service: "db1"},
	})
	e.Enqueue("op1")
	e.Enqueue("op1") // same id, already in flight — must not double-queue

	close(r.block)
	time.Sleep(50 * time.Millisecond)
	r.mu.Lock()
	got := append([]string(nil), r.ran...)
	r.mu.Unlock()
	if len(got) != 1 || got[0] != "op1" {
		t.Fatalf("want op1 to run exactly once, got %v", got)
	}
}

// TestExecutorDropsRefusedClaim proves a claim that comes back nil (control
// plane refused — already claimed/settled) is dropped without running,
// and the worker moves on to the next queued op.
func TestExecutorDropsRefusedClaim(t *testing.T) {
	r := &fakeRunner{}
	e := newExecutorForTest(context.Background(), r, map[string]*queuedOp{
		"op2": {service: "db1"}, // "op1" deliberately absent from the source → claim refused
	})
	e.Enqueue("op1")
	e.Enqueue("op2")

	time.Sleep(50 * time.Millisecond)
	r.mu.Lock()
	got := append([]string(nil), r.ran...)
	r.mu.Unlock()
	if len(got) != 1 || got[0] != "op2" {
		t.Fatalf("want only op2 to run (op1's claim refused), got %v", got)
	}
}

// TestDispatchRunnerRecoversHandlerPanic exercises the real dispatchRunner
// (not a fake opRunner) end to end against a fake control-plane HTTP server,
// to prove the recover() lives where it actually matters: inside
// dispatchRunner.run, wrapping the handler call, reporting via the real
// ReportServiceOp request shape.
func TestDispatchRunnerRecoversHandlerPanic(t *testing.T) {
	type reportBody struct {
		Status    string `json:"status"`
		Error     string `json:"error"`
		ErrorCode string `json:"error_code"`
	}
	var reported struct {
		mu    sync.Mutex
		calls int
		last  reportBody
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body reportBody
		_ = json.NewDecoder(r.Body).Decode(&body)
		reported.mu.Lock()
		reported.calls++
		reported.last = body
		reported.mu.Unlock()
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	client := control.New(srv.URL, "tok", "0.5.0")
	d := &dispatchRunner{client: client, docker: nil}

	handlers["panic_kind"] = func(ctx context.Context, client *control.Client, docker dockerAPI, op *queuedOp) (any, error) {
		panic("boom")
	}
	defer delete(handlers, "panic_kind")

	d.run(context.Background(), &queuedOp{id: "op-panic", kind: "panic_kind", timeoutSeconds: 5})

	reported.mu.Lock()
	if reported.calls != 1 {
		reported.mu.Unlock()
		t.Fatalf("want ReportServiceOp called once, got %d", reported.calls)
	}
	if reported.last.Status != "failed" {
		reported.mu.Unlock()
		t.Fatalf("want status failed, got %q", reported.last.Status)
	}
	if reported.last.Error != "panic: boom" {
		reported.mu.Unlock()
		t.Fatalf("want error %q, got %q", "panic: boom", reported.last.Error)
	}
	if reported.last.ErrorCode != serviceOpPanicErrorCode {
		reported.mu.Unlock()
		t.Fatalf("want error_code %q, got %q", serviceOpPanicErrorCode, reported.last.ErrorCode)
	}
	reported.mu.Unlock()

	// Executor keeps running afterward: a second, non-panicking op still
	// dispatches through the same runner and reports success.
	handlers["ok_kind"] = func(ctx context.Context, client *control.Client, docker dockerAPI, op *queuedOp) (any, error) {
		return "fine", nil
	}
	defer delete(handlers, "ok_kind")
	d.run(context.Background(), &queuedOp{id: "op-next", kind: "ok_kind", timeoutSeconds: 5})

	reported.mu.Lock()
	defer reported.mu.Unlock()
	if reported.calls != 2 || reported.last.Status != "succeeded" {
		t.Fatalf("want the next op to still run and report succeeded, got calls=%d status=%s", reported.calls, reported.last.Status)
	}
}
