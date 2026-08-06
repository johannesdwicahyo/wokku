package lifecycle

import (
	"context"
	"errors"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// fakeSwarm records the write-call sequence so tests assert on exactly what
// the engine did (and, via idempotency, what it didn't).
type fakeSwarm struct {
	live          []ServiceInfo
	calls         []string // "create:<name>", "update:<name>:force=<bool>", "remove:<name>", "net:<name>"
	jobTasks      map[string][]JobTask
	logs          map[string]string
	specs         map[string]ServiceSpec // ServiceCreate specs recorded by name, for run.go tests
	jobTasksErr   error                  // If set, JobTasks returns this error instead
	jobTasksHook  func()                 // If set, called in JobTasks before returning (before jobTasksErr check)
}

// newFakeSwarm is the fake's constructor (run_test.go's preferred entry point
// alongside the &fakeSwarm{} literal used throughout this file).
func newFakeSwarm() *fakeSwarm { return &fakeSwarm{} }

// createdSpec returns the ServiceSpec passed to ServiceCreate for the given
// service name (run_test.go asserts against the recorded Job spec).
func (f *fakeSwarm) createdSpec(name string) ServiceSpec { return f.specs[name] }

func (f *fakeSwarm) ServiceList(ctx context.Context, appLabel string) ([]ServiceInfo, error) {
	var out []ServiceInfo
	for _, s := range f.live {
		if s.App == appLabel {
			out = append(out, s)
		}
	}
	return out, nil
}

func (f *fakeSwarm) ServiceCreate(ctx context.Context, spec ServiceSpec) error {
	f.calls = append(f.calls, "create:"+spec.Name)
	if f.specs == nil {
		f.specs = make(map[string]ServiceSpec)
	}
	f.specs[spec.Name] = spec
	return nil
}

func (f *fakeSwarm) ServiceUpdate(ctx context.Context, name string, spec ServiceSpec, forceRestart bool) error {
	if forceRestart {
		f.calls = append(f.calls, "update:"+name+":force=true")
	} else {
		f.calls = append(f.calls, "update:"+name+":force=false")
	}
	return nil
}

func (f *fakeSwarm) ServiceRemove(ctx context.Context, name string) error {
	f.calls = append(f.calls, "remove:"+name)
	return nil
}

func (f *fakeSwarm) TaskList(ctx context.Context) ([]TaskInfo, error) { return nil, nil }

func (f *fakeSwarm) NetworkEnsureOverlay(ctx context.Context, name string) error {
	f.calls = append(f.calls, "net:"+name)
	return nil
}

func (f *fakeSwarm) ImageTagPush(ctx context.Context, localRef, registryRef string) error {
	f.calls = append(f.calls, "tagpush:"+registryRef)
	return nil
}

func (f *fakeSwarm) JobTasks(ctx context.Context, name string) ([]JobTask, error) {
	f.calls = append(f.calls, "JobTasks("+name+")")
	if f.jobTasksHook != nil {
		f.jobTasksHook()
	}
	if f.jobTasksErr != nil {
		return nil, f.jobTasksErr
	}
	return f.jobTasks[name], nil
}

func (f *fakeSwarm) ServiceLogs(ctx context.Context, name string) (string, error) {
	f.calls = append(f.calls, "ServiceLogs("+name+")")
	return f.logs[name], nil
}

// writes returns the call sequence with network-ensure noise filtered out —
// tests that care about writes-vs-no-writes assert on service ops only.
func (f *fakeSwarm) writes() []string {
	var out []string
	for _, c := range f.calls {
		if len(c) >= 4 && c[:4] == "net:" {
			continue
		}
		out = append(out, c)
	}
	return out
}

func baseParams() ConvergeParams {
	return ConvergeParams{
		App:      "blog",
		DeployID: "d1",
		ImageRef: "127.0.0.1:5000/wokku/blog:d1",
		Formation: map[string]int{
			"web":    1,
			"worker": 1,
		},
		FormationCommands: map[string]string{
			"web":    "bundle exec puma",
			"worker": "bundle exec sidekiq",
		},
		Env:           map[string]string{"RACK_ENV": "production"},
		Resources:     map[string]ProcResources{"web": {MemoryMB: 512, CPUShares: 0.5}},
		PublishedPort: 20001,
		ContainerPort: 5000,
		Networks:      []string{"wokku-services"},
	}
}

// liveFrom builds the live services that an identical prior converge would
// have produced, so "no change" tests start from a matching baseline.
func liveFrom(p ConvergeParams) []ServiceInfo {
	var out []ServiceInfo
	for proc, count := range p.Formation {
		out = append(out, ServiceInfo{
			Name:     ServiceName(p.App, proc),
			App:      p.App,
			Process:  proc,
			DeployID: p.DeployID,
			Image:    p.ImageRef,
			Replicas: count,
		})
	}
	return out
}

func TestConvergeEmptyStateCreatesPerProcess(t *testing.T) {
	f := &fakeSwarm{}
	p := baseParams()
	res, err := Converge(context.Background(), f, p)
	if err != nil {
		t.Fatal(err)
	}
	got := append([]string(nil), f.writes()...)
	sort.Strings(got)
	want := []string{"create:wokku-blog-web", "create:wokku-blog-worker"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("writes = %v, want %v", got, want)
	}
	if len(res.Created) != 2 {
		t.Fatalf("result.Created = %v, want 2 entries", res.Created)
	}
	// overlay network ensured before creating.
	if len(f.calls) == 0 || f.calls[0] != "net:wokku-services" {
		t.Fatalf("expected network ensure first, calls=%v", f.calls)
	}
}

func TestConvergeWebPublishesWorkerDoesNot(t *testing.T) {
	f := &fakeSwarm{}
	p := baseParams()
	// capture specs via a spy create
	var specs []ServiceSpec
	spy := &specSpy{fakeSwarm: f, out: &specs}
	if _, err := Converge(context.Background(), spy, p); err != nil {
		t.Fatal(err)
	}
	for _, s := range specs {
		switch s.Process {
		case "web":
			if s.PublishedPort != 20001 || s.TargetPort != 5000 {
				t.Fatalf("web must publish, got %+v", s)
			}
		case "worker":
			if s.PublishedPort != 0 || s.TargetPort != 0 {
				t.Fatalf("worker must not publish, got %+v", s)
			}
			if len(s.Command) != 3 { // bundle exec sidekiq
				t.Fatalf("worker command not split: %v", s.Command)
			}
		}
	}
}

func TestConvergeIdenticalStateIsZeroWrites(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	res, err := Converge(context.Background(), f, p)
	if err != nil {
		t.Fatal(err)
	}
	if w := f.writes(); len(w) != 0 {
		t.Fatalf("idempotent converge must not write, got %v", w)
	}
	if len(res.Created)+len(res.Updated)+len(res.Removed) != 0 {
		t.Fatalf("result should be empty, got %+v", res)
	}
}

func TestConvergeImageChangeUpdates(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	p.DeployID = "d2"
	p.ImageRef = "127.0.0.1:5000/wokku/blog:d2"
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	got := append([]string(nil), f.writes()...)
	sort.Strings(got)
	want := []string{"update:wokku-blog-web:force=false", "update:wokku-blog-worker:force=false"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("writes = %v, want %v", got, want)
	}
}

func TestConvergeCountChangeUpdatesReplicas(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	p.Formation["worker"] = 3 // scale worker only
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if got := f.writes(); !reflect.DeepEqual(got, []string{"update:wokku-blog-worker:force=false"}) {
		t.Fatalf("only worker should update, got %v", got)
	}
}

func TestConvergeRemovedProcessRemovesService(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	delete(p.Formation, "worker")
	delete(p.FormationCommands, "worker")
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if got := f.writes(); !reflect.DeepEqual(got, []string{"remove:wokku-blog-worker"}) {
		t.Fatalf("worker should be removed, got %v", got)
	}
}

func TestConvergeRestartForcesUpdate(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	p.Restart = true // nothing else changed
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	got := append([]string(nil), f.writes()...)
	sort.Strings(got)
	want := []string{"update:wokku-blog-web:force=true", "update:wokku-blog-worker:force=true"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("restart must force-update all, got %v", got)
	}
}

func TestConvergeEmptyFormationGuard(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	// desired formation omits web entirely while live web runs.
	delete(p.Formation, "web")
	delete(p.FormationCommands, "web")
	_, err := Converge(context.Background(), f, p)
	if !errors.Is(err, ErrFormationWouldEmpty) {
		t.Fatalf("want ErrFormationWouldEmpty, got %v", err)
	}
	if w := f.writes(); len(w) != 0 {
		t.Fatalf("guard must write nothing, got %v", w)
	}
}

func TestConvergeWebScaleToZeroIsAllowed(t *testing.T) {
	// stop/sleep sets web:0 (key present) — that is a scale, not a removal,
	// and must NOT trip the guard.
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	p.Formation["web"] = 0
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatalf("web:0 must be allowed, got %v", err)
	}
	if got := f.writes(); !reflect.DeepEqual(got, []string{"update:wokku-blog-web:force=false"}) {
		t.Fatalf("web should scale to 0 via update, got %v", got)
	}
}

func TestRemoveDeletesAllServices(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	if err := Remove(context.Background(), f, "blog"); err != nil {
		t.Fatal(err)
	}
	got := append([]string(nil), f.writes()...)
	sort.Strings(got)
	want := []string{"remove:wokku-blog-web", "remove:wokku-blog-worker"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("remove all, got %v", got)
	}
}

func TestConvergeTagFromLocalPushesBeforeServiceWrites(t *testing.T) {
	f := &fakeSwarm{}
	p := baseParams()
	p.TagFromLocal = true
	p.LocalRef = "dokku/blog:latest"
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) == 0 || f.calls[0] != "tagpush:"+p.ImageRef {
		t.Fatalf("expected tag-push before any service write, calls=%v", f.calls)
	}
}

func TestConvergeTagFromLocalFalseSkipsPush(t *testing.T) {
	f := &fakeSwarm{}
	p := baseParams()
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "tagpush:") {
			t.Fatalf("tag_from_local=false must not push, calls=%v", f.calls)
		}
	}
}

// specSpy wraps fakeSwarm to capture the specs passed to ServiceCreate.
type specSpy struct {
	*fakeSwarm
	out *[]ServiceSpec
}

func (s *specSpy) ServiceCreate(ctx context.Context, spec ServiceSpec) error {
	*s.out = append(*s.out, spec)
	return s.fakeSwarm.ServiceCreate(ctx, spec)
}

func TestFakeJobTasksAndServiceLogs(t *testing.T) {
	f := &fakeSwarm{}
	f.jobTasks = map[string][]JobTask{"wokku-run-a-x": {{State: "complete", ExitCode: 0}}}
	f.logs = map[string]string{"wokku-run-a-x": "migrated\n"}
	tasks, err := f.JobTasks(context.Background(), "wokku-run-a-x")
	if err != nil || len(tasks) != 1 || tasks[0].State != "complete" {
		t.Fatalf("JobTasks: %v %v", tasks, err)
	}
	out, err := f.ServiceLogs(context.Background(), "wokku-run-a-x")
	if err != nil || out != "migrated\n" {
		t.Fatalf("ServiceLogs: %q %v", out, err)
	}
}

// --- spec-hash change detection (B6 agent batch) ---

func liveFromHashed(p ConvergeParams) []ServiceInfo {
	out := liveFrom(p)
	desired := p.serviceParams()
	for i := range out {
		out[i].SpecHash = p.specFor(out[i].Process, desired[out[i].Process]).SpecHash()
	}
	return out
}

func TestConvergeHashedIdenticalStateIsZeroWrites(t *testing.T) {
	p := baseParams()
	f := &fakeSwarm{live: liveFromHashed(p)}
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if w := f.writes(); len(w) != 0 {
		t.Fatalf("hashed idempotent converge must not write, got %v", w)
	}
}

func TestConvergeEnvOnlyChangeUpdatesWhenHashed(t *testing.T) {
	// The legacy image/replicas/deploy triple missed env/command-only changes
	// — config:set on a flagged app silently never applied.
	p := baseParams()
	f := &fakeSwarm{live: liveFromHashed(p)}
	p.Env = map[string]string{"NEW_VAR": "set-after-adopt"}
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if len(f.writes()) == 0 {
		t.Fatal("env-only change must update hashed services, got zero writes")
	}
}

func TestConvergeEnvOnlyChangeIgnoredWithoutHash(t *testing.T) {
	// Pre-hash services (no label) keep the legacy triple until their next
	// real update — pinned so the fallback never regresses into a rotate
	// storm on agent upgrade.
	p := baseParams()
	f := &fakeSwarm{live: liveFrom(p)}
	p.Env = map[string]string{"NEW_VAR": "x"}
	if _, err := Converge(context.Background(), f, p); err != nil {
		t.Fatal(err)
	}
	if w := f.writes(); len(w) != 0 {
		t.Fatalf("unhashed services must keep legacy detection, got %v", w)
	}
}

func TestSpecHashDeterministic(t *testing.T) {
	a := ServiceSpec{Name: "n", Env: map[string]string{"A": "1", "B": "2"}, Command: []string{"run"}}
	b := ServiceSpec{Name: "n", Env: map[string]string{"B": "2", "A": "1"}, Command: []string{"run"}}
	if a.SpecHash() != b.SpecHash() {
		t.Fatal("hash must be independent of env map insertion order")
	}
	b.Env["A"] = "changed"
	if a.SpecHash() == b.SpecHash() {
		t.Fatal("env value change must change the hash")
	}
}

// baselineSpec is a fully-populated pre-B5b ServiceSpec. Its hash is pinned so
// that adding fields for mounts/healthchecks cannot silently change the hash of
// every existing service — which would rotate all adopted apps at once on the
// first converge after an agent upgrade.
func baselineSpec() ServiceSpec {
	return ServiceSpec{
		Name: "wokku-demo-web", App: "demo", Process: "web",
		DeployID: "dep123", Image: "reg/wokku/demo:dep123",
		Command:  []string{"/bin/bash", "-l", "-c", "exec node bin/www"},
		Env:      map[string]string{"PORT": "5000", "RAILS_ENV": "production"},
		Replicas: 1, MemoryMB: 512, CPU: 0.5,
		Networks:      []string{"wokku-services"},
		PublishedPort: 20001, TargetPort: 5000,
	}
}

func TestSpecHashStableAcrossB5bFields(t *testing.T) {
	const preB5b = "fce2ae4548707d5cab2257a4c7b485f5b00c980a1b8e30cb6a80975ef2aebb38"
	if got := baselineSpec().SpecHash(); got != preB5b {
		t.Fatalf("spec hash changed for a service with no mounts/healthcheck:\n got %s\nwant %s\nthis rotates every adopted app on upgrade", got, preB5b)
	}
}

func TestSpecHashChangesWhenMountsAdded(t *testing.T) {
	s := baselineSpec()
	s.Mounts = []Mount{{Volume: "wokku-demo-data", Path: "/data"}}
	if s.SpecHash() == baselineSpec().SpecHash() {
		t.Fatal("adding a mount must change the spec hash, else the change never applies")
	}
}

// Legacy params must normalize to exactly the specs the pre-B5b engine built,
// because every op already in lifecycle_ops is the old shape.
func TestServiceParamsFromLegacyShape(t *testing.T) {
	p := ConvergeParams{
		App: "demo", DeployID: "d1", ImageRef: "img:1",
		Formation:         map[string]int{"web": 2, "worker": 1},
		FormationCommands: map[string]string{"worker": "bundle exec sidekiq"},
		Env:               map[string]string{"PORT": "5000"},
		Resources:         map[string]ProcResources{"web": {MemoryMB: 512, CPUShares: 0.5}},
		PublishedPort:     20001,
		ContainerPort:     5000,
	}
	got := p.serviceParams()

	if len(got) != 2 {
		t.Fatalf("want 2 services, got %d", len(got))
	}
	web := got["web"]
	if web.Image != "img:1" || web.Replicas != 2 || !web.Public || web.TargetPort != 5000 {
		t.Fatalf("web normalized wrong: %+v", web)
	}
	if web.MemoryMB != 512 || web.CPU != 0.5 {
		t.Fatalf("web resources lost: %+v", web)
	}
	worker := got["worker"]
	if worker.Public {
		t.Fatal("only the web process is public in the legacy shape")
	}
	if worker.Command != "bundle exec sidekiq" || worker.Image != "img:1" {
		t.Fatalf("worker normalized wrong: %+v", worker)
	}
}

// TestConvergeServicesPayloadCreatesEachEntry exercises Converge itself (not
// serviceParams in isolation) with a Services payload — the shape the control
// plane is about to emit on every converge, making this the live production
// path rather than an edge case.
func TestConvergeServicesPayloadCreatesEachEntry(t *testing.T) {
	f := &fakeSwarm{}
	var specs []ServiceSpec
	spy := &specSpy{fakeSwarm: f, out: &specs}
	p := ConvergeParams{
		App:           "demo",
		DeployID:      "d1",
		PublishedPort: 20001,
		Networks:      []string{"wokku-services"},
		Services: map[string]ServiceParams{
			"web": {
				Image: "web:1", Replicas: 1, Public: true, TargetPort: 3000,
				Mounts:      []Mount{{Volume: "wokku-demo-data", Path: "/data"}},
				Healthcheck: &Healthcheck{Test: []string{"CMD-SHELL", "curl -f localhost:3000"}, IntervalSec: 5},
			},
			"worker": {Image: "worker:1", Replicas: 2},
		},
	}
	res, err := Converge(context.Background(), spy, p)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Created) != 2 {
		t.Fatalf("want 2 created, got %v", res.Created)
	}

	byProc := make(map[string]ServiceSpec, len(specs))
	for _, s := range specs {
		byProc[s.Process] = s
	}

	web := byProc["web"]
	if web.Image != "web:1" {
		t.Fatalf("web image = %q, want web:1", web.Image)
	}
	if web.PublishedPort != 20001 || web.TargetPort != 3000 {
		t.Fatalf("public service must publish, got %+v", web)
	}
	if len(web.Mounts) != 1 || web.Mounts[0].Volume != "wokku-demo-data" {
		t.Fatalf("web mounts not carried through: %+v", web.Mounts)
	}
	if web.Healthcheck == nil || web.Healthcheck.IntervalSec != 5 {
		t.Fatalf("web healthcheck not carried through: %+v", web.Healthcheck)
	}

	worker := byProc["worker"]
	if worker.Image != "worker:1" {
		t.Fatalf("worker image = %q, want worker:1", worker.Image)
	}
	if worker.PublishedPort != 0 || worker.TargetPort != 0 {
		t.Fatalf("non-public service must not publish, got %+v", worker)
	}
}

// The new shape wins outright, and carries a per-service image.
func TestServiceParamsPrefersServicesShape(t *testing.T) {
	p := ConvergeParams{
		App: "demo", ImageRef: "legacy:1",
		Formation: map[string]int{"web": 9},
		Services: map[string]ServiceParams{
			"web": {Image: "web:1", Replicas: 1, Public: true, TargetPort: 3000},
			"api": {Image: "api:1", Replicas: 2},
		},
	}
	got := p.serviceParams()
	if len(got) != 2 || got["web"].Image != "web:1" || got["api"].Image != "api:1" {
		t.Fatalf("services shape not preferred: %+v", got)
	}
	if got["web"].Replicas != 1 {
		t.Fatal("legacy formation must be ignored when services is present")
	}
}
