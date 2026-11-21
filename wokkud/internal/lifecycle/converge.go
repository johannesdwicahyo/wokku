// Package lifecycle is B5a's declarative converge engine: it diffs a desired
// app stack (from a stack.converge op's params) against the live Swarm
// services and applies the minimal set of create/update/scale/remove calls.
//
// The engine talks to Swarm only through the narrow swarmAPI interface, so
// all of the diff logic is unit-tested against a recording fake (no daemon).
// swarm.go is the thin real translation over the Docker SDK.
package lifecycle

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// JobTask is one task of a run-job service, terminal states included.
type JobTask struct {
	State    string // swarm task state: "complete", "failed", "rejected", …
	ExitCode int
	Message  string // t.Status.Err — scheduler/runtime error detail
}

// swarmAPI is the narrow Swarm surface the converge engine needs — same
// pattern as dockermon's api and services' dockerAPI: the smallest shape the
// caller needs, not the full SDK client. Ownership is always by label
// (wokku.app etc.), never by parsing the service name back apart.
type swarmAPI interface {
	// ServiceList returns the live wokku-managed services for one app,
	// filtered by the wokku.app=<appLabel> label.
	ServiceList(ctx context.Context, appLabel string) ([]ServiceInfo, error)
	ServiceCreate(ctx context.Context, spec ServiceSpec) error
	// ServiceUpdate replaces the spec of an existing service. forceRestart
	// bumps the task force-update counter so a restart happens even when the
	// spec is otherwise unchanged.
	ServiceUpdate(ctx context.Context, name string, spec ServiceSpec, forceRestart bool) error
	ServiceRemove(ctx context.Context, name string) error
	// TaskList returns all wokku.managed=true tasks (heartbeat / crash feed).
	TaskList(ctx context.Context) ([]TaskInfo, error)
	NetworkEnsureOverlay(ctx context.Context, name string) error
	// ImageTagPush re-tags a locally-built image to a registry ref and pushes
	// it — the tag_from_local adopt shim, called by Converge before any
	// service create/update when TagFromLocal is set (Task 10).
	ImageTagPush(ctx context.Context, localRef, registryRef string) error
	// RolloutStatus returns a service's Swarm rolling-update status.
	RolloutStatus(ctx context.Context, name string) (RolloutStatus, error)
	// ImageEntrypoint returns the image's ENTRYPOINT; an error (image not
	// local) means "unknown" and callers fall back to exec form.
	ImageEntrypoint(ctx context.Context, ref string) ([]string, error)
	// JobTasks returns ALL tasks of one service by name, terminal states
	// included (TaskList deliberately drops terminal history; a finished
	// job's Complete/Failed task is exactly what stack.run polls for).
	JobTasks(ctx context.Context, serviceName string) ([]JobTask, error)
	// ServiceLogs returns the combined stdout+stderr of a service's tasks.
	ServiceLogs(ctx context.Context, serviceName string) (string, error)
}

// Mount is one persistent volume attachment. Named Docker volumes, not host
// binds: Docker seeds a fresh named volume's CONTENT and OWNERSHIP from the
// image path on first mount, which host binds do not. That matters for images
// mounting a populated path (nextcloud/wordpress mount their whole
// /var/www/html webroot) and for images running as a non-root uid (grafana
// runs as 472). Volumes also live under /var/lib/docker, outside the
// /var/lib/dokku tree B6 W8 removes.
type Mount struct {
	Volume string `json:"volume"` // named volume, conventionally wokku-<app>-<name>
	Path   string `json:"path"`   // absolute container path
}

// Healthcheck overrides the image's HEALTHCHECK. Without one, Swarm's
// start-first rollout counts a task healthy the instant it is Running, so
// slow-boot images (ghost, umami — roughly 60s) drop the old task too early
// and blip on every deploy.
type Healthcheck struct {
	Test           []string `json:"test"` // docker form, e.g. ["CMD-SHELL", "curl -f localhost:3000 || exit 1"]
	IntervalSec    int      `json:"interval_sec"`
	TimeoutSec     int      `json:"timeout_sec"`
	Retries        int      `json:"retries"`
	StartPeriodSec int      `json:"start_period_sec"`
}

// ServiceSpec is the desired state of one Swarm service, narrowed to exactly
// what the engine computes so the fake records plain values.
type ServiceSpec struct {
	Name, App, Process, DeployID, Image string
	Command                             []string
	// Args overrides the image CMD. omitempty: unset must not change the
	// SpecHash of services that predate it.
	Args                      []string `json:"args,omitempty"`
	Env                       map[string]string
	Replicas                  int
	MemoryMB                  int
	CPU                       float64
	Networks                  []string
	PublishedPort, TargetPort int // 0 = don't publish

	// B5b. Tagged omitempty so a service using neither marshals — and
	// therefore hashes — exactly as it did before B5b. TestSpecHashStable
	// AcrossB5bFields pins this; do not remove the tags.
	Mounts      []Mount      `json:"mounts,omitempty"`
	Healthcheck *Healthcheck `json:"healthcheck,omitempty"`

	// Job marks a one-off stack.run service: ReplicatedJob mode, restart
	// condition none, wokku.run label instead of wokku.managed. omitempty is
	// LOAD-BEARING — Job=false must not change existing services' SpecHash.
	Job bool `json:"job,omitempty"`
}

// SpecHash is the change-detection fingerprint stored as a service label.
// json.Marshal is deterministic for structs (fixed field order) and maps
// (sorted keys), so identical desired state always hashes identically.
// Covers EVERYTHING in the spec — the old image/replicas/deploy_id triple
// missed command/env/resource-only changes, which silently never applied
// to a live service (wicara-rails kept its crash-looping $PORT command
// after the fix shipped; config:set on a flagged app was a no-op).
func (s ServiceSpec) SpecHash() string {
	b, _ := json.Marshal(s)
	return fmt.Sprintf("%x", sha256.Sum256(b))
}

// ServiceInfo is the live-state slice ServiceList returns — only what the
// diff needs. Ownership fields come from labels, not the name.
type ServiceInfo struct {
	Name     string
	App      string
	Process  string
	DeployID string
	Image    string
	Replicas int
	SpecHash string // wokku.spec-hash label; "" on services created pre-hash
}

// TaskInfo is one wokku.managed task, narrowed for the heartbeat/crash feed.
// The converge engine does not consume it; it rides the interface because the
// same real client serves both.
type TaskInfo struct {
	ServiceName  string
	App          string
	Process      string
	State        string
	DesiredState string
	ContainerID  string
	StartedAt    time.Time
	ExitCode     int
}

// ProcResources is the per-process resource block from op params
// (resources: {web: {memory_mb, cpu}, …}).
type ProcResources struct {
	MemoryMB  int     `json:"memory_mb"`
	CPUShares float64 `json:"cpu"`
}

// ServiceParams is one service's desired state in the B5b per-service param
// shape. It replaces the pre-B5b arrangement of an app-level image plus three
// parallel maps (formation / formation_commands / resources) keyed by process.
type ServiceParams struct {
	Image       string            `json:"image"`
	Command     string            `json:"command"`
	Replicas    int               `json:"replicas"`
	Env         map[string]string `json:"env"`
	MemoryMB    int               `json:"memory_mb"`
	CPU         float64           `json:"cpu"`
	Public      bool              `json:"public"`
	TargetPort  int               `json:"target_port"`
	Mounts      []Mount           `json:"mounts,omitempty"`
	Healthcheck *Healthcheck      `json:"healthcheck,omitempty"`
}

// ConvergeParams is decoded straight from a stack.converge op's params by the
// executor (Task 7); JSON tags are the wire contract. App is set by the
// executor from the op's app record — it is not one of the params the control
// plane assembles (there is no app key in the op params), so it carries the
// `app` tag defensively but is normally populated in Go.
type ConvergeParams struct {
	App       string         `json:"app"`
	DeployID  string         `json:"deploy_id"`
	ImageRef  string         `json:"image_ref"`
	Formation map[string]int `json:"formation"`
	// Services is the B5b per-service shape. When present it wins outright.
	// When absent the legacy Formation/FormationCommands/Resources trio is
	// normalized into it — every op already persisted in lifecycle_ops is the
	// legacy shape, and converge! falls back to those rows.
	Services          map[string]ServiceParams `json:"services"`
	FormationCommands map[string]string        `json:"formation_commands"`
	Env               map[string]string        `json:"env"`
	Resources         map[string]ProcResources `json:"resources"`
	PublishedPort     int                      `json:"published_port"`
	ContainerPort     int                      `json:"container_port"`
	Networks          []string                 `json:"networks"`
	Restart           bool                     `json:"restart"`
	TagFromLocal      bool                     `json:"tag_from_local"`
	// LocalRef is the dokku-built local image (conventionally
	// dokku/<app>:latest) to tag+push to the registry before converging —
	// only read when TagFromLocal is true (the adopt shim, Task 10).
	LocalRef string `json:"local_ref"`
}

// ConvergeResult reports which services the converge touched.
type ConvergeResult struct {
	Created []string
	Updated []string
	Removed []string
}

// RolloutStatus is a service's Swarm UpdateStatus; State "" = none.
type RolloutStatus struct {
	State     string // updating, completed, paused, rollback_started, rollback_paused, rollback_completed
	StartedAt time.Time
	Message   string
}

// ErrRolloutFailed: the new tasks never became healthy and Swarm restored the
// previous version (FailureAction rollback). Before this, converge returned
// the moment Swarm ACCEPTED the update, so a crashing deploy reported
// "succeeded" while Swarm quietly rolled it back (schdl, 2026-11-21).
var ErrRolloutFailed = errors.New("new version did not start; Swarm kept the previous version")

// ErrCodeRolloutFailed is the control-plane error_code for ErrRolloutFailed.
const ErrCodeRolloutFailed = "rollout_failed"

// Rollout wait knobs (vars for tests). rolloutGrace bounds the wait for an
// update that never shows a fresh UpdateStatus — Swarm had nothing to roll.
var (
	rolloutPoll  = time.Second
	rolloutGrace = time.Minute
)

// waitRollout blocks until the rolling update Swarm started at/after since
// completes; any other terminal state is ErrRolloutFailed.
func waitRollout(ctx context.Context, s swarmAPI, name string, since time.Time) error {
	grace := time.Now().Add(rolloutGrace)
	for {
		st, err := s.RolloutStatus(ctx, name)
		if err != nil {
			return err
		}
		if st.State != "" && !st.StartedAt.Before(since) { // ours, not a previous deploy's
			switch st.State {
			case "completed":
				return nil
			case "updating":
			default:
				return fmt.Errorf("%s: %w (%s): %s", name, ErrRolloutFailed, st.State, st.Message)
			}
		} else if time.Now().After(grace) {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(rolloutPoll):
		}
	}
}

// rolls reports whether an update replaces running tasks (a rolling update
// Swarm can fail and roll back) rather than only scaling. Scale to/from 0
// starts or stops tasks without an update — a crash there surfaces through
// the crash-loop detector, not here.
// ponytail: a published-port-only change also counts as rolling and waits out
// rolloutGrace; compare endpoint specs if that ever matters.
func rolls(cur ServiceInfo, spec ServiceSpec, restart bool) bool {
	if cur.Replicas == 0 || spec.Replicas == 0 {
		return false
	}
	if restart {
		return true
	}
	if cur.SpecHash == "" {
		return cur.Image != spec.Image || cur.DeployID != spec.DeployID
	}
	scaled := spec
	scaled.Replicas = cur.Replicas
	return scaled.SpecHash() != cur.SpecHash
}

// ErrFormationWouldEmpty is the defensive guard: a converge that would drop
// the last running web service (live web running, desired formation omits the
// web key) is refused with no writes. The executor maps it to error_code
// ErrCodeFormationWouldEmpty.
var ErrFormationWouldEmpty = errors.New("formation would remove the last running web service")

// ErrCodeFormationWouldEmpty is the control-plane error_code for the guard.
const ErrCodeFormationWouldEmpty = "formation_would_empty"

// ServiceName is the Swarm service name for an app's process type. Dots are
// not allowed in Swarm service names, so app/proc must already be dot-free.
func ServiceName(app, proc string) string {
	return fmt.Sprintf("wokku-%s-%s", app, proc)
}

// Converge diffs the desired formation against the live services and applies
// the minimum create/update/remove set. Identical desired state issues zero
// writes.
func Converge(ctx context.Context, s swarmAPI, p ConvergeParams) (*ConvergeResult, error) {
	// Adopt shim: the app's only image is dokku-built and local to this host
	// (never pushed to the registry) — tag+push it before any service
	// create/update, so the image Swarm is about to pull already exists.
	if p.TagFromLocal {
		if err := s.ImageTagPush(ctx, p.LocalRef, p.ImageRef); err != nil {
			return nil, err
		}
	}

	live, err := s.ServiceList(ctx, p.App)
	if err != nil {
		return nil, err
	}
	liveByProc := make(map[string]ServiceInfo, len(live))
	for _, svc := range live {
		liveByProc[svc.Process] = svc
	}

	desired := p.serviceParams()

	// Defensive guard, before any write: refuse a converge that would remove a
	// running "web" service outright (removal, not a scale-to-0 stop, which
	// keeps the key present). Only "web" can ever be guarded here: the check
	// is keyed off `desired`, so a public non-web service being dropped is
	// indistinguishable from one that was never public — ServiceInfo (the
	// live side) carries no publish flag to compare against. Guarding those
	// properly needs a Published field on ServiceInfo sourced from the Swarm
	// EndpointSpec, plus an explicit override so a deliberate public-service
	// rename still goes through. Deferred to B5b Stage 2, where non-web public
	// services first exist.
	if live, ok := liveByProc["web"]; ok && live.Replicas > 0 {
		if _, present := desired["web"]; !present {
			return nil, ErrFormationWouldEmpty
		}
	}

	res := &ConvergeResult{}

	// Ensure overlay networks exist only when we are about to create at least
	// one service — an all-idempotent converge must not write, and existing
	// services already carry their attachments.
	networksEnsured := false
	ensureNetworks := func() error {
		if networksEnsured {
			return nil
		}
		for _, n := range p.Networks {
			if err := s.NetworkEnsureOverlay(ctx, n); err != nil {
				return err
			}
		}
		networksEnsured = true
		return nil
	}

	type rollout struct {
		name  string
		since time.Time
	}
	var rolling []rollout
	entrypoints := map[string][]string{}
	for name, sp := range desired {
		ep, seen := entrypoints[sp.Image]
		if !seen {
			ep, _ = s.ImageEntrypoint(ctx, sp.Image) // unknown → nil → exec form
			entrypoints[sp.Image] = ep
		}
		spec := p.specFor(name, sp, ep)
		cur, exists := liveByProc[name]
		if !exists {
			if err := ensureNetworks(); err != nil {
				return nil, err
			}
			if err := s.ServiceCreate(ctx, spec); err != nil {
				return nil, err
			}
			res.Created = append(res.Created, spec.Name)
			continue
		}
		// Hash-based change detection when the live service carries the
		// label; services created before the hash shipped fall back to the
		// legacy triple and pick the label up on their next real update.
		changed := cur.Image != spec.Image ||
			cur.Replicas != spec.Replicas ||
			cur.DeployID != spec.DeployID
		if cur.SpecHash != "" {
			changed = cur.SpecHash != spec.SpecHash()
		}
		if changed || p.Restart {
			since := time.Now().Add(-2 * time.Second) // manager clock is this host's; small skew slack
			if err := s.ServiceUpdate(ctx, spec.Name, spec, p.Restart); err != nil {
				return nil, err
			}
			res.Updated = append(res.Updated, spec.Name)
			if rolls(cur, spec, p.Restart) {
				rolling = append(rolling, rollout{spec.Name, since})
			}
		}
	}

	// Wait after all writes so an app's processes roll in parallel.
	for _, r := range rolling {
		if err := waitRollout(ctx, s, r.name, r.since); err != nil {
			return res, err
		}
	}

	// Remove services for process types absent from the desired formation.
	for proc, svc := range liveByProc {
		if _, present := desired[proc]; present {
			continue
		}
		if err := s.ServiceRemove(ctx, svc.Name); err != nil {
			return nil, err
		}
		res.Removed = append(res.Removed, svc.Name)
	}

	return res, nil
}

// serviceParams returns the desired services, normalizing the legacy shape
// when the new one is absent. In the legacy shape every service shares one
// image and one env, and only "web" is public — exactly the pre-B5b engine.
func (p ConvergeParams) serviceParams() map[string]ServiceParams {
	if len(p.Services) > 0 {
		return p.Services
	}
	out := make(map[string]ServiceParams, len(p.Formation))
	for proc, count := range p.Formation {
		sp := ServiceParams{
			Image:    p.ImageRef,
			Command:  p.FormationCommands[proc],
			Replicas: count,
			Env:      p.Env,
		}
		if r, ok := p.Resources[proc]; ok {
			sp.MemoryMB = r.MemoryMB
			sp.CPU = r.CPUShares
		}
		if proc == "web" {
			sp.Public = true
			sp.TargetPort = p.ContainerPort
		}
		out[proc] = sp
	}
	return out
}

// specFor builds the desired ServiceSpec for one service. Only the service
// marked Public publishes a port — pre-B5b this was hardcoded to proc == "web".
func (p ConvergeParams) specFor(name string, sp ServiceParams, entrypoint []string) ServiceSpec {
	command, args := processCommand(entrypoint, sp.Command)
	spec := ServiceSpec{
		Name:        ServiceName(p.App, name),
		App:         p.App,
		Process:     name,
		DeployID:    p.DeployID,
		Image:       sp.Image,
		Command:     command,
		Args:        args,
		Env:         sp.Env,
		Replicas:    sp.Replicas,
		MemoryMB:    sp.MemoryMB,
		CPU:         sp.CPU,
		Networks:    p.Networks,
		Mounts:      sp.Mounts,
		Healthcheck: sp.Healthcheck,
	}
	if sp.Public && p.PublishedPort != 0 {
		spec.PublishedPort = p.PublishedPort
		spec.TargetPort = sp.TargetPort
	}
	return spec
}

// Remove deletes every wokku-<app>-* service (stack.remove: destroy / evict).
func Remove(ctx context.Context, s swarmAPI, appName string) error {
	live, err := s.ServiceList(ctx, appName)
	if err != nil {
		return err
	}
	for _, svc := range live {
		if err := s.ServiceRemove(ctx, svc.Name); err != nil {
			return err
		}
	}
	return nil
}
