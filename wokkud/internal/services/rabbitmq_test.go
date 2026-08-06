package services

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestRabbitProvisionTenantSequence(t *testing.T) {
	x := &fakeExecer{}
	res, err := rabbitProvisionTenant(context.Background(), x, "dokku-shared-rabbitmq",
		TenantProvisionParams{Slug: "app1", Password: "s3cret"})
	if err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 3 {
		t.Fatalf("want 3 execs (add_vhost, add_user, set_permissions), got %d", len(x.calls))
	}
	wantFrags := []string{
		"rabbitmqctl add_vhost app1",
		"rabbitmqctl add_user app1 s3cret",
		"rabbitmqctl set_permissions -p app1 app1 .* .* .*",
	}
	for i, frag := range wantFrags {
		if !strings.Contains(strings.Join(x.calls[i].cmd, " "), frag) {
			t.Errorf("call %d missing %q, got %v", i, frag, x.calls[i].cmd)
		}
		if x.calls[i].container != "dokku-shared-rabbitmq" {
			t.Errorf("call %d container = %q", i, x.calls[i].container)
		}
	}
	if res["vhost"] != "app1" || res["user"] != "app1" {
		t.Fatalf("got %+v", res)
	}
}

// A leftover vhost from a half-finished provision is tolerated — the USER is
// the credential step, so user_already_exists is the tenant_exists signal.
func TestRabbitProvisionTenantVhostExistsTolerated(t *testing.T) {
	x := &fakeExecer{errs: []error{errors.New("Error: vhost_already_exists: app1")}}
	if _, err := rabbitProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "app1", Password: "pw"}); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 3 {
		t.Fatalf("want provision to continue past existing vhost, got %d calls", len(x.calls))
	}
}

func TestRabbitProvisionTenantUserExistsSentinel(t *testing.T) {
	x := &fakeExecer{errs: []error{nil, errors.New("Error: user_already_exists: app1")}}
	_, err := rabbitProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "app1", Password: "pw"})
	if !errors.Is(err, errTenantExists) {
		t.Fatalf("want errTenantExists, got %v", err)
	}
	if len(x.calls) != 2 {
		t.Fatalf("want to stop after failing add_user, got %d calls", len(x.calls))
	}
}

func TestRabbitProvisionTenantRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	if _, err := rabbitProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "bad slug!"}); err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
}

func TestRabbitDestroyTenantSequence(t *testing.T) {
	x := &fakeExecer{}
	if err := rabbitDestroyTenant(context.Background(), x, "dokku-shared-rabbitmq", "app1"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 2 {
		t.Fatalf("want 2 execs (delete_user, delete_vhost), got %d", len(x.calls))
	}
	if !strings.Contains(strings.Join(x.calls[0].cmd, " "), "delete_user app1") ||
		!strings.Contains(strings.Join(x.calls[1].cmd, " "), "delete_vhost app1") {
		t.Fatalf("got %v", x.calls)
	}
}

func TestRabbitDestroyTenantNotFoundTolerant(t *testing.T) {
	x := &fakeExecer{errs: []error{
		errors.New("Error: no_such_user: ghost"),
		errors.New("Error: no_such_vhost: ghost"),
	}}
	if err := rabbitDestroyTenant(context.Background(), x, "c", "ghost"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 2 {
		t.Fatalf("want both deletes attempted, got %d", len(x.calls))
	}
}

// Unlike the plugin's blanket `|| true`, a broker that's actually broken
// still fails loud.
func TestRabbitDestroyTenantRealErrorPropagates(t *testing.T) {
	x := &fakeExecer{errs: []error{errors.New("Error: unable to connect to node rabbit@host")}}
	if err := rabbitDestroyTenant(context.Background(), x, "c", "app1"); err == nil {
		t.Fatal("want broker error to propagate")
	}
}

func TestRabbitCheckQuotasSumsMessagesAndFlipsWrite(t *testing.T) {
	// header junk + two queues; cap_bytes carries the MESSAGE cap for rabbitmq
	x := &fakeExecer{outputs: []string{"Listing queues ...\nq1\t70\nq2\t50\n", ""}}
	got, err := rabbitCheckQuotas(context.Background(), x, "dokku-shared-rabbitmq",
		[]TenantQuota{{Slug: "app1", CapBytes: 100}})
	if err != nil {
		t.Fatal(err)
	}
	if !got[0].Over || got[0].SizeBytes != 120 || !got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	flip := x.calls[1].cmd
	// write regex must be the EMPTY string (revoke write, keep configure/read)
	want := []string{"rabbitmqctl", "set_permissions", "-p", "app1", "app1", ".*", "", ".*"}
	if len(flip) != len(want) {
		t.Fatalf("got %v", flip)
	}
	for i := range want {
		if flip[i] != want[i] {
			t.Fatalf("flip arg %d = %q, want %q", i, flip[i], want[i])
		}
	}
}

func TestRabbitCheckQuotasUnderCapRestoresWrite(t *testing.T) {
	x := &fakeExecer{outputs: []string{"q1\t5\n", ""}}
	got, err := rabbitCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 100}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].Over || got[0].ReadOnly || got[0].SizeBytes != 5 {
		t.Fatalf("got %+v", got[0])
	}
	if !strings.Contains(strings.Join(x.calls[1].cmd, " "), "set_permissions -p app1 app1 .* .* .*") {
		t.Fatalf("got %v", x.calls[1].cmd)
	}
}

func TestRabbitCheckQuotasEmptyVhostCountsZero(t *testing.T) {
	x := &fakeExecer{outputs: []string{"", ""}}
	got, err := rabbitCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 100}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].SizeBytes != 0 || got[0].Over {
		t.Fatalf("got %+v", got[0])
	}
}
