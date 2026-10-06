package services

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func redisCmdLine(c execCall) string { return strings.Join(c.cmd, " ") }

func TestRedisProvisionTenantSequence(t *testing.T) {
	x := &fakeExecer{outputs: []string{"", "OK", "OK"}} // GETUSER empty = user missing
	res, err := redisProvisionTenant(context.Background(), x, "dokku-shared-redis",
		TenantProvisionParams{Slug: "app1", Password: "s3cret", QuotaMB: 25, MaxConns: 40})
	if err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 3 {
		t.Fatalf("want 3 execs (GETUSER, SETUSER, SAVE), got %d", len(x.calls))
	}
	wantFrags := []string{
		"ACL GETUSER app1",
		"ACL SETUSER app1 on >s3cret ~app1:* nocommands +@all -@admin -@dangerous +info",
		"ACL SAVE",
	}
	for i, frag := range wantFrags {
		if !strings.Contains(redisCmdLine(x.calls[i]), frag) {
			t.Errorf("call %d missing %q, got %v", i, frag, x.calls[i].cmd)
		}
		if x.calls[i].container != "dokku-shared-redis" {
			t.Errorf("call %d container = %q", i, x.calls[i].container)
		}
	}
	if res["key_prefix"] != "app1:" || res["user"] != "app1" {
		t.Fatalf("got %+v", res)
	}
}

func TestRedisProvisionTenantExistsSentinel(t *testing.T) {
	x := &fakeExecer{outputs: []string{"flags\non allkeys\npasswords\n..."}} // GETUSER non-empty = exists
	_, err := redisProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "app1", Password: "pw"})
	if !errors.Is(err, errTenantExists) {
		t.Fatalf("want errTenantExists, got %v", err)
	}
	if len(x.calls) != 1 {
		t.Fatalf("want to stop after GETUSER, got %d calls", len(x.calls))
	}
}

func TestRedisProvisionTenantRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	if _, err := redisProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "bad slug!", Password: "pw"}); err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
}

// redis-cli exits 0 even when the server rejects the command — the reply
// prefix is the only failure signal (broke the plugin's check-quotas in
// v0.1.0, so it's load-bearing here too).
func TestRedisAdminDetectsErrReply(t *testing.T) {
	x := &fakeExecer{outputs: []string{"ERR unknown command 'ACLX'"}}
	if _, err := runRedisAdmin(context.Background(), x, "c", "ACLX"); err == nil {
		t.Fatal("want error for ERR reply")
	}
	x = &fakeExecer{outputs: []string{"NOPERM this user has no permissions"}}
	if _, err := runRedisAdmin(context.Background(), x, "c", "GET", "k"); err == nil {
		t.Fatal("want error for NOPERM reply")
	}
}

// The admin wrapper must never carry the admin password in argv — it is
// discovered in-container (env or /data/redis.conf) by the sh script.
func TestRedisAdminWrapperShape(t *testing.T) {
	x := &fakeExecer{}
	if _, err := runRedisAdmin(context.Background(), x, "c", "ACL", "SAVE"); err != nil {
		t.Fatal(err)
	}
	cmd := x.calls[0].cmd
	if cmd[0] != "sh" || cmd[1] != "-c" || !strings.Contains(cmd[2], "redis-cli") {
		t.Fatalf("got %v", cmd)
	}
	if cmd[len(cmd)-2] != "ACL" || cmd[len(cmd)-1] != "SAVE" {
		t.Fatalf("args not appended: %v", cmd)
	}
}

func TestRedisDestroyTenantSequence(t *testing.T) {
	x := &fakeExecer{outputs: []string{"42", "1", "OK"}}
	if err := redisDestroyTenant(context.Background(), x, "dokku-shared-redis", "app1"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 3 {
		t.Fatalf("want 3 execs (EVAL purge, DELUSER, SAVE), got %d", len(x.calls))
	}
	if !strings.Contains(redisCmdLine(x.calls[0]), "EVAL") || !strings.Contains(redisCmdLine(x.calls[0]), "app1:*") {
		t.Errorf("purge call wrong: %v", x.calls[0].cmd)
	}
	if !strings.Contains(redisCmdLine(x.calls[1]), "ACL DELUSER app1") {
		t.Errorf("deluser call wrong: %v", x.calls[1].cmd)
	}
}

// ACL DELUSER on a missing user replies 0 — destroy of an already-gone
// tenant succeeds without special-casing.
func TestRedisDestroyTenantNotFoundTolerant(t *testing.T) {
	x := &fakeExecer{outputs: []string{"0", "0", "OK"}}
	if err := redisDestroyTenant(context.Background(), x, "c", "ghost"); err != nil {
		t.Fatal(err)
	}
}

func TestRedisDestroyTenantRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	if err := redisDestroyTenant(context.Background(), x, "c", "bad slug!"); err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
}

func TestRedisCheckQuotasOverCapFlipsReadOnly(t *testing.T) {
	x := &fakeExecer{outputs: []string{"3 999999999", "OK", "OK"}}
	got, err := redisCheckQuotas(context.Background(), x, "dokku-shared-redis",
		[]TenantQuota{{Slug: "app1", CapBytes: 26214400}})
	if err != nil {
		t.Fatal(err)
	}
	if !got[0].Over || got[0].SizeBytes != 999999999 || !got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	if !strings.Contains(redisCmdLine(x.calls[1]), "ACL SETUSER app1 nocommands +@read +@connection -@admin -@dangerous +info +del +unlink") {
		t.Fatalf("flip call wrong: %v", x.calls[1].cmd)
	}
}

func TestRedisCheckQuotasUnderCapRestoresFull(t *testing.T) {
	x := &fakeExecer{outputs: []string{"3 1000", "OK", "OK"}}
	got, err := redisCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 26214400}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].Over || got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	if !strings.Contains(redisCmdLine(x.calls[1]), "ACL SETUSER app1 nocommands +@all -@admin -@dangerous +info") {
		t.Fatalf("flip call wrong: %v", x.calls[1].cmd)
	}
}

// The plugin's --no-raw EVAL wrapped the reply in quotes — parsing must
// survive both quoted and bare "keys bytes" shapes.
func TestRedisCheckQuotasParsesQuotedUsage(t *testing.T) {
	x := &fakeExecer{outputs: []string{`"7 2048"`, "OK", "OK"}}
	got, err := redisCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 26214400}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].SizeBytes != 2048 {
		t.Fatalf("got %+v", got[0])
	}
}

func TestRedisCheckQuotasBadUsageOutput(t *testing.T) {
	x := &fakeExecer{outputs: []string{"garbage"}}
	if _, err := redisCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 1}}); err == nil {
		t.Fatal("want error for unparseable usage")
	}
}
