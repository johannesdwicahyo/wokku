// swarm.go is the real Docker SDK implementation of swarmAPI. It is thin by
// design — translation only, no diff logic (that all lives in converge.go and
// is unit-tested against the fake). The fixed update/restart/publish policy
// from spec §3.2 is baked in here where the SDK structs are built, since it
// never varies per app.
package lifecycle

import (
	"bytes"
	"context"
	"io"
	"strings"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/network"
	"github.com/docker/docker/api/types/swarm"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/jsonmessage"
	"github.com/docker/docker/pkg/stdcopy"
)

// Fixed rollout policy (spec §3.2) — same for every wokku service.
const (
	updateMonitor = 15 * time.Second
	restartWindow = 30 * time.Second
	restartMax    = uint64(3)
	labelManaged  = "wokku.managed"
	labelApp      = "wokku.app"
	labelProcess  = "wokku.process"
	labelDeploy   = "wokku.deploy"
	labelSpecHash = "wokku.spec-hash"
	labelRun      = "wokku.run"
)

type realSwarmAPI struct {
	cli *client.Client
}

// NewSwarmAPI builds the real Docker-SDK-backed swarmAPI, same construction as
// dockermon.New / services.newDockerAPI.
func NewSwarmAPI() (swarmAPI, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, err
	}
	return &realSwarmAPI{cli: cli}, nil
}

func (r *realSwarmAPI) ServiceList(ctx context.Context, appLabel string) ([]ServiceInfo, error) {
	f := filters.NewArgs()
	f.Add("label", labelManaged+"=true")
	f.Add("label", labelApp+"="+appLabel)
	svcs, err := r.cli.ServiceList(ctx, swarm.ServiceListOptions{Filters: f})
	if err != nil {
		return nil, err
	}
	out := make([]ServiceInfo, 0, len(svcs))
	for _, s := range svcs {
		labels := s.Spec.Labels
		info := ServiceInfo{
			Name:     s.Spec.Name,
			App:      labels[labelApp],
			Process:  labels[labelProcess],
			DeployID: labels[labelDeploy],
			SpecHash: labels[labelSpecHash],
		}
		if cs := s.Spec.TaskTemplate.ContainerSpec; cs != nil {
			info.Image = cs.Image
		}
		if m := s.Spec.Mode.Replicated; m != nil && m.Replicas != nil {
			info.Replicas = int(*m.Replicas)
		}
		out = append(out, info)
	}
	return out, nil
}

func (r *realSwarmAPI) ServiceCreate(ctx context.Context, spec ServiceSpec) error {
	_, err := r.cli.ServiceCreate(ctx, buildSpec(spec), swarm.ServiceCreateOptions{})
	return err
}

func (r *realSwarmAPI) ServiceUpdate(ctx context.Context, name string, spec ServiceSpec, forceRestart bool) error {
	// ServiceUpdate needs the current object version to avoid clobbering a
	// concurrent write; fetch it by name.
	cur, _, err := r.cli.ServiceInspectWithRaw(ctx, name, swarm.ServiceInspectOptions{})
	if err != nil {
		return err
	}
	sp := buildSpec(spec)
	if forceRestart {
		// Bump ForceUpdate past the live value so Swarm restarts tasks even
		// when the spec is otherwise identical.
		sp.TaskTemplate.ForceUpdate = cur.Spec.TaskTemplate.ForceUpdate + 1
	}
	_, err = r.cli.ServiceUpdate(ctx, cur.ID, cur.Version, sp, swarm.ServiceUpdateOptions{})
	return err
}

func (r *realSwarmAPI) ServiceRemove(ctx context.Context, name string) error {
	return r.cli.ServiceRemove(ctx, name)
}

// liveTask reports whether a Swarm task is current (the orchestrator still
// wants it running, or it's actively starting) rather than shutdown-desired
// terminal history. Split out for table-testing without a daemon.
func liveTask(desiredState, state string) bool {
	if desiredState == "running" {
		return true
	}
	switch state {
	case "running", "starting", "pending":
		return true
	}
	return false
}

func (r *realSwarmAPI) TaskList(ctx context.Context) ([]TaskInfo, error) {
	// No API-side label filter: Swarm tasks carry EMPTY task-level labels
	// (the wokku.* set lives on Spec.ContainerSpec.Labels), so a label
	// filter here matches nothing. List all and select client-side.
	tasks, err := r.cli.TaskList(ctx, swarm.TaskListOptions{})
	if err != nil {
		return nil, err
	}
	out := make([]TaskInfo, 0, len(tasks))
	for _, t := range tasks {
		if info, ok := taskInfo(t); ok {
			out = append(out, info)
		}
	}
	return out, nil
}

// taskInfo maps a Swarm task to a TaskInfo, reading ownership from
// Spec.ContainerSpec.Labels (task-level labels are empty in practice).
// ok=false drops unmanaged tasks and terminal task HISTORY (~5 dead tasks
// per slot per the task-history-limit) whose counting would inflate the
// scale read — keep only tasks the orchestrator still wants running, or
// that are actively coming up.
func taskInfo(t swarm.Task) (TaskInfo, bool) {
	cs := t.Spec.ContainerSpec
	if cs == nil || cs.Labels[labelManaged] != "true" {
		return TaskInfo{}, false
	}
	if !liveTask(string(t.DesiredState), string(t.Status.State)) {
		return TaskInfo{}, false
	}
	info := TaskInfo{
		App:          cs.Labels[labelApp],
		Process:      cs.Labels[labelProcess],
		ServiceName:  ServiceName(cs.Labels[labelApp], cs.Labels[labelProcess]),
		State:        string(t.Status.State),
		DesiredState: string(t.DesiredState),
		// Swarm tasks don't carry a dedicated started-at; the status
		// timestamp is when the current state was entered, which for a
		// running task is its start.
		StartedAt: t.Status.Timestamp,
	}
	if t.Status.ContainerStatus != nil {
		info.ContainerID = t.Status.ContainerStatus.ContainerID
		info.ExitCode = t.Status.ContainerStatus.ExitCode
	}
	return info, true
}

// NetworkEnsureOverlay creates the named attachable overlay network if it
// doesn't exist. Mirrors services.realDockerAPI.NetworkEnsure (bridge there,
// overlay here — Swarm services need a swarm-scoped overlay for cross-node DNS
// so DB hostnames resolve); the ~10 lines are duplicated rather than shared
// because the driver/scope differ and the two live in different packages.
func (r *realSwarmAPI) NetworkEnsureOverlay(ctx context.Context, name string) error {
	if _, err := r.cli.NetworkInspect(ctx, name, network.InspectOptions{}); err == nil {
		return nil
	}
	_, err := r.cli.NetworkCreate(ctx, name, network.CreateOptions{
		Driver:     "overlay",
		Attachable: true,
	})
	if err != nil && strings.Contains(err.Error(), "already exists") {
		return nil // lost a create race — the network exists, which is all we need
	}
	return err
}

// ImageTagPush is the tag_from_local adopt shim: retag a locally-built image
// under a registry ref and push it. Called by Converge (converge.go) before
// any service create/update when the op's params carry tag_from_local, so
// the image already exists in the registry by the time Swarm goes to pull it.
func (r *realSwarmAPI) ImageTagPush(ctx context.Context, localRef, registryRef string) error {
	if err := r.cli.ImageTag(ctx, localRef, registryRef); err != nil {
		return err
	}
	rc, err := r.cli.ImagePush(ctx, registryRef, image.PushOptions{})
	if err != nil {
		return err
	}
	defer rc.Close()
	return drainPushStream(rc)
}

// drainPushStream reads a Docker push JSON-message stream to completion and
// surfaces an error if any message reports a failure (auth, quota, disk) —
// the push body is JSON lines, and a failed push still returns a 200 with an
// "error"/"errorDetail" line rather than a non-2xx HTTP status, so draining
// without inspecting the stream (the old behavior) silently swallowed it.
func drainPushStream(rc io.Reader) error {
	return jsonmessage.DisplayJSONMessagesStream(rc, io.Discard, 0, false, nil)
}

// buildSpec maps the narrow ServiceSpec to the full Docker swarm.ServiceSpec,
// applying the fixed §3.2 rollout/restart/publish policy.
func buildSpec(s ServiceSpec) swarm.ServiceSpec {
	labels := map[string]string{
		labelManaged:  "true",
		labelApp:      s.App,
		labelProcess:  s.Process,
		labelDeploy:   s.DeployID,
		labelSpecHash: s.SpecHash(),
	}

	if s.Job {
		labels = map[string]string{labelRun: "true", labelApp: s.App}
		one := uint64(1)
		return swarm.ServiceSpec{
			Annotations: swarm.Annotations{Name: s.Name, Labels: labels},
			TaskTemplate: swarm.TaskSpec{
				ContainerSpec: &swarm.ContainerSpec{
					Image:   s.Image,
					Command: s.Command,
					Env:     envSlice(s.Env),
					Labels:  labels,
				},
				// Condition none, explicitly: Swarm's default restart policy
				// would re-run a failed task — a failed migration must never
				// auto-retry (spec §7.1).
				RestartPolicy: &swarm.RestartPolicy{Condition: swarm.RestartPolicyConditionNone},
				Networks:      networkAttachments(s.Networks),
				Resources:     resourceReqs(s),
			},
			Mode: swarm.ServiceMode{ReplicatedJob: &swarm.ReplicatedJob{
				MaxConcurrent:    &one,
				TotalCompletions: &one,
			}},
		}
	}

	replicas := uint64(s.Replicas)
	monitor := updateMonitor
	window := restartWindow
	maxAttempts := restartMax

	spec := swarm.ServiceSpec{
		Annotations: swarm.Annotations{Name: s.Name, Labels: labels},
		TaskTemplate: swarm.TaskSpec{
			ContainerSpec: &swarm.ContainerSpec{
				Image:   s.Image,
				Command: s.Command, // exec array; nil falls back to image CMD
				Env:     envSlice(s.Env),
				Labels:  labels,
			},
			RestartPolicy: &swarm.RestartPolicy{
				Condition:   swarm.RestartPolicyConditionOnFailure,
				MaxAttempts: &maxAttempts,
				Window:      &window,
			},
			Networks: networkAttachments(s.Networks),
		},
		Mode: swarm.ServiceMode{Replicated: &swarm.ReplicatedService{Replicas: &replicas}},
		UpdateConfig: &swarm.UpdateConfig{
			Parallelism:   1,
			Monitor:       monitor,
			Order:         swarm.UpdateOrderStartFirst,
			FailureAction: swarm.UpdateFailureActionRollback,
		},
		// RollbackConfig mirrors UpdateConfig so a failed rollout reverts the
		// same way it rolled out.
		RollbackConfig: &swarm.UpdateConfig{
			Parallelism: 1,
			Monitor:     monitor,
			Order:       swarm.UpdateOrderStartFirst,
		},
	}

	if len(s.Mounts) > 0 {
		ms := make([]mount.Mount, 0, len(s.Mounts))
		for _, m := range s.Mounts {
			ms = append(ms, mount.Mount{
				Type:   mount.TypeVolume,
				Source: m.Volume,
				Target: m.Path,
			})
		}
		spec.TaskTemplate.ContainerSpec.Mounts = ms
	}
	if hc := s.Healthcheck; hc != nil {
		spec.TaskTemplate.ContainerSpec.Healthcheck = &container.HealthConfig{
			Test:        hc.Test,
			Interval:    time.Duration(hc.IntervalSec) * time.Second,
			Timeout:     time.Duration(hc.TimeoutSec) * time.Second,
			Retries:     hc.Retries,
			StartPeriod: time.Duration(hc.StartPeriodSec) * time.Second,
		}
	}
	if res := resourceReqs(s); res != nil {
		spec.TaskTemplate.Resources = res
	}
	if s.PublishedPort != 0 {
		spec.EndpointSpec = &swarm.EndpointSpec{
			Mode: swarm.ResolutionModeVIP,
			Ports: []swarm.PortConfig{{
				Protocol:      swarm.PortConfigProtocolTCP,
				TargetPort:    uint32(s.TargetPort),
				PublishedPort: uint32(s.PublishedPort),
				PublishMode:   swarm.PortConfigPublishModeIngress,
			}},
		}
	}
	return spec
}

func envSlice(env map[string]string) []string {
	if len(env) == 0 {
		return nil
	}
	out := make([]string, 0, len(env))
	for k, v := range env {
		out = append(out, k+"="+v)
	}
	return out
}

func networkAttachments(names []string) []swarm.NetworkAttachmentConfig {
	if len(names) == 0 {
		return nil
	}
	out := make([]swarm.NetworkAttachmentConfig, 0, len(names))
	for _, n := range names {
		out = append(out, swarm.NetworkAttachmentConfig{Target: n})
	}
	return out
}

func resourceReqs(s ServiceSpec) *swarm.ResourceRequirements {
	if s.MemoryMB == 0 && s.CPU == 0 {
		return nil
	}
	lim := &swarm.Limit{}
	if s.MemoryMB != 0 {
		lim.MemoryBytes = int64(s.MemoryMB) * 1024 * 1024
	}
	if s.CPU != 0 {
		lim.NanoCPUs = int64(s.CPU * 1e9)
	}
	return &swarm.ResourceRequirements{Limits: lim}
}

func (r *realSwarmAPI) JobTasks(ctx context.Context, serviceName string) ([]JobTask, error) {
	f := filters.NewArgs()
	f.Add("service", serviceName)
	tasks, err := r.cli.TaskList(ctx, swarm.TaskListOptions{Filters: f})
	if err != nil {
		return nil, err
	}
	out := make([]JobTask, 0, len(tasks))
	for _, t := range tasks {
		jt := JobTask{State: string(t.Status.State), Message: t.Status.Err}
		if t.Status.ContainerStatus != nil {
			jt.ExitCode = t.Status.ContainerStatus.ExitCode
		}
		out = append(out, jt)
	}
	return out, nil
}

func (r *realSwarmAPI) ServiceLogs(ctx context.Context, serviceName string) (string, error) {
	rc, err := r.cli.ServiceLogs(ctx, serviceName, container.LogsOptions{
		ShowStdout: true, ShowStderr: true, Tail: "500",
	})
	if err != nil {
		return "", err
	}
	defer rc.Close()
	var buf bytes.Buffer
	// Non-TTY service logs are multiplexed frames; demux both streams into
	// one buffer in arrival order.
	if _, err := stdcopy.StdCopy(&buf, &buf, rc); err != nil {
		return buf.String(), err
	}
	return buf.String(), nil
}
