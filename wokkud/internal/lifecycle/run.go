// run.go is the stack.run engine: run one command to completion in a fresh
// container from the app's image, as a Swarm replicated-job (founder-chosen
// over a plain container: multi-host-ready, same op contract). The job spec
// is restart-none — a failed migration must never auto-retry — and the
// service is removed on every path, with logs read strictly before removal
// (a removed job's logs are gone).
package lifecycle

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// maxRunOutputBytes caps the captured output tail (spec §7.5) so a chatty
// migration can't bloat lifecycle_ops.
const maxRunOutputBytes = 64 * 1024

// runPollInterval is a var so tests can shrink it.
var runPollInterval = 2 * time.Second

// ErrRunTimeout: the command did not reach a terminal task state before the
// op deadline. The service is removed; the partial log rides the result.
var ErrRunTimeout = errors.New("run timed out")

const (
	ErrCodeCommandFailed = "command_failed"
	ErrCodeRunTimeout    = "timeout"
)

// CommandFailedError: the command ran and exited nonzero (or the task was
// rejected). Distinct type so the executor maps it to error_code
// command_failed while still reporting the output tail as the op result.
type CommandFailedError struct{ ExitCode int }

func (e *CommandFailedError) Error() string {
	return fmt.Sprintf("command exited %d", e.ExitCode)
}

// RunParams is decoded straight from a stack.run op's params; JSON tags are
// the wire contract with Lifecycle::Ops.run!. App and OpID are set by the
// executor from the op record, mirroring ConvergeParams.App.
type RunParams struct {
	App      string            `json:"app"`
	OpID     string            `json:"-"`
	ImageRef string            `json:"image_ref"`
	Command  string            `json:"command"`
	Env      map[string]string `json:"env"`
	MemoryMB int               `json:"memory_mb"`
	CPU      float64           `json:"cpu"`
	Networks []string          `json:"networks"`
}

// RunResult is the op result: exit code + combined-output tail. Reported
// even when the command fails (the output IS the debugging surface).
type RunResult struct {
	ExitCode int    `json:"exit_code"`
	Output   string `json:"output"`
}

// RunServiceName is the job service's name: wokku-run-<app>-<op8>. The op-id
// prefix makes re-claims idempotent (same op → same name → pre-remove).
func RunServiceName(app, opID string) string {
	if len(opID) > 8 {
		opID = opID[:8]
	}
	return fmt.Sprintf("wokku-run-%s-%s", app, opID)
}

// RunOnce runs one command as a replicated-job and waits for the terminal
// task state. Returns (result, nil) on exit 0; (result, *CommandFailedError)
// on nonzero/rejected; (best-effort result, ErrRunTimeout) on deadline.
func RunOnce(ctx context.Context, s swarmAPI, p RunParams) (*RunResult, error) {
	name := RunServiceName(p.App, p.OpID)

	for _, n := range p.Networks {
		if err := s.NetworkEnsureOverlay(ctx, n); err != nil {
			return nil, err
		}
	}

	// Idempotent re-claim: a crashed prior attempt may have left the service
	// behind — same op id, same name. Best-effort remove before create.
	_ = s.ServiceRemove(ctx, name)

	spec := ServiceSpec{
		Name: name, App: p.App, Process: "run",
		Image:    p.ImageRef,
		Command:  splitCommand(p.Command),
		Env:      p.Env,
		Replicas: 1,
		MemoryMB: p.MemoryMB, CPU: p.CPU,
		Networks: p.Networks,
		Job:      true,
	}
	if err := s.ServiceCreate(ctx, spec); err != nil {
		return nil, err
	}
	// Removal must survive ctx expiry (the timeout path is exactly when
	// cleanup matters most) — detached context with its own short deadline.
	defer func() {
		rmCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancel()
		_ = s.ServiceRemove(rmCtx, name)
	}()

	for {
		select {
		case <-ctx.Done():
			out, _ := readLogs(ctx, s, name)
			return &RunResult{ExitCode: -1, Output: out}, ErrRunTimeout
		case <-time.After(runPollInterval):
		}
		tasks, err := s.JobTasks(ctx, name)
		if err != nil {
			// If JobTasks failed AND the context has expired, take the
			// timeout path (best-effort logs + ErrRunTimeout). Otherwise
			// a plain error indicates a transient API issue, not expiry.
			if ctx.Err() != nil {
				out, _ := readLogs(ctx, s, name)
				return &RunResult{ExitCode: -1, Output: out}, ErrRunTimeout
			}
			return nil, err
		}
		for _, t := range tasks {
			switch t.State {
			case "complete":
				out, lerr := readLogs(ctx, s, name)
				if lerr != nil {
					// The command succeeded; a log-read failure must not
					// fail the op. Surface what we know.
					out = fmt.Sprintf("(log read failed: %v)", lerr)
				}
				return &RunResult{ExitCode: 0, Output: out}, nil
			case "failed", "rejected", "orphaned":
				out, _ := readLogs(ctx, s, name)
				if t.Message != "" {
					out = out + "\n" + t.Message
				}
				return &RunResult{ExitCode: t.ExitCode, Output: capTail(out)},
					&CommandFailedError{ExitCode: t.ExitCode}
			}
		}
	}
}

// readLogs reads with a detached context so the timeout path can still
// fetch the partial log, and tail-caps.
func readLogs(ctx context.Context, s swarmAPI, name string) (string, error) {
	lctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 15*time.Second)
	defer cancel()
	out, err := s.ServiceLogs(lctx, name)
	return capTail(out), err
}

func capTail(s string) string {
	if len(s) > maxRunOutputBytes {
		return s[len(s)-maxRunOutputBytes:]
	}
	return s
}
