package services

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeDocker is the test double for dockerAPI: records every call in call
// order (same style as postgres_test.go's fakeExecer) and returns canned
// errors/exec outputs.
type fakeDocker struct {
	calls []string

	inspect    ContainerInfo
	inspectErr error

	execOut []string
	execErr []error
	execI   int

	// streaming exec (service.export/import) fixtures
	streamStdin bytes.Buffer
	streamOut   []byte
	streamErr   error

	existing map[string]bool

	failOn map[string]error
}

func (f *fakeDocker) fail(method string) error {
	if f.failOn == nil {
		return nil
	}
	return f.failOn[method]
}

func (f *fakeDocker) ImageEnsure(ctx context.Context, ref string) error {
	f.calls = append(f.calls, fmt.Sprintf("ImageEnsure(%s)", ref))
	return f.fail("ImageEnsure")
}

func (f *fakeDocker) VolumeCreate(ctx context.Context, hostPath string) error {
	f.calls = append(f.calls, fmt.Sprintf("VolumeCreate(%s)", hostPath))
	return f.fail("VolumeCreate")
}

func (f *fakeDocker) ContainerCreate(ctx context.Context, spec ContainerSpec) error {
	f.calls = append(f.calls, fmt.Sprintf("ContainerCreate(name=%s image=%s env=%v bind=%s cmd=%v)", spec.Name, spec.Image, spec.Env, spec.Bind, spec.Cmd))
	return f.fail("ContainerCreate")
}

func (f *fakeDocker) ContainerInspect(ctx context.Context, name string) (ContainerInfo, error) {
	f.calls = append(f.calls, fmt.Sprintf("ContainerInspect(%s)", name))
	return f.inspect, f.inspectErr
}

func (f *fakeDocker) ContainerStart(ctx context.Context, name string) error {
	f.calls = append(f.calls, fmt.Sprintf("ContainerStart(%s)", name))
	return f.fail("ContainerStart")
}

func (f *fakeDocker) ContainerStop(ctx context.Context, name string) error {
	f.calls = append(f.calls, fmt.Sprintf("ContainerStop(%s)", name))
	return f.fail("ContainerStop")
}

func (f *fakeDocker) ContainerRestart(ctx context.Context, name string) error {
	f.calls = append(f.calls, fmt.Sprintf("ContainerRestart(%s)", name))
	return f.fail("ContainerRestart")
}

func (f *fakeDocker) ContainerRemove(ctx context.Context, name string) error {
	f.calls = append(f.calls, fmt.Sprintf("ContainerRemove(%s)", name))
	return f.fail("ContainerRemove")
}

func (f *fakeDocker) ContainerUpdate(ctx context.Context, name string, memoryMB int, cpu float64) error {
	if cpu > 0 {
		f.calls = append(f.calls, fmt.Sprintf("ContainerUpdate(%s,%d,cpu=%g)", name, memoryMB, cpu))
	} else {
		f.calls = append(f.calls, fmt.Sprintf("ContainerUpdate(%s,%d)", name, memoryMB))
	}
	return f.fail("ContainerUpdate")
}

func (f *fakeDocker) ContainerExists(ctx context.Context, name string) (bool, error) {
	if err := f.fail("ContainerExists"); err != nil {
		return false, err
	}
	f.calls = append(f.calls, fmt.Sprintf("ContainerExists(%s)", name))
	return f.existing[name], nil
}

func (f *fakeDocker) NetworkConnect(ctx context.Context, networkName, name string, aliases ...string) error {
	if err := f.fail("NetworkConnect"); err != nil {
		return err
	}
	f.calls = append(f.calls, fmt.Sprintf("NetworkConnect(%s,%s,aliases=%s)", networkName, name, strings.Join(aliases, ",")))
	return nil
}

func (f *fakeDocker) NetworkEnsure(ctx context.Context, name string) error {
	f.calls = append(f.calls, fmt.Sprintf("NetworkEnsure(%s)", name))
	return f.fail("NetworkEnsure")
}

func (f *fakeDocker) Exec(ctx context.Context, container, stdin string, cmd ...string) (string, error) {
	f.calls = append(f.calls, fmt.Sprintf("Exec(%s,%v)", container, cmd))
	i := f.execI
	f.execI++
	var out string
	if i < len(f.execOut) {
		out = f.execOut[i]
	}
	var err error
	if i < len(f.execErr) {
		err = f.execErr[i]
	}
	return out, err
}

func (f *fakeDocker) ExecStream(ctx context.Context, container string, stdin io.Reader, stdout io.Writer, cmd ...string) error {
	f.calls = append(f.calls, fmt.Sprintf("ExecStream(%s,%v)", container, cmd))
	if stdin != nil {
		if _, err := io.Copy(&f.streamStdin, stdin); err != nil {
			return err
		}
	}
	if len(f.streamOut) > 0 {
		if _, err := stdout.Write(f.streamOut); err != nil {
			return err
		}
	}
	return f.streamErr
}

// --- service.create ---

// A fresh redis must boot WITH auth: the official image has no password env,
// so serviceCreate writes requirepass into a conf INSIDE the data dir (auth
// travels with the data — ensure recreates carry no credentials) and overrides
// the image CMD to load it. Chatwoot's AUTH failed against a passwordless
// fresh redis on 2026-07-22; this pins the fix.
func TestServiceCreateRedisWritesRequirepassConf(t *testing.T) {
	vol := t.TempDir()
	f := &fakeDocker{}
	params := CreateParams{
		ServiceType: "redis", Image: "redis:7",
		Network: "wokku-services", VolumePath: vol, AdminPass: "sekret",
	}
	if err := serviceCreate(context.Background(), f, "dokku.redis.x", params); err != nil {
		t.Fatal(err)
	}
	conf, err := os.ReadFile(filepath.Join(vol, "redis.conf"))
	if err != nil || string(conf) != "requirepass sekret\n" {
		t.Fatalf("conf: %q err=%v", conf, err)
	}
	found := false
	for _, c := range f.calls {
		if strings.Contains(c, "cmd=[redis-server /data/redis.conf]") {
			found = true
		}
	}
	if !found {
		t.Fatalf("container must load /data/redis.conf, calls=%v", f.calls)
	}
}

// A newline in admin_pass would inject arbitrary redis config directives —
// reject at the trust boundary even though the control plane is hex-only.
func TestServiceCreateRedisRejectsNewlinePassword(t *testing.T) {
	f := &fakeDocker{}
	params := CreateParams{
		ServiceType: "redis", Image: "redis:7",
		VolumePath: t.TempDir(), AdminPass: "pw\nrename-command CONFIG x",
	}
	err := serviceCreate(context.Background(), f, "dokku.redis.x", params)
	if err == nil || !strings.Contains(err.Error(), "newline") {
		t.Fatalf("want newline rejection, got %v", err)
	}
}

// An ensure recreate (adminPass "") must NOT rewrite the conf — the password
// already lives in the intact data dir and the op params never carry it.
func TestEnsureRedisRecreateKeepsExistingConf(t *testing.T) {
	vol := t.TempDir()
	orig := []byte("requirepass original\n")
	if err := os.WriteFile(filepath.Join(vol, "redis.conf"), orig, 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{}
	params := CreateParams{ServiceType: "redis", Image: "redis:7", VolumePath: vol, AdminPass: ""}
	res, err := serviceEnsure(context.Background(), f, "dokku.redis.x", params)
	if err != nil || res.Action != "recreated" {
		t.Fatalf("res=%+v err=%v", res, err)
	}
	after, _ := os.ReadFile(filepath.Join(vol, "redis.conf"))
	if string(after) != string(orig) {
		t.Fatalf("recreate must not touch the conf: %q", after)
	}
}

func TestServiceCreatePostgresCallSequence(t *testing.T) {
	f := &fakeDocker{}
	params := CreateParams{
		ServiceType: "postgres",
		Image:       "postgres:16-alpine",
		MemoryMB:    256,
		MaxConns:    0, // skipped: no ALTER exec, no restart (mirrors database_resources.rb's n<=0 guard)
		Network:     "dokku-net",
		VolumePath:  "/var/lib/dokku/services/postgres/mydb/data",
		AdminPass:   "pw",
	}
	if err := serviceCreate(context.Background(), f, "dokku.postgres.mydb", params); err != nil {
		t.Fatal(err)
	}

	want := []string{
		"ImageEnsure(postgres:16-alpine)",
		"VolumeCreate(/var/lib/dokku/services/postgres/mydb/data)",
		"ContainerCreate(name=dokku.postgres.mydb image=postgres:16-alpine env=[POSTGRES_PASSWORD=pw PGDATA=/var/lib/postgresql/data] bind=/var/lib/dokku/services/postgres/mydb/data:/var/lib/postgresql/data cmd=[])",
		"NetworkEnsure(dokku-net)",
		"NetworkConnect(dokku-net,dokku.postgres.mydb,aliases=)",
		"ContainerStart(dokku.postgres.mydb)",
		"ContainerUpdate(dokku.postgres.mydb,256)",
	}
	if len(f.calls) != len(want) {
		t.Fatalf("want %d calls, got %d: %v", len(want), len(f.calls), f.calls)
	}
	for i, w := range want {
		if f.calls[i] != w {
			t.Errorf("call %d: want %q, got %q", i, w, f.calls[i])
		}
	}
}

// B4 gate 3: "bridge" always exists and can't be NetworkCreate'd — the
// ensure step must be skipped for it (and only it).
// postgres:18 ignores a bind at /var/lib/postgresql/data unless PGDATA points
// there explicitly (it crash-loops with "unused mount/volume" otherwise —
// verified live on jkt-01, 2026-07-18). Pin PGDATA to the mount for every major.
func TestPostgresEnvPinsPGDATAToDataPath(t *testing.T) {
	spec := dedicatedEngines["postgres"]
	got := strings.Join(spec.env("pw", ""), " ")
	if !strings.Contains(got, "PGDATA="+spec.dataPath) {
		t.Errorf("postgres env must pin PGDATA to %s, got %v", spec.dataPath, spec.env("pw", ""))
	}
}

func TestServiceCreateBridgeSkipsNetworkEnsure(t *testing.T) {
	f := &fakeDocker{}
	params := CreateParams{
		ServiceType: "postgres", Image: "postgres:16", Network: "bridge", AdminPass: "pw",
	}
	if err := serviceCreate(context.Background(), f, "dokku.postgres.b", params); err != nil {
		t.Fatal(err)
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "NetworkEnsure") {
			t.Errorf("NetworkEnsure must not be called for bridge; calls: %v", f.calls)
		}
	}
}

func TestServiceCreateMariadbEnvAndDataPath(t *testing.T) {
	f := &fakeDocker{}
	params := CreateParams{
		ServiceType: "mariadb",
		Image:       "mariadb:11",
		VolumePath:  "/var/lib/dokku/services/mariadb/mydb/data",
		AdminPass:   "rootpw",
	}
	if err := serviceCreate(context.Background(), f, "dokku.mariadb.mydb", params); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(f.calls, " | ")
	if !strings.Contains(got, "env=[MARIADB_ROOT_PASSWORD=rootpw]") {
		t.Errorf("missing mariadb env, got %v", f.calls)
	}
	if !strings.Contains(got, "bind=/var/lib/dokku/services/mariadb/mydb/data:/var/lib/mysql") {
		t.Errorf("missing mariadb bind, got %v", f.calls)
	}
	// MemoryMB=0/MaxConns=0 -> no ContainerUpdate call at all.
	if strings.Contains(got, "ContainerUpdate") {
		t.Errorf("want no ContainerUpdate when memory_mb=0, got %v", f.calls)
	}
}

// mariadb max_connections must persist across the entrypoint's post-bootstrap
// mysqld restart. `SET GLOBAL` is runtime-only and is silently lost (the op
// still reports success — found live on prod 2026-07-17, value stayed at the
// 151 default). The durable fix writes a conf.d file (no DB auth needed, so it
// also dodges the password race) and restarts to apply it.
func TestMariadbSetConnsWritesDurableConf(t *testing.T) {
	cmd := dedicatedEngines["mariadb"].setConnsCmd(77)
	got := strings.Join(cmd, " ")
	if cmd[0] != "sh" || !strings.Contains(got, "/etc/mysql/conf.d/") {
		t.Errorf("want conf.d file write via sh, got %v", cmd)
	}
	if !strings.Contains(got, "max_connections=77") {
		t.Errorf("want max_connections=77 in conf, got %v", cmd)
	}
	if !dedicatedEngines["mariadb"].restartAfterSetConns {
		t.Error("mariadb must restart after writing the conf so it takes effect")
	}
}

// Task 10: a fresh dedicated create must ask the engine to create the
// application database on first boot via its native DB-creation env. Without
// it the container boots with only a root password and no app database, so the
// app's DSN points at a database that doesn't exist and the app 500s (proven
// on a wordpress/mariadb deploy). The env only takes effect on an empty data
// dir — exactly the fresh-create case; adopt reuses existing data.
func TestServiceCreateSetsDBCreationEnv(t *testing.T) {
	cases := []struct {
		serviceType string
		image       string
		wantEnv     string
	}{
		{"postgres", "postgres:16", "POSTGRES_DB=mtx_wp"},
		{"mariadb", "mariadb:11.4", "MARIADB_DATABASE=mtx_wp_mariadb"},
		{"mongodb", "mongo:7", "MONGO_INITDB_DATABASE=mtx_wp_mongo"},
	}
	for _, tc := range cases {
		t.Run(tc.serviceType, func(t *testing.T) {
			f := &fakeDocker{}
			db := strings.SplitN(tc.wantEnv, "=", 2)[1]
			err := serviceCreate(context.Background(), f, "dokku."+tc.serviceType+".x", CreateParams{
				ServiceType: tc.serviceType, Image: tc.image, AdminPass: "pw", Database: db,
			})
			if err != nil {
				t.Fatal(err)
			}
			got := strings.Join(f.calls, " | ")
			if !strings.Contains(got, tc.wantEnv) {
				t.Errorf("want %q in create env, got %v", tc.wantEnv, f.calls)
			}
		})
	}
}

// An empty Database param must add NO DB-creation env (redis, or any no-db
// case). Redis has no application-database concept at all.
func TestServiceCreateEmptyDatabaseAddsNoEnv(t *testing.T) {
	for _, st := range []string{"postgres", "mariadb", "mongodb", "redis"} {
		f := &fakeDocker{}
		image := map[string]string{"postgres": "postgres:16", "mariadb": "mariadb:11.4", "mongodb": "mongo:7", "redis": "redis:7"}[st]
		if err := serviceCreate(context.Background(), f, "dokku."+st+".x", CreateParams{
			ServiceType: st, Image: image, AdminPass: "pw", Database: "",
		}); err != nil {
			t.Fatal(err)
		}
		got := strings.Join(f.calls, " | ")
		for _, envKey := range []string{"POSTGRES_DB=", "MARIADB_DATABASE=", "MONGO_INITDB_DATABASE="} {
			if strings.Contains(got, envKey) {
				t.Errorf("%s: empty Database must add no %s, got %v", st, envKey, f.calls)
			}
		}
	}
}

func TestServiceCreateUnsupportedServiceType(t *testing.T) {
	f := &fakeDocker{}
	err := serviceCreate(context.Background(), f, "dokku.oracle.mydb", CreateParams{ServiceType: "oracle"})
	if err == nil {
		t.Fatal("want error for unsupported service_type")
	}
	if len(f.calls) != 0 {
		t.Fatalf("want no docker calls for unsupported service_type, got %v", f.calls)
	}
}

// --- service.set_limits ---

func TestServiceSetLimitsPostgresAltersAndRestarts(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceSetLimits(context.Background(), f, "dokku.postgres.mydb", "postgres", 512, 100, 0); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"ContainerUpdate(dokku.postgres.mydb,512)",
		"Exec(dokku.postgres.mydb,[psql -U postgres -c ALTER SYSTEM SET max_connections = 100;])",
		"ContainerRestart(dokku.postgres.mydb)",
	}
	if len(f.calls) != len(want) {
		t.Fatalf("want %d calls, got %d: %v", len(want), len(f.calls), f.calls)
	}
	for i, w := range want {
		if f.calls[i] != w {
			t.Errorf("call %d: want %q, got %q", i, w, f.calls[i])
		}
	}
}

func TestServiceSetLimitsMariadbWritesConfAndRestarts(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceSetLimits(context.Background(), f, "dokku.mariadb.mydb", "mariadb", 512, 100, 0); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(f.calls, " | ")
	// memory via docker update, limit via durable conf file, then a restart
	// so mysqld actually reads it (SET GLOBAL wouldn't survive the entrypoint's
	// post-bootstrap restart — the 2026-07-17 prod bug).
	if !strings.Contains(got, "ContainerUpdate(dokku.mariadb.mydb,512)") {
		t.Errorf("missing memory update, got %v", f.calls)
	}
	if !strings.Contains(got, "/etc/mysql/conf.d/") || !strings.Contains(got, "max_connections=100") {
		t.Errorf("missing durable conf write, got %v", f.calls)
	}
	if !strings.Contains(got, "ContainerRestart(dokku.mariadb.mydb)") {
		t.Errorf("mariadb must restart so the conf takes effect, got %v", f.calls)
	}
}

func TestServiceSetLimitsSkipsZeroValues(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceSetLimits(context.Background(), f, "c", "postgres", 0, 0, 0); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 0 {
		t.Fatalf("want no calls when memory_mb=0 and max_connections=0, got %v", f.calls)
	}
}

func TestSetLimitsAppliesCPU(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceSetLimits(context.Background(), f, "dokku.postgres.mydb", "postgres", 512, 0, 0.5); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(f.calls, "|")
	if !strings.Contains(got, "ContainerUpdate(dokku.postgres.mydb,512,cpu=0.5)") {
		t.Errorf("want cpu applied, got %v", f.calls)
	}
}

func TestSetLimitsCPUOnly(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceSetLimits(context.Background(), f, "dokku.redis.c", "redis", 0, 0, 0.25); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(f.calls, "|"), "ContainerUpdate(dokku.redis.c,0,cpu=0.25)") {
		t.Errorf("want cpu-only update, got %v", f.calls)
	}
}

// --- service.destroy (dedicated.go's half — the force gate itself lives in
// ops.go's dispatch and is tested there) ---

func TestServiceDestroyStopsThenRemoves(t *testing.T) {
	f := &fakeDocker{}
	if err := serviceDestroy(context.Background(), f, "dokku.postgres.mydb"); err != nil {
		t.Fatal(err)
	}
	want := []string{"ContainerInspect(dokku.postgres.mydb)", "ContainerStop(dokku.postgres.mydb)", "ContainerRemove(dokku.postgres.mydb)"}
	if len(f.calls) != 3 || f.calls[0] != want[0] || f.calls[1] != want[1] || f.calls[2] != want[2] {
		t.Fatalf("got %v", f.calls)
	}
}

// --- service.adopt ---

func TestServiceAdoptDedicatedPostgres(t *testing.T) {
	f := &fakeDocker{inspect: ContainerInfo{
		Image:    "postgres:16-alpine",
		Env:      []string{"POSTGRES_PASSWORD=secret", "PATH=/usr/bin"},
		Binds:    []string{"/var/lib/dokku/services/postgres/mydb/data:/var/lib/postgresql/data"},
		Networks: []string{"dokku-net"},
		Running:  true,
	}}
	res, err := serviceAdopt(context.Background(), f, "dokku.postgres.mydb")
	if err != nil {
		t.Fatal(err)
	}
	if res.Image != "postgres:16-alpine" || !res.Running || res.Network != "dokku-net" {
		t.Fatalf("got %+v", res)
	}
	if res.Volume != "/var/lib/dokku/services/postgres/mydb/data" {
		t.Errorf("volume = %q", res.Volume)
	}
	if res.EnvDSN != "postgres://postgres:secret@dokku.postgres.mydb:5432/mydb" {
		t.Errorf("env_dsn = %q", res.EnvDSN)
	}
	if len(res.Tenants) != 0 {
		t.Errorf("dedicated adopt must not populate tenants, got %+v", res.Tenants)
	}
}

func TestServiceAdoptSharedParentPopulatesTenants(t *testing.T) {
	dir := t.TempDir()
	orig := sharedPostgresMetaDir
	sharedPostgresMetaDir = dir
	defer func() { sharedPostgresMetaDir = orig }()

	tenantDir := filepath.Join(dir, "app1")
	if err := os.MkdirAll(tenantDir, 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"PASSWORD":       "tenantpw",
		"ROLE":           "app1_role",
		"DATABASE":       "app1",
		"QUOTA_MB":       "150",
		"QUOTA_VIOLATED": "false",
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(tenantDir, name), []byte(content+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	f := &fakeDocker{inspect: ContainerInfo{Image: "postgres:16-alpine", Running: true}}
	res, err := serviceAdopt(context.Background(), f, sharedPostgresContainer)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Tenants) != 1 {
		t.Fatalf("want 1 tenant, got %+v", res.Tenants)
	}
	tn := res.Tenants[0]
	if tn.Slug != "app1" || tn.Role != "app1_role" || tn.Database != "app1" || tn.Password != "tenantpw" || tn.QuotaMB != 150 || tn.QuotaViolated {
		t.Errorf("got %+v", tn)
	}
}

func TestServiceAdoptInspectError(t *testing.T) {
	f := &fakeDocker{inspectErr: errors.New("no such container")}
	if _, err := serviceAdopt(context.Background(), f, "dokku.postgres.gone"); err == nil {
		t.Fatal("want error when inspect fails")
	}
}

// --- ops.go dispatch: runOp ---

func TestRunOpServiceDestroyWithoutForceNeedsForce(t *testing.T) {
	f := &fakeDocker{}
	op := &queuedOp{kind: "service.destroy", service: "dokku.postgres.mydb", params: json.RawMessage(`{}`)}
	_, err := runOp(context.Background(), nil, f, op)
	if err == nil {
		t.Fatal("want error")
	}
	var oe *opError
	if !errors.As(err, &oe) || oe.code != errCodeDestroyNeedsForce {
		t.Fatalf("want error_code %q, got %v", errCodeDestroyNeedsForce, err)
	}
	if len(f.calls) != 0 {
		t.Fatalf("want no docker calls (no stop/remove) without force, got %v", f.calls)
	}
}

func TestRunOpServiceDestroyWithForceRuns(t *testing.T) {
	f := &fakeDocker{}
	op := &queuedOp{kind: "service.destroy", service: "dokku.postgres.mydb", params: json.RawMessage(`{"force":true}`)}
	if _, err := runOp(context.Background(), nil, f, op); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 3 {
		t.Fatalf("want inspect+stop+remove, got %v", f.calls)
	}
}

func TestDestroyableDataDir(t *testing.T) {
	cases := map[string]bool{
		"/var/lib/dokku/services/redis/my-redis/data":     true,
		"/var/lib/dokku/services/postgres/my-pg/data":     true,
		"/var/lib/dokku/services/shared-postgres/_pgdata": false, // shared parent: many tenants, never one service's to remove
		"/var/lib/dokku/services/shared-redis/data":       false,
		"/var/lib/dokku/services/":                        false,
		"/var/lib/dokku/services":                         false,
		"/home/user/data":                                 false,
		"/var/lib/docker/volumes/x":                       false,
	}
	for path, want := range cases {
		if got := destroyableDataDir(path); got != want {
			t.Errorf("destroyableDataDir(%q) = %v, want %v", path, got, want)
		}
	}
}

// destroy means destroy: the dedicated service's data dir goes with the
// container (dokku parity) — keeping it made a same-name recreate boot the
// OLD credentials against the NEW DSN (chatwoot's redis, 2026-07-22).
func TestServiceDestroyRemovesOwnDataDir(t *testing.T) {
	root := t.TempDir() + "/"
	old := servicesDataRoot
	servicesDataRoot = root
	t.Cleanup(func() { servicesDataRoot = old })

	dataDir := filepath.Join(root, "redis", "my-redis", "data")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dataDir, "redis.conf"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{inspect: ContainerInfo{Binds: []string{dataDir + ":/data"}}}
	if err := serviceDestroy(context.Background(), f, "dokku.redis.my-redis"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(dataDir); !os.IsNotExist(err) {
		t.Fatalf("data dir must be removed, stat err=%v", err)
	}
	// The now-empty parent (<type>/<name>/) is swept too.
	if _, err := os.Stat(filepath.Dir(dataDir)); !os.IsNotExist(err) {
		t.Fatalf("empty parent must be removed, stat err=%v", err)
	}
}

func TestServiceDestroyLeavesOutOfScopeBinds(t *testing.T) {
	outside := t.TempDir()
	if err := os.WriteFile(filepath.Join(outside, "keep"), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{inspect: ContainerInfo{Binds: []string{outside + ":/data"}}}
	if err := serviceDestroy(context.Background(), f, "dokku.redis.x"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(outside, "keep")); err != nil {
		t.Fatalf("out-of-scope bind must survive destroy: %v", err)
	}
}

// Fresh create refuses a non-empty data dir (the inverse of ensure's
// data_dir_missing guard) — booting over leftover data keeps the old
// credentials against the new DSN.
func TestRunOpServiceCreateRefusesNonEmptyDataDir(t *testing.T) {
	vol := t.TempDir()
	if err := os.WriteFile(filepath.Join(vol, "PG_VERSION"), []byte("16"), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{}
	op := &queuedOp{kind: "service.create", service: "dokku.postgres.x",
		params: json.RawMessage(fmt.Sprintf(`{"service_type":"postgres","image":"postgres:16","volume_path":%q,"admin_pass":"pw"}`, vol))}
	_, err := runOp(context.Background(), nil, f, op)
	var oe *opError
	if !errors.As(err, &oe) || oe.code != "data_dir_exists" {
		t.Fatalf("want data_dir_exists, got %v", err)
	}
	if len(f.calls) != 0 {
		t.Fatalf("refusal must precede any docker call, got %v", f.calls)
	}
}

func TestRunOpServiceCreateProceedsOnEmptyOrAbsentDataDir(t *testing.T) {
	for _, vol := range []string{t.TempDir(), t.TempDir() + "/absent"} {
		f := &fakeDocker{}
		op := &queuedOp{kind: "service.create", service: "dokku.postgres.x",
			params: json.RawMessage(fmt.Sprintf(`{"service_type":"postgres","image":"postgres:16","volume_path":%q,"admin_pass":"pw"}`, vol))}
		if _, err := runOp(context.Background(), nil, f, op); err != nil {
			t.Fatalf("vol=%q: %v", vol, err)
		}
	}
}

func TestRunOpTenantDestroyWithoutForceNeedsForce(t *testing.T) {
	f := &fakeDocker{}
	op := &queuedOp{kind: "tenant.destroy", service: "app1", params: json.RawMessage(`{}`)}
	_, err := runOp(context.Background(), nil, f, op)
	var oe *opError
	if !errors.As(err, &oe) || oe.code != errCodeDestroyNeedsForce {
		t.Fatalf("want error_code %q, got %v", errCodeDestroyNeedsForce, err)
	}
	if len(f.calls) != 0 {
		t.Fatalf("want no DROP exec without force, got %v", f.calls)
	}
}

// C1: op.service is the PARENT container name (never a slug) — the tenant
// slug travels in params.slug instead. Confirms the DROP targets params.slug
// even though op.service here is deliberately set to something else.
func TestRunOpTenantDestroyWithForceUsesParamsSlugNotOpService(t *testing.T) {
	f := &fakeDocker{}
	op := &queuedOp{
		kind:    "tenant.destroy",
		service: sharedPostgresContainer,
		params:  json.RawMessage(`{"force":true,"slug":"app1"}`),
	}
	if _, err := runOp(context.Background(), nil, f, op); err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 2 { // DROP DATABASE, DROP ROLE — mirrors pgDestroyTenant
		t.Fatalf("want 2 execs, got %v", f.calls)
	}
	for _, c := range f.calls {
		if !strings.Contains(c, "app1") {
			t.Errorf("want slug app1 dropped, got %v", c)
		}
	}
}

func TestRunOpTenantProvisionExistsSentinelMapsToErrorCode(t *testing.T) {
	f := &fakeDocker{execErr: []error{errors.New(`ERROR:  role "app1_role" already exists`)}}
	params, _ := json.Marshal(TenantProvisionParams{Slug: "app1", Password: "pw", QuotaMB: 150, MaxConns: 40})
	op := &queuedOp{kind: "tenant.provision", service: sharedPostgresContainer, params: params}
	_, err := runOp(context.Background(), nil, f, op)
	var oe *opError
	if !errors.As(err, &oe) || oe.code != errCodeTenantExists {
		t.Fatalf("want error_code %q, got %v", errCodeTenantExists, err)
	}
}

func TestRunOpTenantProvisionSuccess(t *testing.T) {
	f := &fakeDocker{}
	params, _ := json.Marshal(TenantProvisionParams{Slug: "app1", Password: "pw", QuotaMB: 150, MaxConns: 40})
	op := &queuedOp{kind: "tenant.provision", service: sharedPostgresContainer, params: params}
	result, err := runOp(context.Background(), nil, f, op)
	if err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 3 { // CREATE ROLE, CREATE DATABASE, REVOKE — mirrors pgProvisionTenant
		t.Fatalf("want 3 execs, got %v", f.calls)
	}
	if m, ok := result.(map[string]string); !ok || m["slug"] != "app1" {
		t.Fatalf("got %+v", result)
	}
}

// Tenant ops dispatch by op.service (the shared parent container name) —
// a container that isn't a known shared parent gets the friendly refusal,
// reported like any other handler failure.
func TestRunOpTenantOpsUnknownEngineRefused(t *testing.T) {
	f := &fakeDocker{}
	params := json.RawMessage(`{"slug":"app1","password":"pw","force":true,"quota_mb":25,"tenants":[]}`)
	for _, kind := range []string{"tenant.provision", "tenant.destroy", "tenant.set_quota", "service.check_quotas"} {
		_, err := runOp(context.Background(), nil, f, &queuedOp{kind: kind, service: "dokku.postgres.x", params: params})
		if err == nil || !strings.Contains(err.Error(), "unsupported shared engine") {
			t.Errorf("%s: want unsupported-shared-engine refusal, got %v", kind, err)
		}
	}
	if len(f.calls) != 0 {
		t.Fatalf("want no execs for unknown engine, got %v", f.calls)
	}
}

func TestRunOpTenantProvisionRoutesToRedisEngine(t *testing.T) {
	f := &fakeDocker{} // exec outputs default "": GETUSER empty -> user missing
	params, _ := json.Marshal(TenantProvisionParams{Slug: "app1", Password: "pw"})
	op := &queuedOp{kind: "tenant.provision", service: "dokku-shared-redis", params: params}
	result, err := runOp(context.Background(), nil, f, op)
	if err != nil {
		t.Fatal(err)
	}
	if len(f.calls) != 3 { // GETUSER, SETUSER, SAVE — redis, not postgres
		t.Fatalf("want 3 execs, got %v", f.calls)
	}
	for _, c := range f.calls {
		if !strings.Contains(c, "dokku-shared-redis") || !strings.Contains(c, "redis-cli") {
			t.Errorf("call not routed to redis parent: %s", c)
		}
	}
	if m, ok := result.(map[string]string); !ok || m["key_prefix"] != "app1:" {
		t.Fatalf("got %+v", result)
	}
}

func TestRunOpUnknownKindTypedFailure(t *testing.T) {
	op := &queuedOp{kind: "service.frobnicate", service: "x", params: json.RawMessage(`{}`)}
	_, err := runOp(context.Background(), nil, &fakeDocker{}, op)
	if err == nil || !strings.Contains(err.Error(), "unknown kind") {
		t.Fatalf("want typed unknown-kind failure, got %v", err)
	}
}

func TestRunOpServiceAdoptDispatches(t *testing.T) {
	f := &fakeDocker{inspect: ContainerInfo{Image: "redis:7", Running: true}}
	op := &queuedOp{kind: "service.adopt", service: "dokku.redis.cache1", params: json.RawMessage(`{}`)}
	result, err := runOp(context.Background(), nil, f, op)
	if err != nil {
		t.Fatal(err)
	}
	res, ok := result.(*AdoptResult)
	if !ok || res.Image != "redis:7" || !res.Running {
		t.Fatalf("got %+v", result)
	}
}

// TestRunOpServiceCheckQuotas verifies the control plane's tenant list
// (op.params, as Rails' SharedDatabaseQuotaJob sends it) drives the sweep —
// NOT host QUOTA_MB files. This closes the invisible-new-tenant gap: tenants
// provisioned via tenant.provision never get a host metadata file, so a
// host-file-derived list would silently skip them forever.
func TestRunOpServiceCheckQuotas(t *testing.T) {
	f := &fakeDocker{execOut: []string{"999999999", ""}}
	op := &queuedOp{
		kind:    "service.check_quotas",
		service: sharedPostgresContainer,
		params:  json.RawMessage(`{"tenants":[{"slug":"app1","cap_bytes":150000000}]}`),
	}
	result, err := runOp(context.Background(), nil, f, op)
	if err != nil {
		t.Fatal(err)
	}
	body, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("got %+v", result)
	}
	statuses, ok := body["tenants"].([]TenantQuotaStatus)
	if !ok || len(statuses) != 1 || statuses[0].Slug != "app1" || !statuses[0].Over {
		t.Fatalf("got %+v", body)
	}
}

// TestRunOpServiceCheckQuotasEmptyParams verifies the no-tenants case
// returns an empty result, not a crash — e.g. a shared parent with zero
// tenants currently provisioned.
func TestRunOpServiceCheckQuotasEmptyParams(t *testing.T) {
	f := &fakeDocker{}
	op := &queuedOp{kind: "service.check_quotas", service: sharedPostgresContainer, params: json.RawMessage(`{}`)}
	result, err := runOp(context.Background(), nil, f, op)
	if err != nil {
		t.Fatal(err)
	}
	body, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("got %+v", result)
	}
	statuses, ok := body["tenants"].([]TenantQuotaStatus)
	if !ok || len(statuses) != 0 {
		t.Fatalf("want empty tenants result, got %+v", body)
	}
}

// First-rung B4 smoke (2026-07-17): service.create on a host without the
// image failed with "No such image" — create must ensure the image exists
// (inspect, pull-if-missing) before touching volumes/containers.
func TestServiceCreateFailsBeforeContainerWhenImageUnavailable(t *testing.T) {
	f := &fakeDocker{failOn: map[string]error{"ImageEnsure": fmt.Errorf("pull failed: no such image")}}
	err := serviceCreate(context.Background(), f, "dokku.postgres.mydb", CreateParams{
		ServiceType: "postgres", Image: "postgres:16", AdminPass: "pw",
	})
	if err == nil {
		t.Fatal("expected error when image cannot be ensured")
	}
	for _, c := range f.calls {
		if c != "ImageEnsure(postgres:16)" {
			t.Fatalf("no other docker call may happen after image failure, got %v", f.calls)
		}
	}
}

// B4 first-rung smoke (2026-07-17): create ran ALTER SYSTEM immediately
// after ContainerStart — postgres was still in initdb, socket absent, exec
// exit 2. The first post-start admin exec must retry until the engine is
// ready (bounded).
func TestServiceCreateRetriesSetConnsUntilEngineReady(t *testing.T) {
	restore := setConnsRetryInterval
	setConnsRetryInterval = 0
	defer func() { setConnsRetryInterval = restore }()

	f := &fakeDocker{execErr: []error{
		fmt.Errorf(`exit 2: psql: error: connection to server on socket failed`),
		fmt.Errorf(`exit 2: psql: error: connection to server on socket failed`),
		nil,
	}}
	err := serviceCreate(context.Background(), f, "dokku.postgres.mydb", CreateParams{
		ServiceType: "postgres", Image: "postgres:16", MaxConns: 10, AdminPass: "pw",
	})
	if err != nil {
		t.Fatalf("create should succeed once the engine comes up: %v", err)
	}
	execs := 0
	for _, c := range f.calls {
		if strings.HasPrefix(c, "Exec(") {
			execs++
		}
	}
	if execs != 3 {
		t.Fatalf("want 3 exec attempts (2 fail + 1 ok), got %d: %v", execs, f.calls)
	}
}

func TestServiceCreateGivesUpWhenEngineNeverReady(t *testing.T) {
	restore := setConnsRetryInterval
	setConnsRetryInterval = 0
	defer func() { setConnsRetryInterval = restore }()

	errs := make([]error, setConnsRetryAttempts+1)
	for i := range errs {
		errs[i] = fmt.Errorf("exit 2: socket failed")
	}
	f := &fakeDocker{execErr: errs}
	err := serviceCreate(context.Background(), f, "dokku.postgres.mydb", CreateParams{
		ServiceType: "postgres", Image: "postgres:16", MaxConns: 10, AdminPass: "pw",
	})
	if err == nil {
		t.Fatal("expected error when engine never becomes ready")
	}
}

func TestNetworkConnectRecordsAliases(t *testing.T) {
	f := &fakeDocker{}
	if err := f.NetworkConnect(context.Background(), "wokku-services", "dokku-shared-postgres", "dokku-shared-postgres"); err != nil {
		t.Fatal(err)
	}
	want := "NetworkConnect(wokku-services,dokku-shared-postgres,aliases=dokku-shared-postgres)"
	if len(f.calls) != 1 || f.calls[0] != want {
		t.Fatalf("got %v, want %q", f.calls, want)
	}
}

func TestContainerExistsFake(t *testing.T) {
	f := &fakeDocker{existing: map[string]bool{"here": true}}
	if ok, _ := f.ContainerExists(context.Background(), "here"); !ok {
		t.Fatal("want exists=true for a present container")
	}
	if ok, _ := f.ContainerExists(context.Background(), "gone"); ok {
		t.Fatal("want exists=false for a missing container")
	}
}

// Mongo root is created in the admin DB; a DSN naming the app database must
// say so, or drivers authenticate against the app DB and fail.
func TestAdoptMongoDSNCarriesAuthSourceAdmin(t *testing.T) {
	for _, spec := range adoptDSNEnvs {
		if spec.envKey == "MONGO_INITDB_ROOT_PASSWORD" {
			got := fmt.Sprintf(spec.format, "pw", "dokku.mongodb.x", "x")
			if got != "mongodb://root:pw@dokku.mongodb.x:27017/x?authSource=admin" {
				t.Fatalf("got %q", got)
			}
			return
		}
	}
	t.Fatal("no mongo adopt DSN entry")
}
