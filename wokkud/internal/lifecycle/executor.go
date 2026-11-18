// executor.go claims Swarm lifecycle ops (stack.converge / stack.remove) off
// the heartbeat's pending_lifecycle_op_ids and runs them — the B5a sibling of
// internal/services' executor, with two differences: a 2-worker pool
// (converges on different apps parallelize; same-app serialization is the
// control plane's partial unique index, one live op per app, so no app-level
// locking here) and dispatch straight into Converge/Remove instead of a kind
// registry. Fail-static throughout: every failure (including panics) is
// REPORTED via the report endpoint, never returned — the workers never die.
package lifecycle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	"wokku.cloud/wokkud/internal/control"
	"wokku.cloud/wokkud/internal/registry"
)

// lifecycleWorkers is the pool size: enough to overlap converges on
// different apps without turning one slow image pull into a host-wide stall.
// ponytail: fixed at 2 per the B5a spec; raise if converge queueing shows up.
const lifecycleWorkers = 2

// lifecycleOpPanicErrorCode is reported opaquely to the control plane.
const lifecycleOpPanicErrorCode = "lifecycle_op_panic"

// registryBaseURL is the registry.prune dispatch target — a package-level
// var (not a literal registry.DefaultBaseURL call) so dispatch-level tests
// can point it at an httptest registry instead of the real host one.
var registryBaseURL = registry.DefaultBaseURL

// registryDocker runs the host docker CLI for registry.prune's local-image
// cleanup; faked in tests.
var registryDocker interface {
	Run(ctx context.Context, name string, args ...string) ([]byte, error)
} = registry.HostExec{}

// queuedOp is a claimed control.LifecycleOp, trimmed to what the runner uses.
type queuedOp struct {
	id             string
	kind           string
	appName        string
	params         json.RawMessage
	timeoutSeconds int
}

// opSource claims a lifecycle op by id; faked in tests.
type opSource interface {
	claim(id string) (*queuedOp, error)
}

// opRunner executes one claimed op end to end; faked in tests.
type opRunner interface {
	run(ctx context.Context, op *queuedOp)
}

// Executor runs lifecycle ops on a small worker pool with inFlight dedup:
// the heartbeat re-announces pending ids every 15s, so the same id must
// never be queued or run twice concurrently (a dropped enqueue self-heals on
// the next beat instead).
type Executor struct {
	source opSource
	runner opRunner
	swarm  swarmAPI

	queue    chan string
	mu       sync.Mutex
	inFlight map[string]bool
}

func NewExecutor(ctx context.Context, client *control.Client, s swarmAPI) *Executor {
	e := &Executor{
		source:   &clientSource{client: client},
		runner:   &dispatchRunner{client: client, swarm: s},
		swarm:    s,
		queue:    make(chan string, 16),
		inFlight: map[string]bool{},
	}
	for i := 0; i < lifecycleWorkers; i++ {
		go e.work(ctx)
	}
	return e
}

// NewRealExecutor builds an executor backed by the real Docker SDK. On error
// the caller keeps heartbeating and simply never claims lifecycle ops (same
// degraded pattern as the services executor).
func NewRealExecutor(ctx context.Context, client *control.Client) (*Executor, error) {
	s, err := NewSwarmAPI()
	if err != nil {
		return nil, err
	}
	return NewExecutor(ctx, client, s), nil
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

// TaskStates maps the live wokku.managed Swarm tasks to the heartbeat's wire
// shape. Nil-safe: a dark lifecycle duty (docker unavailable at boot) simply
// reports no tasks.
func (e *Executor) TaskStates(ctx context.Context) []control.TaskState {
	if e == nil || e.swarm == nil {
		return nil
	}
	tasks, err := e.swarm.TaskList(ctx)
	if err != nil {
		log.Printf("wokkud: lifecycle task list: %v", err)
		return nil
	}
	out := make([]control.TaskState, 0, len(tasks))
	for _, t := range tasks {
		out = append(out, control.TaskState{
			App:          t.App,
			Process:      t.Process,
			State:        t.State,
			DesiredState: t.DesiredState,
			StartedAt:    t.StartedAt,
			ExitCode:     t.ExitCode,
		})
	}
	return out
}

// work is one of lifecycleWorkers dispatch loops: claim, run to completion,
// dequeue the next. Two loops share one queue, so two ops (necessarily
// different apps — the control plane's one-live-op-per-app index guarantees
// it) run concurrently.
func (e *Executor) work(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case id := <-e.queue:
			op, err := e.source.claim(id)
			if err != nil {
				log.Printf("wokkud: claim lifecycle op %s: %v", id, err)
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

// clientSource claims via the control plane.
type clientSource struct {
	client *control.Client
}

func (s *clientSource) claim(id string) (*queuedOp, error) {
	op, err := s.client.ClaimLifecycleOp(id)
	if err != nil || op == nil {
		return nil, err
	}
	return &queuedOp{
		id:             op.ID,
		kind:           op.Kind,
		appName:        op.AppName,
		params:         op.Params,
		timeoutSeconds: op.TimeoutSeconds,
	}, nil
}

// dispatchRunner runs one op with a timeout and reports exactly once.
// Logging is id/kind/app only — op params carry the app's full env, which
// must never hit the agent log (the control plane redacts its copy on
// report; ours never exists).
type dispatchRunner struct {
	client *control.Client
	swarm  swarmAPI
}

func (d *dispatchRunner) run(ctx context.Context, op *queuedOp) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(op.timeoutSeconds)*time.Second)
	defer cancel()

	// fail-static: a panic anywhere below must not take the worker down —
	// recover, report the op failed, let the loop pick up the next one.
	defer func() {
		if r := recover(); r != nil {
			msg := fmt.Sprintf("panic: %v", r)
			log.Printf("wokkud: lifecycle op %s (%s app=%s) %s", op.id, op.kind, op.appName, msg)
			if rerr := d.client.ReportLifecycleOp(op.id, "failed", nil, msg, lifecycleOpPanicErrorCode); rerr != nil {
				log.Printf("wokkud: report lifecycle op %s: %v", op.id, rerr)
			}
		}
	}()

	result, err := d.dispatch(ctx, op)
	if err != nil {
		log.Printf("wokkud: lifecycle op %s (%s app=%s) failed: %v", op.id, op.kind, op.appName, err)
		code := ""
		if errors.Is(err, ErrFormationWouldEmpty) {
			code = ErrCodeFormationWouldEmpty
		}
		var cf *CommandFailedError
		if errors.As(err, &cf) {
			code = ErrCodeCommandFailed
		}
		if errors.Is(err, ErrRunTimeout) {
			code = ErrCodeRunTimeout
		}
		if rerr := d.client.ReportLifecycleOp(op.id, "failed", result, err.Error(), code); rerr != nil {
			log.Printf("wokkud: report lifecycle op %s: %v", op.id, rerr)
		}
		return
	}
	if rerr := d.client.ReportLifecycleOp(op.id, "succeeded", result, "", ""); rerr != nil {
		log.Printf("wokkud: report lifecycle op %s: %v", op.id, rerr)
	}
}

// dispatch routes the op kind to the converge engine. A handful of kinds
// exist (LifecycleOp::KINDS on the Rails side), so a switch beats a registry.
func (d *dispatchRunner) dispatch(ctx context.Context, op *queuedOp) (any, error) {
	switch op.kind {
	case "registry.prune":
		var p struct {
			Repo     string   `json:"repo"`
			KeepTags []string `json:"keep_tags"`
		}
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		res, err := registry.Prune(ctx, registryBaseURL, p.Repo, p.KeepTags)
		if err != nil {
			return nil, err
		}
		registry.RemoveLocalImages(ctx, registryDocker, p.Repo, p.KeepTags)
		return map[string]int{
			"deleted":        res.Deleted,
			"kept":           res.Kept,
			"skipped_shared": res.SkippedShared,
		}, nil
	case "stack.run":
		var p RunParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		p.App = op.appName // authoritative, mirroring stack.converge
		p.OpID = op.id
		res, err := RunOnce(ctx, d.swarm, p)
		if res != nil {
			// Non-nil even on failure — the output tail is the op's
			// debugging surface either way.
			return map[string]any{"exit_code": res.ExitCode, "output": res.Output}, err
		}
		return nil, err
	case "stack.converge":
		var p ConvergeParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		p.App = op.appName // authoritative: from the op's app record, not params
		res, err := Converge(ctx, d.swarm, p)
		if err != nil {
			return nil, err
		}
		return map[string][]string{
			"created": res.Created,
			"updated": res.Updated,
			"removed": res.Removed,
		}, nil
	case "stack.remove":
		return nil, Remove(ctx, d.swarm, op.appName)
	default:
		return nil, fmt.Errorf("unsupported lifecycle op kind: %s", op.kind)
	}
}
