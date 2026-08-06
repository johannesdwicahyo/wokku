package dockermon

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/docker/docker/api/types/events"
	"github.com/docker/docker/api/types/swarm"
	"github.com/docker/docker/api/types/system"

	"wokku.cloud/wokkud/internal/control"
)

type fakeAPI struct {
	oom  bool
	logs string
	err  error
}

func (f *fakeAPI) OOMKilled(ctx context.Context, id string) (bool, error) { return f.oom, f.err }
func (f *fakeAPI) LastLogs(ctx context.Context, id string, n int) (string, error) {
	return f.logs, f.err
}

func TestBuildEvent(t *testing.T) {
	api := &fakeAPI{oom: true, logs: "FATAL: out of memory\n"}
	ev := buildEvent(context.Background(), api, dieInfo{
		ContainerID: "abc123",
		Name:        "myapp.web.1",
		ExitCode:    137,
		At:          time.Unix(1751630400, 0),
	})
	if ev.Type != "container.died" || ev.Container != "myapp.web.1" || ev.ContainerID != "abc123" {
		t.Fatalf("identity: %+v", ev)
	}
	if ev.ExitCode != 137 || !ev.OOMKilled || ev.LogExcerpt != "FATAL: out of memory\n" {
		t.Fatalf("enrichment: %+v", ev)
	}
}

// I9: a Swarm task death carries the wokku.app label so the control plane
// can map it to an app (the task's container name can't be name-parsed).
func TestBuildEventCarriesAppLabel(t *testing.T) {
	ev := buildEvent(context.Background(), &fakeAPI{}, dieInfo{
		ContainerID: "swarmcid",
		Name:        "wokku-myapp-web.1.abc123xyz",
		App:         "myapp",
		ExitCode:    1,
	})
	if ev.App != "myapp" {
		t.Fatalf("app label not propagated: %+v", ev)
	}
}

func TestBuildEventSurvivesAPIErrors(t *testing.T) {
	api := &fakeAPI{err: errors.New("container already removed")}
	ev := buildEvent(context.Background(), api, dieInfo{ContainerID: "gone", Name: "myapp.web.1", ExitCode: 1})
	// Enrichment is best-effort: the death report still goes out.
	if ev.ExitCode != 1 || ev.OOMKilled || ev.LogExcerpt != "" {
		t.Fatalf("degraded event: %+v", ev)
	}
}

func TestSwarmState(t *testing.T) {
	info := system.Info{Swarm: swarm.Info{LocalNodeState: swarm.LocalNodeStateActive}}
	if got := swarmState(info, nil); got != "active" {
		t.Fatalf("swarmState: got %q, want %q", got, "active")
	}
}

func TestSwarmStateSurvivesInfoError(t *testing.T) {
	// cli.Info() failing (e.g. daemon down mid-beat) must degrade to "" —
	// vitals collection as a whole must not break on this.
	if got := swarmState(system.Info{}, errors.New("info: connection refused")); got != "" {
		t.Fatalf("swarmState on error: got %q, want empty", got)
	}
}

// stack.run job containers carry wokku.run=true alongside wokku.app — a
// failed post_deploy migration must not fire a false "app crashed" alert.
func TestHandleDieEventIgnoresRunContainers(t *testing.T) {
	msg := events.Message{Actor: events.Actor{
		ID: "runcid",
		Attributes: map[string]string{
			"name":      "wokku-run-myapp.1.xyz",
			"wokku.app": "myapp",
			"wokku.run": "true",
			"exitCode":  "1",
		},
	}}
	called := false
	handleDieEvent(context.Background(), &fakeAPI{}, msg, func(control.Event) { called = true })
	if called {
		t.Fatal("run-job container death must not be recorded as a crash")
	}
}

func TestHandleDieEventRecordsNormalDeaths(t *testing.T) {
	msg := events.Message{Actor: events.Actor{
		ID: "cid1",
		Attributes: map[string]string{
			"name":      "myapp.web.1",
			"wokku.app": "myapp",
			"exitCode":  "137",
		},
	}}
	var got control.Event
	called := false
	handleDieEvent(context.Background(), &fakeAPI{}, msg, func(ev control.Event) { called = true; got = ev })
	if !called {
		t.Fatal("a normal container death must still be recorded")
	}
	if got.App != "myapp" || got.ExitCode != 137 {
		t.Fatalf("event mismatch: %+v", got)
	}
}

func TestEventTime(t *testing.T) {
	if !eventTime(0).IsZero() {
		t.Fatal("missing msg.Time must map to zero time so buildEvent falls back to now")
	}
	if got := eventTime(1751630400); got != time.Unix(1751630400, 0) {
		t.Fatalf("real timestamps must pass through, got %v", got)
	}
}
