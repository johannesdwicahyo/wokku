// Package dockermon watches the Docker daemon: liveness ping + container-death
// events enriched with OOM flag and a log tail. Enrichment is best-effort —
// a dead container may already be gone (that exact race is why the
// old SSH-poll CrashEvent capture missed crashes; the die event itself
// always arrives).
package dockermon

import (
	"bytes"
	"context"
	"log"
	"strconv"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/events"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/system"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/stdcopy"

	"wokku.cloud/wokkud/internal/control"
)

const logTailLines = 200

// api is the narrow slice of the Docker client buildEvent needs —
// interface so tests run without a daemon.
type api interface {
	OOMKilled(ctx context.Context, id string) (bool, error)
	LastLogs(ctx context.Context, id string, n int) (string, error)
}

type dieInfo struct {
	ContainerID string
	Name        string
	App         string // from the wokku.app container label (Swarm task naming defeats name-parsing)
	ExitCode    int
	At          time.Time
}

type Monitor struct {
	cli *client.Client
}

func New() (*Monitor, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, err
	}
	return &Monitor{cli: cli}, nil
}

func (m *Monitor) PingStatus(ctx context.Context) string {
	pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if _, err := m.cli.Ping(pingCtx); err != nil {
		return "down"
	}
	return "ok"
}

// SwarmStatus reports the Docker daemon's raw Swarm.LocalNodeState (e.g.
// "active"/"inactive") for the vitals heartbeat — the B5a adopt guard
// (lifecycle.rake) gates on vitals["swarm"] == "active".
func (m *Monitor) SwarmStatus(ctx context.Context) string {
	infoCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	info, err := m.cli.Info(infoCtx)
	return swarmState(info, err)
}

// swarmState is split from SwarmStatus so it's testable without a daemon —
// same split as parseMeminfo/parseLoadavg in the vitals package. Any error
// collecting swarm state (daemon unreachable mid-beat, etc.) degrades to ""
// rather than failing the whole heartbeat.
func swarmState(info system.Info, err error) string {
	if err != nil {
		return ""
	}
	return string(info.Swarm.LocalNodeState)
}

// WatchDeaths blocks until ctx is done, invoking onDeath for every
// container die event. Stream errors trigger a resubscribe after 5s.
func (m *Monitor) WatchDeaths(ctx context.Context, onDeath func(control.Event)) {
	f := filters.NewArgs()
	f.Add("type", "container")
	f.Add("event", "die")

	for ctx.Err() == nil {
		msgs, errs := m.cli.Events(ctx, events.ListOptions{Filters: f})
	stream:
		for {
			select {
			case <-ctx.Done():
				return
			case err := <-errs:
				log.Printf("wokkud: docker event stream error, resubscribing in 5s: %v", err)
				select {
				case <-time.After(5 * time.Second):
				case <-ctx.Done():
					return
				}
				break stream
			case msg := <-msgs:
				handleDieEvent(ctx, m, msg, onDeath)
			}
		}
	}
}

// handleDieEvent applies the wokku.run guard and, for real crashes, builds
// and delivers the death event. Split out from WatchDeaths so it's testable
// without a Docker daemon (msg is a plain events.Message, a stands in for
// the client). stack.run job containers are tagged wokku.run=true alongside
// wokku.app — their death is an op result, not a crash, and must not fire a
// false "app crashed" alert.
func handleDieEvent(ctx context.Context, a api, msg events.Message, onDeath func(control.Event)) {
	if msg.Actor.Attributes["wokku.run"] == "true" {
		return
	}
	exitCode, _ := strconv.Atoi(msg.Actor.Attributes["exitCode"])
	onDeath(buildEvent(ctx, a, dieInfo{
		ContainerID: msg.Actor.ID,
		Name:        msg.Actor.Attributes["name"],
		// Docker die events carry the dead container's labels in
		// Actor.Attributes. Swarm task containers are named
		// wokku-<app>-<proc>.<slot>.<taskid>, which name-parsing on
		// the control plane can't map back to an app — the label can.
		App:      msg.Actor.Attributes["wokku.app"],
		ExitCode: exitCode,
		At:       eventTime(msg.Time),
	}))
}

func (m *Monitor) OOMKilled(ctx context.Context, id string) (bool, error) {
	insp, err := m.cli.ContainerInspect(ctx, id)
	if err != nil {
		return false, err
	}
	return insp.State != nil && insp.State.OOMKilled, nil
}

func (m *Monitor) LastLogs(ctx context.Context, id string, n int) (string, error) {
	rc, err := m.cli.ContainerLogs(ctx, id, container.LogsOptions{
		ShowStdout: true, ShowStderr: true, Tail: strconv.Itoa(n),
	})
	if err != nil {
		return "", err
	}
	defer rc.Close()
	var buf bytes.Buffer
	if _, err := stdcopy.StdCopy(&buf, &buf, rc); err != nil {
		return buf.String(), nil // partial logs beat no logs
	}
	return buf.String(), nil
}

// eventTime keeps the "fallback to now" guard meaningful: time.Unix(0, 0)
// is 1970, not time.Time{}, so a missing msg.Time must be caught before
// conversion or buildEvent's IsZero check never fires on the real path.
func eventTime(unixSec int64) time.Time {
	if unixSec == 0 {
		return time.Time{}
	}
	return time.Unix(unixSec, 0)
}

func buildEvent(ctx context.Context, a api, d dieInfo) control.Event {
	ev := control.Event{
		Type:        "container.died",
		Container:   d.Name,
		App:         d.App,
		ContainerID: d.ContainerID,
		ExitCode:    d.ExitCode,
		ExitedAt:    d.At,
	}
	if d.At.IsZero() {
		ev.ExitedAt = time.Now()
	}
	// Best-effort enrichment: the container may already be removed.
	if oom, err := a.OOMKilled(ctx, d.ContainerID); err == nil {
		ev.OOMKilled = oom
	}
	if logs, err := a.LastLogs(ctx, d.ContainerID, logTailLines); err == nil {
		ev.LogExcerpt = logs
	}
	return ev
}
