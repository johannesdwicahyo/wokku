package cronrun

import (
	"context"
	"strings"
	"testing"
	"time"
)

func containsArg(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}

// The container needs a deterministic name so a timed-out run can be reaped
// by name, and so a stale collision fails fast instead of silently double
// running.
func TestRunPassesDeterministicContainerName(t *testing.T) {
	origRun, origReap := execRunDocker, execReapContainer
	defer func() { execRunDocker, execReapContainer = origRun, origReap }()

	var gotArgs []string
	execRunDocker = func(ctx context.Context, env []string, args ...string) ([]byte, error) {
		gotArgs = args
		return []byte("ok"), nil
	}
	var reaped string
	execReapContainer = func(name string) { reaped = name }

	r := DockerRunner{}
	code, out := r.Run(Entry{ID: "abc123", ImageRef: "dokku/a:latest", Command: "true"}, nil)

	if code != 0 || out != "ok" {
		t.Fatalf("code=%d out=%q", code, out)
	}
	if !containsArg(gotArgs, "--name") || !containsArg(gotArgs, "wokku-cron-abc123") {
		t.Fatalf("args missing --name wokku-cron-abc123: %v", gotArgs)
	}
	if reaped != "wokku-cron-abc123" {
		t.Fatalf("expected reap of wokku-cron-abc123, got %q", reaped)
	}
}

// A timed-out run's docker CLI gets SIGKILLed by ctx cancellation, which can
// orphan the container it was running. The reap must still fire so orphans
// don't pile up every interval.
func TestRunReapsContainerOnTimeout(t *testing.T) {
	origRun, origReap := execRunDocker, execReapContainer
	defer func() { execRunDocker, execReapContainer = origRun, origReap }()

	execRunDocker = func(ctx context.Context, env []string, args ...string) ([]byte, error) {
		<-ctx.Done() // simulate a hung docker run killed by the timeout
		return []byte("partial"), ctx.Err()
	}
	reapCalled := make(chan string, 1)
	execReapContainer = func(name string) { reapCalled <- name }

	r := DockerRunner{}
	code, out := r.Run(Entry{ID: "t9", TimeoutSeconds: 1, ImageRef: "dokku/a:latest", Command: "sleep 10"}, nil)

	if code != 124 {
		t.Fatalf("want exit 124 on timeout, got %d", code)
	}
	if !strings.Contains(out, "timed out") {
		t.Fatalf("want timeout marker in output, got %q", out)
	}
	select {
	case name := <-reapCalled:
		if name != "wokku-cron-t9" {
			t.Fatalf("reaped wrong name: %q", name)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("reap was not called on timeout")
	}
}
