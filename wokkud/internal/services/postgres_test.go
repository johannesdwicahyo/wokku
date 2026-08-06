package services

import (
	"context"
	"errors"
	"strings"
	"testing"
)

// execCall records one Exec invocation for assertion.
type execCall struct {
	container string
	stdin     string
	cmd       []string
}

// fakeExecer is the test double for execer: records every call in order and
// returns canned outputs/errors by call index.
type fakeExecer struct {
	calls   []execCall
	outputs []string
	errs    []error
}

func (f *fakeExecer) Exec(ctx context.Context, container, stdin string, cmd ...string) (string, error) {
	i := len(f.calls)
	f.calls = append(f.calls, execCall{container: container, stdin: stdin, cmd: cmd})
	var out string
	if i < len(f.outputs) {
		out = f.outputs[i]
	}
	var err error
	if i < len(f.errs) {
		err = f.errs[i]
	}
	return out, err
}

func TestPgProvisionTenantSQLSequence(t *testing.T) {
	x := &fakeExecer{}
	err := pgProvisionTenant(context.Background(), x, "dokku-shared-postgres", "app1", "s3cret", 150, 40)
	if err != nil {
		t.Fatal(err)
	}
	wantFrags := []string{
		`CREATE ROLE "app1_role" LOGIN PASSWORD 's3cret' CONNECTION LIMIT 40`,
		`CREATE DATABASE "app1" OWNER "app1_role"`,
		`REVOKE CONNECT ON DATABASE "app1" FROM PUBLIC`,
	}
	if len(x.calls) != 3 {
		t.Fatalf("want 3 execs, got %d", len(x.calls))
	}
	for i, frag := range wantFrags {
		if !strings.Contains(strings.Join(x.calls[i].cmd, " "), frag) {
			t.Errorf("call %d missing %q, got %v", i, frag, x.calls[i].cmd)
		}
		if x.calls[i].container != "dokku-shared-postgres" {
			t.Errorf("call %d container = %q", i, x.calls[i].container)
		}
	}
}

// quotaMB is accepted (matches the control-plane op params contract) even
// though the flip-only design means it isn't used in any SQL here — the
// brief's signature keeps it so callers don't need a special no-op path.
func TestPgProvisionTenantIgnoresQuotaMB(t *testing.T) {
	x := &fakeExecer{}
	if err := pgProvisionTenant(context.Background(), x, "c", "app1", "pw", 999999, 40); err != nil {
		t.Fatal(err)
	}
}

func TestPgProvisionTenantRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	err := pgProvisionTenant(context.Background(), x, "c", `x"; DROP ROLE postgres; --`, "pw", 150, 40)
	if err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for invalid slug, got %d", len(x.calls))
	}
}

func TestPgProvisionTenantRejectsReservedSlug(t *testing.T) {
	x := &fakeExecer{}
	err := pgProvisionTenant(context.Background(), x, "c", "postgres", "pw", 150, 40)
	if err == nil {
		t.Fatal("want error for reserved slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for reserved slug, got %d", len(x.calls))
	}
}

// A password containing a single quote must not break out of the SQL string
// literal — the plan's SQL template interpolates it raw ('<pw>'), so this
// guards the one untrusted-content injection surface the brief flagged for
// self-review (slug is regex-validated; password is control-plane-generated
// but not otherwise constrained).
func TestPgProvisionTenantEscapesPasswordQuote(t *testing.T) {
	x := &fakeExecer{}
	if err := pgProvisionTenant(context.Background(), x, "c", "app1", "p'w", 150, 40); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(x.calls[0].cmd, " ")
	if !strings.Contains(got, `PASSWORD 'p''w'`) {
		t.Fatalf("password quote not escaped: %v", x.calls[0].cmd)
	}
}

func TestPgProvisionTenantRoleExistsSentinel(t *testing.T) {
	x := &fakeExecer{errs: []error{errors.New(`ERROR:  role "app1_role" already exists`)}}
	err := pgProvisionTenant(context.Background(), x, "c", "app1", "pw", 150, 40)
	if !errors.Is(err, errTenantExists) {
		t.Fatalf("want errTenantExists, got %v", err)
	}
	if len(x.calls) != 1 {
		t.Fatalf("want to stop after the failing CREATE ROLE, got %d calls", len(x.calls))
	}
}

func TestPgDestroyTenantSQLSequence(t *testing.T) {
	x := &fakeExecer{}
	if err := pgDestroyTenant(context.Background(), x, "dokku-shared-postgres", "app1"); err != nil {
		t.Fatal(err)
	}
	wantFrags := []string{
		`DROP DATABASE IF EXISTS "app1" WITH (FORCE)`,
		`DROP ROLE IF EXISTS "app1_role"`,
	}
	if len(x.calls) != 2 {
		t.Fatalf("want 2 execs, got %d", len(x.calls))
	}
	for i, frag := range wantFrags {
		if !strings.Contains(strings.Join(x.calls[i].cmd, " "), frag) {
			t.Errorf("call %d missing %q", i, frag)
		}
	}
}

func TestPgDestroyTenantRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	if err := pgDestroyTenant(context.Background(), x, "c", "not valid!"); err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for invalid slug, got %d", len(x.calls))
	}
}

func TestPgDestroyTenantRejectsReservedSlug(t *testing.T) {
	x := &fakeExecer{}
	if err := pgDestroyTenant(context.Background(), x, "c", "template1"); err == nil {
		t.Fatal("want error for reserved slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for reserved slug, got %d", len(x.calls))
	}
}

func TestPgSetQuotaFlipsReadOnlyOn(t *testing.T) {
	x := &fakeExecer{}
	if err := pgSetQuota(context.Background(), x, "c", "app1", true); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 1 {
		t.Fatalf("want 1 exec, got %d", len(x.calls))
	}
	got := strings.Join(x.calls[0].cmd, " ")
	if !strings.Contains(got, `ALTER DATABASE "app1" SET default_transaction_read_only = on`) {
		t.Fatalf("got %v", x.calls[0].cmd)
	}
}

func TestPgSetQuotaFlipsReadOnlyOff(t *testing.T) {
	x := &fakeExecer{}
	if err := pgSetQuota(context.Background(), x, "c", "app1", false); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(x.calls[0].cmd, " ")
	if !strings.Contains(got, `ALTER DATABASE "app1" SET default_transaction_read_only = off`) {
		t.Fatalf("got %v", x.calls[0].cmd)
	}
}

func TestPgSetQuotaRejectsReservedSlug(t *testing.T) {
	x := &fakeExecer{}
	if err := pgSetQuota(context.Background(), x, "c", "template1", true); err == nil {
		t.Fatal("want error for reserved slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for reserved slug, got %d", len(x.calls))
	}
}

func TestPgCheckQuotasTyped(t *testing.T) {
	x := &fakeExecer{outputs: []string{"999999999", ""}} // size query, then read-only flip
	got, err := pgCheckQuotas(context.Background(), x, "dokku-shared-postgres",
		[]TenantQuota{{Slug: "app1", CapBytes: 157286400}})
	if err != nil {
		t.Fatal(err)
	}
	if !got[0].Over || got[0].SizeBytes != 999999999 || !got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	if got[0].Slug != "app1" || got[0].CapBytes != 157286400 {
		t.Fatalf("got %+v", got[0])
	}
	wantFrags := []string{
		`SELECT pg_database_size('app1')`,
		`ALTER DATABASE "app1" SET default_transaction_read_only = on`,
	}
	for i, frag := range wantFrags {
		if !strings.Contains(strings.Join(x.calls[i].cmd, " "), frag) {
			t.Errorf("call %d missing %q, got %v", i, frag, x.calls[i].cmd)
		}
	}
}

func TestPgCheckQuotasUnderCapReleasesReadOnly(t *testing.T) {
	x := &fakeExecer{outputs: []string{"1000", ""}}
	got, err := pgCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 157286400}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].Over || got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	got2 := strings.Join(x.calls[1].cmd, " ")
	if !strings.Contains(got2, `default_transaction_read_only = off`) {
		t.Fatalf("got %v", x.calls[1].cmd)
	}
}

func TestPgCheckQuotasMultipleTenants(t *testing.T) {
	x := &fakeExecer{outputs: []string{"999999999", "", "1000", ""}}
	got, err := pgCheckQuotas(context.Background(), x, "c", []TenantQuota{
		{Slug: "app1", CapBytes: 157286400},
		{Slug: "app2", CapBytes: 157286400},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || !got[0].Over || got[1].Over {
		t.Fatalf("got %+v", got)
	}
	if len(x.calls) != 4 {
		t.Fatalf("want 4 execs (2 per tenant), got %d", len(x.calls))
	}
}

func TestPgCheckQuotasRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	_, err := pgCheckQuotas(context.Background(), x, "c", []TenantQuota{{Slug: "bad slug!", CapBytes: 1}})
	if err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for invalid slug, got %d", len(x.calls))
	}
}

func TestPgCheckQuotasRejectsReservedSlug(t *testing.T) {
	x := &fakeExecer{}
	_, err := pgCheckQuotas(context.Background(), x, "c", []TenantQuota{{Slug: "template0", CapBytes: 1}})
	if err == nil {
		t.Fatal("want error for reserved slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs for reserved slug, got %d", len(x.calls))
	}
}

func TestPgCheckQuotasBadSizeOutput(t *testing.T) {
	x := &fakeExecer{outputs: []string{"not-a-number"}}
	_, err := pgCheckQuotas(context.Background(), x, "c", []TenantQuota{{Slug: "app1", CapBytes: 1}})
	if err == nil {
		t.Fatal("want error for unparseable size")
	}
}

func TestValidSlugRejectsInjection(t *testing.T) {
	if validSlug(`x"; DROP ROLE postgres; --`) {
		t.Fatal("injection slug accepted")
	}
}

func TestValidSlugAcceptsPluginRegexShape(t *testing.T) {
	valid := []string{"a", "app1", "my-app_1", strings.Repeat("a", 31)}
	for _, s := range valid {
		if !validSlug(s) {
			t.Errorf("want %q valid", s)
		}
	}
	invalid := []string{"", "1app", "App", "app!", strings.Repeat("a", 32), "a b"}
	for _, s := range invalid {
		if validSlug(s) {
			t.Errorf("want %q invalid", s)
		}
	}
}

func TestValidSlugDeniesReservedSystemDatabases(t *testing.T) {
	reserved := []string{"postgres", "template0", "template1"}
	for _, s := range reserved {
		if validSlug(s) {
			t.Errorf("want %q denied (reserved system database)", s)
		}
	}
}
