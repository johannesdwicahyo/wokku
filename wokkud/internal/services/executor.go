// Package services is wokkud's datastore-lifecycle executor (Track B Phase
// B4): claim a pending service op off the heartbeat's
// pending_service_op_ids, dispatch it to an engine handler, stream/report
// the outcome. Mirrors the Phase 4c build pipeline (internal/builder)
// exactly: a single blocking worker, one op at a time, which serializes ALL
// datastore ops host-wide (spec §3) — no per-service concurrency to reason
// about. All failures are REPORTED, never returned — a handler panic is
// recovered and reported too, so the agent never dies mid-queue.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

// dockerAPI is declared in docker.go (Task 8) — kept out of this file so
// NewExecutor's signature could stay stable across Tasks 6-9 without this
// file knowing the real method set in advance.

// queuedOp is a claimed control.ServiceOp, trimmed to what the executor and
// handlers use.
type queuedOp struct {
	id             string
	kind           string
	service        string
	params         json.RawMessage
	timeoutSeconds int
}

// opSource claims a service op by id. Abstracted so tests can fake the
// control-plane round trip.
type opSource interface {
	claim(id string) (*queuedOp, error)
}

// opRunner executes one claimed op end to end (dispatch, run, report).
// Abstracted so tests can fake it without touching control/docker.
type opRunner interface {
	run(ctx context.Context, op *queuedOp)
}

// Executor serializes service ops: dedup by op id (the heartbeat
// re-announces pending ids every 15s, so a dropped enqueue self-heals) and
// runs one op at a time, start to finish, on a single worker.
type Executor struct {
	source opSource
	runner opRunner

	queue    chan string
	mu       sync.Mutex
	inFlight map[string]bool
}

func NewExecutor(ctx context.Context, client *control.Client, docker dockerAPI) *Executor {
	e := &Executor{
		source:   &clientSource{client: client},
		runner:   &dispatchRunner{client: client, docker: docker},
		queue:    make(chan string, 16),
		inFlight: map[string]bool{},
	}
	go e.work(ctx)
	return e
}

// NewRealExecutor builds an executor backed by the real Docker SDK. Returns
// an error if the docker client can't init — the caller keeps heartbeating
// and simply never claims service ops (same degraded pattern as dockermon /
// the build executor). dockerAPI stays unexported; main constructs through
// this.
func NewRealExecutor(ctx context.Context, client *control.Client) (*Executor, error) {
	docker, err := newDockerAPI()
	if err != nil {
		return nil, err
	}
	return NewExecutor(ctx, client, docker), nil
}

func (e *Executor) Enqueue(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.inFlight[id] {
		return
	}
	select {
	case e.queue <- id:
		e.inFlight[id] = true
	default: // queue full — the next heartbeat re-delivers the id
	}
}

// work is the single dispatch loop: claim, then run the op to completion
// before dequeuing the next one.
// ponytail: single worker serializes all datastore ops per host; upgrade
// path = bounded pool (2-4) + per-service busy map if backup windows ever
// matter.
func (e *Executor) work(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case id := <-e.queue:
			op, err := e.source.claim(id)
			if err != nil {
				log.Printf("wokkud: claim service op %s: %v", id, err)
			}
			if op != nil {
				e.runner.run(ctx, op)
			}
			e.mu.Lock()
			delete(e.inFlight, id)
			e.mu.Unlock()
		}
	}
}

// clientSource is the production opSource: claims via the control plane.
type clientSource struct {
	client *control.Client
}

func (s *clientSource) claim(id string) (*queuedOp, error) {
	op, err := s.client.ClaimServiceOp(id)
	if err != nil || op == nil {
		return nil, err
	}
	return &queuedOp{
		id:             op.ID,
		kind:           op.Kind,
		service:        op.Service,
		params:         op.Params,
		timeoutSeconds: op.TimeoutSeconds,
	}, nil
}

// handler processes one claimed op and returns a JSON-able result, or an
// error to be reported as a failure. Real engine handlers (Tasks 7-8)
// register themselves in handlers by op.Kind.
type handler func(ctx context.Context, client *control.Client, docker dockerAPI, op *queuedOp) (result any, err error)

// handlers is the op.Kind → handler registry. Empty until Tasks 7-8 register
// real engine handlers; unregistered kinds fall back to stubHandler.
var handlers = map[string]handler{}

// stubHandler fails loud for any kind not yet implemented — fail-static:
// reported via ReportServiceOp, never returned/panicked up the stack.
func stubHandler(ctx context.Context, client *control.Client, docker dockerAPI, op *queuedOp) (any, error) {
	return nil, fmt.Errorf("unsupported op kind: %s", op.kind)
}

// dispatchRunner is the production opRunner: dispatch by Kind, run with a
// timeout, report exactly once.
type dispatchRunner struct {
	client *control.Client
	docker dockerAPI
}

// serviceOpPanicErrorCode is reported opaquely to the control plane (Rails
// ApiErrors passes error_code through without needing a matching entry).
const serviceOpPanicErrorCode = "service_op_panic"

func (d *dispatchRunner) run(ctx context.Context, op *queuedOp) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(op.timeoutSeconds)*time.Second)
	defer cancel()

	// fail-static: a handler panic must not take the worker down with it —
	// recover, report the op failed, and let the loop move on to the next one.
	defer func() {
		if r := recover(); r != nil {
			msg := fmt.Sprintf("panic: %v", r)
			log.Printf("wokkud: service op %s (%s) %s", op.id, op.kind, msg)
			if rerr := d.client.ReportServiceOp(op.id, "failed", nil, msg, serviceOpPanicErrorCode); rerr != nil {
				log.Printf("wokkud: report service op %s: %v", op.id, rerr)
			}
		}
	}()

	h, ok := handlers[op.kind]
	if !ok {
		h = stubHandler
	}
	result, err := h(ctx, d.client, d.docker, op)
	if err != nil {
		log.Printf("wokkud: service op %s (%s) failed: %v", op.id, op.kind, err)
		code := ""
		var oe *opError
		if errors.As(err, &oe) {
			code = oe.code
		}
		if rerr := d.client.ReportServiceOp(op.id, "failed", nil, err.Error(), code); rerr != nil {
			log.Printf("wokkud: report service op %s: %v", op.id, rerr)
		}
		return
	}
	if rerr := d.client.ReportServiceOp(op.id, "succeeded", result, "", ""); rerr != nil {
		log.Printf("wokkud: report service op %s: %v", op.id, rerr)
	}
}
