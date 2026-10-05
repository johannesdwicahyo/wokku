package services

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func sqlOf(c execCall) string { return c.cmd[len(c.cmd)-1] }

func TestMariadbProvisionTenantSQLSequence(t *testing.T) {
	x := &fakeExecer{}
	res, err := mariadbProvisionTenant(context.Background(), x, sharedMariadbContainer,
		TenantProvisionParams{Slug: "my_app", Password: "s3cret", QuotaMB: 100, MaxConns: 40})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		`CREATE USER 'my_app'@'%' IDENTIFIED BY 's3cret' WITH MAX_USER_CONNECTIONS 40;`,
		"CREATE DATABASE `my_app` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;",
		// '_' escaped: unescaped it is a wildcard and would also grant on "myxapp".
		"GRANT ALL PRIVILEGES ON `my\\_app`.* TO 'my_app'@'%';",
	}
	if len(x.calls) != len(want) {
		t.Fatalf("want %d execs, got %d", len(want), len(x.calls))
	}
	for i, w := range want {
		if got := sqlOf(x.calls[i]); got != w {
			t.Errorf("call %d:\n got %s\nwant %s", i, got, w)
		}
		if x.calls[i].container != sharedMariadbContainer || x.calls[i].cmd[0] != "sh" {
			t.Errorf("call %d must exec the admin wrapper in the parent: %+v", i, x.calls[i])
		}
	}
	if res["slug"] != "my_app" {
		t.Fatalf("result = %v", res)
	}
}

func TestMariadbProvisionTenantExistsSentinel(t *testing.T) {
	x := &fakeExecer{errs: []error{errors.New("ERROR 1396 (HY000): Operation CREATE USER failed for 'a'@'%'")}}
	_, err := mariadbProvisionTenant(context.Background(), x, "c", TenantProvisionParams{Slug: "a", Password: "p"})
	if !errors.Is(err, errTenantExists) {
		t.Fatalf("want errTenantExists, got %v", err)
	}
}

func TestMariadbProvisionQuotesPassword(t *testing.T) {
	x := &fakeExecer{}
	if _, err := mariadbProvisionTenant(context.Background(), x, "c", TenantProvisionParams{Slug: "a", Password: `p'w\`}); err != nil {
		t.Fatal(err)
	}
	if got := sqlOf(x.calls[0]); !strings.Contains(got, `IDENTIFIED BY 'p\'w\\'`) {
		t.Fatalf("password not escaped: %s", got)
	}
}

func TestMariadbRejectsReservedAndInvalidSlugs(t *testing.T) {
	for _, slug := range []string{"root", "mysql", "sys", "information_schema", "x`; DROP DATABASE mysql; --"} {
		x := &fakeExecer{}
		if _, err := mariadbProvisionTenant(context.Background(), x, "c", TenantProvisionParams{Slug: slug}); err == nil {
			t.Errorf("provision %q must be refused", slug)
		}
		if err := mariadbDestroyTenant(context.Background(), x, "c", slug); err == nil {
			t.Errorf("destroy %q must be refused", slug)
		}
		if len(x.calls) != 0 {
			t.Errorf("%q: no SQL may run, got %v", slug, x.calls)
		}
	}
}

func TestMariadbDestroyTenant(t *testing.T) {
	x := &fakeExecer{}
	if err := mariadbDestroyTenant(context.Background(), x, "c", "app1"); err != nil {
		t.Fatal(err)
	}
	if sqlOf(x.calls[0]) != "DROP DATABASE IF EXISTS `app1`;" || sqlOf(x.calls[1]) != "DROP USER IF EXISTS 'app1'@'%';" {
		t.Fatalf("unexpected SQL: %v", x.calls)
	}
}

func TestMariadbCheckQuotasOverAndUnder(t *testing.T) {
	// call order: size(over), flip(over), size(under), flip(under)
	x := &fakeExecer{outputs: []string{"2097152\n", "", "1024\n", ""}}
	st, err := mariadbCheckQuotas(context.Background(), x, "c", []TenantQuota{
		{Slug: "big", CapBytes: 1048576},
		{Slug: "small", CapBytes: 1048576},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !st[0].Over || !st[0].ReadOnly || st[0].SizeBytes != 2097152 {
		t.Fatalf("big: %+v", st[0])
	}
	if st[1].Over || st[1].ReadOnly || st[1].SizeBytes != 1024 {
		t.Fatalf("small: %+v", st[1])
	}
	if !strings.Contains(sqlOf(x.calls[0]), "information_schema.tables WHERE table_schema = 'big'") {
		t.Fatalf("size query: %s", sqlOf(x.calls[0]))
	}
	over := sqlOf(x.calls[1])
	for _, frag := range []string{"REVOKE ALL PRIVILEGES ON `big`.* FROM 'big'@'%'", "GRANT SELECT, DELETE, DROP ON `big`.* TO 'big'@'%'"} {
		if !strings.Contains(over, frag) {
			t.Errorf("over flip missing %q: %s", frag, over)
		}
	}
	if strings.Index(over, "GRANT SELECT ON") > strings.Index(over, "REVOKE") {
		t.Errorf("a grant row must exist before REVOKE ALL: %s", over)
	}
	if sqlOf(x.calls[3]) != "GRANT ALL PRIVILEGES ON `small`.* TO 'small'@'%';" {
		t.Errorf("under flip: %s", sqlOf(x.calls[3]))
	}
	// The JSON wire shape the control plane reads.
	b, _ := json.Marshal(st[0])
	for _, k := range []string{`"slug":"big"`, `"size_bytes":2097152`, `"over":true`} {
		if !strings.Contains(string(b), k) {
			t.Errorf("wire missing %s: %s", k, b)
		}
	}
}

func TestMariadbDispatchRegistered(t *testing.T) {
	if _, err := sharedEngineFor(sharedMariadbContainer); err != nil {
		t.Fatal(err)
	}
	for _, gone := range []string{"dokku-shared-rabbitmq", "dokku-shared-meilisearch"} {
		if _, err := sharedEngineFor(gone); err == nil {
			t.Errorf("%s must no longer have tenant ops", gone)
		}
	}
}

func TestRedactArgvMasksIdentifiedBy(t *testing.T) {
	got := strings.Join(redactArgv(mariadbArgs(`CREATE USER 'a'@'%' IDENTIFIED BY 'se\'cret' WITH MAX_USER_CONNECTIONS 40;`)), " ")
	if strings.Contains(got, "cret") || !strings.Contains(got, `IDENTIFIED BY '***'`) {
		t.Fatalf("IDENTIFIED BY literal not redacted: %s", got)
	}
}

func withSharedMariadbDir(t *testing.T) string {
	t.Helper()
	orig, origInterval := sharedMariadbDir, setConnsRetryInterval
	t.Cleanup(func() { sharedMariadbDir, setConnsRetryInterval = orig, origInterval })
	sharedMariadbDir = t.TempDir()
	setConnsRetryInterval = 0
	return sharedMariadbDir
}

func TestEnsureSharedMariadbFirstBootCreates(t *testing.T) {
	base := withSharedMariadbDir(t)
	f := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "created" {
		t.Fatalf("first boot must create, got %q", res.Action)
	}
	pw, ok := readMetaFile(base, "ROOT_PASSWORD")
	if !ok || len(pw) != 32 {
		t.Fatalf("root password must be minted and stored, got %q", pw)
	}
	if info, _ := os.Stat(filepath.Join(base, "ROOT_PASSWORD")); info.Mode().Perm() != 0o600 {
		t.Fatalf("ROOT_PASSWORD perms = %v", info.Mode().Perm())
	}
	joined := strings.Join(f.calls, " | ")
	for _, want := range []string{
		"ImageEnsure(mariadb:11.4.13)",
		"env=[MARIADB_ROOT_PASSWORD=" + pw + " MARIADB_ROOT_HOST=localhost]",
		"--max-connections=200",
		"bind=" + filepath.Join(base, "data") + ":/var/lib/mysql",
		"--innodb-buffer-pool-size=384M",
		"NetworkConnect(wokku-services,dokku-shared-mariadb,aliases=dokku-shared-mariadb)",
		"ContainerUpdate(dokku-shared-mariadb,1024)",
		"mariadb-admin -h127.0.0.1 --protocol=tcp ping",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing %q in %v", want, f.calls)
		}
	}
}

func TestEnsureSharedMariadbRecreatesOnIntactData(t *testing.T) {
	base := withSharedMariadbDir(t)
	_ = os.WriteFile(filepath.Join(base, "ROOT_PASSWORD"), []byte("keepme\n"), 0o600)
	_ = os.MkdirAll(filepath.Join(base, "data", "mysql"), 0o700)
	f := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "recreated" || !strings.Contains(strings.Join(f.calls, " "), "MARIADB_ROOT_PASSWORD=keepme") {
		t.Fatalf("must recreate with the stored password: %q %v", res.Action, f.calls)
	}
}

func TestEnsureSharedMariadbRefusals(t *testing.T) {
	t.Run("born but data gone", func(t *testing.T) {
		base := withSharedMariadbDir(t)
		_ = os.WriteFile(filepath.Join(base, "ROOT_PASSWORD"), []byte("pw"), 0o600)
		f := &fakeDocker{existing: map[string]bool{}}
		_, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{})
		if err == nil || !strings.HasPrefix(err.Error(), "data_dir_missing:") {
			t.Fatalf("want data_dir_missing, got %v", err)
		}
		if len(f.calls) > 1 { // only ContainerExists
			t.Fatalf("must not touch docker: %v", f.calls)
		}
	})
	t.Run("data without password", func(t *testing.T) {
		base := withSharedMariadbDir(t)
		_ = os.MkdirAll(filepath.Join(base, "data", "mysql"), 0o700)
		f := &fakeDocker{existing: map[string]bool{}}
		if _, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{}); err == nil {
			t.Fatal("must refuse to boot over data it can't log into")
		}
		if _, ok := readMetaFile(base, "ROOT_PASSWORD"); ok {
			t.Fatal("must not mint a password over existing data")
		}
	})
}

// Review fix 1: a failed first pull must leave NOTHING behind — the retry is
// a clean first boot, never a permanent data_dir_missing.
func TestEnsureSharedMariadbFailedPullIsRetryable(t *testing.T) {
	base := withSharedMariadbDir(t)
	f := &fakeDocker{existing: map[string]bool{}, failOn: map[string]error{"ImageEnsure": errors.New("toomanyrequests")}}
	if _, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{}); err == nil {
		t.Fatal("pull failure must surface")
	}
	if _, ok := readMetaFile(base, "ROOT_PASSWORD"); ok {
		t.Fatal("ROOT_PASSWORD must not be written before the image is pulled")
	}

	f2 := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f2, sharedMariadbContainer, CreateParams{})
	if err != nil || res.Action != "created" {
		t.Fatalf("retry must be a clean first boot, got %q %v", res.Action, err)
	}
	if !dataDirPresent(filepath.Join(base, "data")) {
		t.Fatal("data dir must exist once ROOT_PASSWORD does")
	}
}

// A first boot that dies after the marker (e.g. container create fails)
// recreates on the next ensure with the SAME stored password.
func TestEnsureSharedMariadbFailedCreateRecreatesWithStoredPassword(t *testing.T) {
	base := withSharedMariadbDir(t)
	f := &fakeDocker{existing: map[string]bool{}, failOn: map[string]error{"ContainerCreate": errors.New("boom")}}
	if _, err := serviceEnsure(context.Background(), f, sharedMariadbContainer, CreateParams{}); err == nil {
		t.Fatal("create failure must surface")
	}
	pw, _ := readMetaFile(base, "ROOT_PASSWORD")
	f2 := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f2, sharedMariadbContainer, CreateParams{})
	if err != nil || res.Action != "recreated" || !strings.Contains(strings.Join(f2.calls, " "), "MARIADB_ROOT_PASSWORD="+pw) {
		t.Fatalf("want recreate with stored password: %q %v %v", res.Action, err, f2.calls)
	}
}
