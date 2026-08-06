package lifecycle

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/swarm"
)

// drainPushStream backs realSwarmAPI.ImageTagPush — this is the regression
// test for the Task 6 review finding: the old code drained the push body and
// returned nil even when the JSON stream reported a failure (auth, quota,
// disk). Docker's push body is JSON lines; a failure line carries an
// "errorDetail"/"error" field instead of "status".
func TestDrainPushStreamReturnsErrorOnErrorMessage(t *testing.T) {
	stream := `{"status":"Pushing"}
{"errorDetail":{"message":"denied: requested access to the resource is denied"},"error":"denied: requested access to the resource is denied"}
`
	err := drainPushStream(strings.NewReader(stream))
	if err == nil {
		t.Fatal("expected error from a push stream carrying errorDetail, got nil")
	}
	if !strings.Contains(err.Error(), "denied") {
		t.Fatalf("expected the docker error message surfaced, got %q", err.Error())
	}
}

func TestDrainPushStreamOKOnSuccess(t *testing.T) {
	stream := `{"status":"Pushing"}
{"status":"Pushed"}
`
	if err := drainPushStream(strings.NewReader(stream)); err != nil {
		t.Fatalf("expected nil error for a clean push stream, got %v", err)
	}
}

// I7: TaskList must drop shutdown-desired terminal history so live_containers
// isn't inflated with dead tasks from the task-history retention.
func TestLiveTask(t *testing.T) {
	cases := []struct {
		desired, state string
		want           bool
	}{
		{"running", "running", true},    // the live task
		{"running", "starting", true},   // coming up
		{"running", "preparing", true},  // desired running wins even mid-prep
		{"shutdown", "running", true},   // draining but still up — still serving
		{"shutdown", "shutdown", false}, // terminal history
		{"shutdown", "complete", false}, // terminal history
		{"shutdown", "failed", false},   // terminal history
		{"", "pending", true},           // brand-new task being scheduled
		{"shutdown", "rejected", false}, // terminal history
	}
	for _, c := range cases {
		if got := liveTask(c.desired, c.state); got != c.want {
			t.Errorf("liveTask(%q,%q)=%v want %v", c.desired, c.state, got, c.want)
		}
	}
}

// taskInfo backs realSwarmAPI.TaskList — regression test for the first-rung
// prod finding: Swarm tasks carry EMPTY task-level labels (the wokku.* set
// lives on Spec.ContainerSpec.Labels), so both the API-side label filter and
// reading t.Labels returned nothing — heartbeats never carried task state.
func TestTaskInfoReadsContainerSpecLabels(t *testing.T) {
	task := swarmTask("hermes-smoke", "web", "running", "running")
	task.Labels = nil // prod reality: task-level labels are empty

	info, ok := taskInfo(task)
	if !ok {
		t.Fatal("expected managed live task to be kept")
	}
	if info.App != "hermes-smoke" || info.Process != "web" {
		t.Fatalf("App/Process must come from ContainerSpec labels, got %q/%q", info.App, info.Process)
	}
	if info.ServiceName != "wokku-hermes-smoke-web" {
		t.Fatalf("ServiceName = %q", info.ServiceName)
	}
}

func TestTaskInfoDropsUnmanagedTasks(t *testing.T) {
	task := swarmTask("someone-elses", "web", "running", "running")
	task.Spec.ContainerSpec.Labels = map[string]string{"other": "label"}

	if _, ok := taskInfo(task); ok {
		t.Fatal("task without wokku.managed=true must be dropped")
	}
}

func TestTaskInfoDropsTerminalHistory(t *testing.T) {
	task := swarmTask("hermes-smoke", "web", "shutdown", "shutdown")

	if _, ok := taskInfo(task); ok {
		t.Fatal("terminal-history task must be dropped")
	}
}

func swarmTask(app, proc, desired, state string) swarm.Task {
	task := swarm.Task{DesiredState: swarm.TaskState(desired)}
	task.Status.State = swarm.TaskState(state)
	task.Spec.ContainerSpec = &swarm.ContainerSpec{Labels: map[string]string{
		labelManaged: "true", labelApp: app, labelProcess: proc,
	}}
	return task
}

func TestBuildSpecMountsAndHealthcheck(t *testing.T) {
	s := ServiceSpec{
		Name: "wokku-demo-web", App: "demo", Process: "web", Image: "img",
		Replicas: 1,
		Mounts:   []Mount{{Volume: "wokku-demo-data", Path: "/data"}},
		Healthcheck: &Healthcheck{
			Test:        []string{"CMD-SHELL", "curl -f localhost:3000 || exit 1"},
			IntervalSec: 10, TimeoutSec: 3, Retries: 3, StartPeriodSec: 60,
		},
	}
	got := buildSpec(s)

	ms := got.TaskTemplate.ContainerSpec.Mounts
	if len(ms) != 1 || ms[0].Source != "wokku-demo-data" || ms[0].Target != "/data" {
		t.Fatalf("mount not translated: %+v", ms)
	}
	if ms[0].Type != mount.TypeVolume {
		t.Fatalf("want a named volume, got type %q", ms[0].Type)
	}

	hc := got.TaskTemplate.ContainerSpec.Healthcheck
	if hc == nil {
		t.Fatal("healthcheck not translated")
	}
	if hc.Interval != 10*time.Second || hc.StartPeriod != 60*time.Second || hc.Retries != 3 {
		t.Fatalf("healthcheck fields wrong: %+v", hc)
	}
}

func TestBuildSpecOmitsEmptyMountsAndHealthcheck(t *testing.T) {
	got := buildSpec(ServiceSpec{Name: "n", App: "a", Process: "web", Image: "img", Replicas: 1})
	if got.TaskTemplate.ContainerSpec.Mounts != nil {
		t.Fatal("no mounts declared, so none should be set")
	}
	if got.TaskTemplate.ContainerSpec.Healthcheck != nil {
		t.Fatal("no healthcheck declared, so the image's own must be left alone")
	}
}

func TestBuildSpecJob(t *testing.T) {
	s := ServiceSpec{
		Name: "wokku-run-myapp-abcd1234", App: "myapp", Process: "run",
		Image: "img:1", Command: []string{"rails", "db:migrate"},
		Env: map[string]string{"A": "1"}, Replicas: 1, Networks: []string{"wokku-services"},
		Job: true,
	}
	spec := buildSpec(s)
	if spec.Mode.ReplicatedJob == nil || spec.Mode.Replicated != nil {
		t.Fatal("job spec must use ReplicatedJob mode")
	}
	if mc := spec.Mode.ReplicatedJob.MaxConcurrent; mc == nil || *mc != 1 {
		t.Fatal("MaxConcurrent must be 1")
	}
	if tc := spec.Mode.ReplicatedJob.TotalCompletions; tc == nil || *tc != 1 {
		t.Fatal("TotalCompletions must be 1")
	}
	rp := spec.TaskTemplate.RestartPolicy
	if rp == nil || rp.Condition != swarm.RestartPolicyConditionNone {
		t.Fatal("job restart policy must be none — a failed migration must never auto-retry")
	}
	if spec.UpdateConfig != nil || spec.RollbackConfig != nil {
		t.Fatal("job spec must not carry update/rollback config")
	}
	if spec.EndpointSpec != nil {
		t.Fatal("job must never publish a port")
	}
	labels := spec.Annotations.Labels
	if labels[labelRun] != "true" || labels[labelApp] != "myapp" {
		t.Fatalf("job labels wrong: %v", labels)
	}
	if _, has := labels[labelManaged]; has {
		t.Fatal("job must NOT be wokku.managed — converge/heartbeat must ignore it")
	}
	if cs := spec.TaskTemplate.ContainerSpec; cs.Labels[labelRun] != "true" || cs.Labels[labelManaged] != "" {
		t.Fatalf("container labels wrong: %v", cs.Labels)
	}
}

// Job=false must marshal byte-identically to a pre-Job ServiceSpec — the
// marshal IS the spec hash; a changed hash rotates every live service.
func TestSpecHashStableAcrossJobField(t *testing.T) {
	s := ServiceSpec{Name: "wokku-a-web", App: "a", Process: "web", Image: "i", Replicas: 1}
	b, _ := json.Marshal(s)
	if strings.Contains(string(b), "job") {
		t.Fatalf("Job=false must be omitted from marshal, got %s", b)
	}
}
