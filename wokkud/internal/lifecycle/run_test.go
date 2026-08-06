package lifecycle

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// fastPoll shrinks runPollInterval for the duration of one test so the
// timeout test's short deadline actually gets a poll iteration, and restores
// it afterward.
func fastPoll(t *testing.T) {
	old := runPollInterval
	runPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { runPollInterval = old })
}

func runParams() RunParams {
	return RunParams{
		App: "myapp", OpID: "0123456789abcdef", ImageRef: "img:1",
		Command: "bundle exec rails db:migrate",
		Env:     map[string]string{"A": "1"}, Networks: []string{"wokku-services"},
	}
}

func TestRunServiceName(t *testing.T) {
	if got := RunServiceName("myapp", "0123456789abcdef"); got != "wokku-run-myapp-01234567" {
		t.Fatalf("got %q", got)
	}
}

func TestRunOnceSuccess(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "complete", ExitCode: 0}}}
	f.logs = map[string]string{name: "20 migrations applied\n"}
	res, err := RunOnce(context.Background(), f, runParams())
	if err != nil {
		t.Fatal(err)
	}
	if res.ExitCode != 0 || res.Output != "20 migrations applied\n" {
		t.Fatalf("res: %+v", res)
	}
	// Created as a job, logs read BEFORE removal, service removed after.
	var createIdx, logsIdx, removeIdx = -1, -1, -1
	for i, c := range f.calls {
		switch {
		case c == "create:"+name:
			createIdx = i
		case c == "ServiceLogs("+name+")":
			logsIdx = i
		case c == "remove:"+name && createIdx >= 0 && i > createIdx:
			removeIdx = i
		}
	}
	if createIdx < 0 || logsIdx < 0 || removeIdx < 0 || !(createIdx < logsIdx && logsIdx < removeIdx) {
		t.Fatalf("want create<logs<remove, calls=%v", f.calls)
	}
}

func TestRunOnceCreatesJobSpec(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "complete"}}}
	_, err := RunOnce(context.Background(), f, runParams())
	if err != nil {
		t.Fatal(err)
	}
	spec := f.createdSpec(name)
	if !spec.Job || spec.Process != "run" || spec.PublishedPort != 0 {
		t.Fatalf("spec: %+v", spec)
	}
	if len(spec.Command) != 4 || spec.Command[0] != "bundle" {
		t.Fatalf("command not split: %v", spec.Command)
	}
}

func TestRunOnceCommandFailed(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "failed", ExitCode: 7, Message: "task: non-zero exit (7)"}}}
	f.logs = map[string]string{name: "PG::UndefinedTable\n"}
	res, err := RunOnce(context.Background(), f, runParams())
	var cf *CommandFailedError
	if !errors.As(err, &cf) || cf.ExitCode != 7 {
		t.Fatalf("want CommandFailedError{7}, got %v", err)
	}
	if res == nil || res.ExitCode != 7 || !strings.Contains(res.Output, "PG::UndefinedTable") {
		t.Fatalf("failure must still carry result: %+v", res)
	}
	if !strings.Contains(strings.Join(f.calls, "|"), "remove:"+name) {
		t.Fatal("failed run must still remove the service")
	}
}

func TestRunOnceTimeout(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "running"}}} // never terminal
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err := RunOnce(ctx, f, runParams())
	if !errors.Is(err, ErrRunTimeout) {
		t.Fatalf("want ErrRunTimeout, got %v", err)
	}
	if !strings.Contains(strings.Join(f.calls, "|"), "remove:"+name) {
		t.Fatal("timeout must still remove the service")
	}
}

func TestRunOnceOutputCap(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.jobTasks = map[string][]JobTask{name: {{State: "complete"}}}
	f.logs = map[string]string{name: strings.Repeat("x", maxRunOutputBytes+100) + "TAIL"}
	res, err := RunOnce(context.Background(), f, runParams())
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Output) != maxRunOutputBytes || !strings.HasSuffix(res.Output, "TAIL") {
		t.Fatalf("want %d-byte TAIL-preserving cap, got %d", maxRunOutputBytes, len(res.Output))
	}
}

func TestRunOnceJobTasksErrorWithExpiredContext(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	f.logs = map[string]string{name: "partial output before timeout\n"}
	// Context starts live; we'll expire it DURING JobTasks via the hook
	ctx, cancel := context.WithCancel(context.Background())
	// Hook cancels ctx before we check the error, forcing the guard to decide
	// between taking the timeout path or returning the plain error.
	f.jobTasksHook = cancel
	f.jobTasksErr = context.Canceled
	res, err := RunOnce(ctx, f, runParams())
	// Should take the timeout path because ctx.Err() != nil when we check after JobTasks error
	if !errors.Is(err, ErrRunTimeout) {
		t.Fatalf("want ErrRunTimeout, got %v", err)
	}
	// Result should include best-effort logs
	if res == nil || res.ExitCode != -1 {
		t.Fatalf("timeout result must have ExitCode -1, got %+v", res)
	}
	if res.Output != "partial output before timeout\n" {
		t.Fatalf("want best-effort output, got %q", res.Output)
	}
	// Service must still be removed even on timeout
	if !strings.Contains(strings.Join(f.calls, "|"), "remove:"+name) {
		t.Fatal("timeout must still remove the service")
	}
}

func TestRunOnceJobTasksErrorWithLiveContext(t *testing.T) {
	fastPoll(t)
	f := newFakeSwarm()
	name := "wokku-run-myapp-01234567"
	// JobTasks will error immediately
	f.jobTasksErr = errors.New("API temporarily unavailable")
	// Use a background context that won't expire
	res, err := RunOnce(context.Background(), f, runParams())
	// Should return the plain error, not a timeout
	if !errors.Is(err, errors.New("API temporarily unavailable")) && err.Error() != "API temporarily unavailable" {
		t.Fatalf("want plain API error, got %v", err)
	}
	// Result should be nil (not the best-effort timeout path)
	if res != nil {
		t.Fatalf("plain error should return nil result, got %+v", res)
	}
	// Service must still be removed
	if !strings.Contains(strings.Join(f.calls, "|"), "remove:"+name) {
		t.Fatal("error cleanup must still remove the service")
	}
}
