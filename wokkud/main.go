// wokkud/main.go
// wokkud — the Wokku host agent (Track A Phase 1: observe + report).
// Dials OUT only: the control plane never connects to the host. A dead
// host is detected upstream by the absence of heartbeats.
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wokku.cloud/wokkud/internal/builder"
	"wokku.cloud/wokkud/internal/config"
	"wokku.cloud/wokkud/internal/control"
	"wokku.cloud/wokkud/internal/cronrun"
	"wokku.cloud/wokkud/internal/dockermon"
	"wokku.cloud/wokkud/internal/lifecycle"
	"wokku.cloud/wokkud/internal/registry"
	"wokku.cloud/wokkud/internal/router"
	"wokku.cloud/wokkud/internal/services"
	"wokku.cloud/wokkud/internal/vitals"
)

// Version is stamped at build time via -ldflags "-X main.Version=…".
var Version = "0.7.0"

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "wokkud:", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	mon, err := dockermon.New()
	if err != nil {
		// Still heartbeat with docker="down" — a broken docker socket is
		// exactly the kind of thing the control plane must hear about.
		log.Printf("wokkud: docker client unavailable: %v", err)
	}
	client := control.New(cfg.URL, cfg.Token, Version)
	builds := builder.NewExecutor(ctx, client)

	// Registry GC duty: self-scheduled `registry garbage-collect` +
	// `docker image prune -f` against the per-host loopback registry —
	// skipped whenever a build is in flight (builds.Busy) so GC never
	// contends with a build for disk I/O. This REPLACES the old
	// /etc/cron.weekly/wokku-registry-gc cron (provisioned by install.sh,
	// live on jkt-01 since Jul 8) which ran --delete-untagged with no
	// busy-guard — the exact race this ticker exists to prevent. install.sh
	// now deletes that cron file on upgrade; this ticker is the only GC path.
	go registry.RunGCTicker(ctx, registry.GCInterval(), builds.Busy, registry.HostExec{})

	// Cron duty (Track B B3): declarative schedule sync + one-off container
	// fires. Never nil — a missing docker binary degrades per-fire inside
	// DockerRunner.Run, not dark at boot (unlike router/services above).
	cronSched := cronrun.NewScheduler(client, cronrun.DockerRunner{})

	// Router duty (Track B B1): nil (dark) until deploy/install.sh puts a
	// caddy binary on the host. Nil-safe throughout.
	rtr := router.New(client, cfg.URL, cfg.Token)
	if rtr == nil {
		log.Println("wokkud: router duty dark (no caddy on PATH)")
	}

	// Services duty (Track B B4): datastore ops via the Docker SDK. Nil
	// (dark) if docker can't init — the agent keeps heartbeating and simply
	// never claims service ops.
	svcs, err := services.NewRealExecutor(ctx, client)
	if err != nil {
		log.Printf("wokkud: services duty dark (docker unavailable): %v", err)
	}

	// Lifecycle duty (Track B B5a): Swarm stack converge/remove ops + the
	// task-state heartbeat feed. Nil (dark) if docker can't init — the agent
	// keeps heartbeating with no tasks and never claims lifecycle ops.
	lc, err := lifecycle.NewRealExecutor(ctx, client)
	if err != nil {
		log.Printf("wokkud: lifecycle duty dark (docker unavailable): %v", err)
	}

	// Loop 2: container deaths (only if docker is reachable at boot;
	// systemd Restart=always re-runs us until it is).
	if mon != nil {
		go mon.WatchDeaths(ctx, func(ev control.Event) {
			log.Printf("wokkud: container died: %s exit=%d oom=%t", ev.Container, ev.ExitCode, ev.OOMKilled)
			if err := client.PostEvents([]control.Event{ev}); err != nil {
				log.Printf("wokkud: %v", err)
			}
		})
	}

	// Loop 1: heartbeat. Fires immediately, then every cfg.Interval.
	log.Printf("wokkud %s → %s every %s", Version, cfg.URL, cfg.Interval)
	ticker := time.NewTicker(cfg.Interval)
	defer ticker.Stop()
	for {
		beat(ctx, mon, client, builds, rtr, svcs, lc, cronSched)
		select {
		case <-ctx.Done():
			log.Println("wokkud: shutting down")
			return
		case <-ticker.C:
		}
	}
}

func beat(ctx context.Context, mon *dockermon.Monitor, client *control.Client, builds *builder.Executor, rtr *router.Manager, svcs *services.Executor, lc *lifecycle.Executor, cronSched *cronrun.Scheduler) {
	dockerStatus := "down"
	if mon != nil {
		dockerStatus = mon.PingStatus(ctx)
	}
	v, err := vitals.Collect(dockerStatus)
	if err != nil {
		// Partial vitals still ship — Docker status alone is valuable.
		log.Printf("wokkud: vitals: %v", err)
		v.Docker = dockerStatus
	}
	v.Registry = registryStatus(ctx)
	v.Router, v.RouterConfigApplied = rtr.Status(ctx)
	if mon != nil {
		v.Swarm = mon.SwarmStatus(ctx)
	}
	resp, err := client.PostHeartbeat(v, lc.TaskStates(ctx))
	if err != nil {
		log.Printf("wokkud: heartbeat: %v", err)
		return
	}
	for _, id := range resp.PendingBuildIDs {
		builds.Enqueue(id)
	}
	if svcs != nil {
		for _, id := range resp.PendingServiceOpIDs {
			svcs.Enqueue(id)
		}
	}
	if lc != nil {
		for _, id := range resp.PendingLifecycleOpIDs {
			lc.Enqueue(id)
		}
	}
	rtr.Sync(ctx, resp.RouterConfigVersion)
	if resp.CronConfigVersion != "" && resp.CronConfigVersion != cronSched.AppliedVersion() {
		go cronSched.Sync()
	}
}

// registryStatus probes the local registry started by deploy/install.sh.
// "unreachable" on hosts that don't run one — harmless noise in vitals.
func registryStatus(ctx context.Context) string {
	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, "http://127.0.0.1:5000/v2/", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "unreachable"
	}
	resp.Body.Close()
	return "ok"
}
