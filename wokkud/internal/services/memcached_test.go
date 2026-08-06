package services

import (
	"context"
	"strings"
	"testing"
)

const memcachedDump = `key=app1%3Asession%3A1 exp=-1 la=1 cas=1 fetch=no cls=1 size=100 flags=0
key=app1%3Acart exp=-1 la=1 cas=2 fetch=no cls=1 size=250 flags=0
key=other%3Akey exp=-1 la=1 cas=3 fetch=no cls=1 size=999 flags=0
END`

// Provision is a wire no-op: memcached has no users or ACLs, a tenant is a
// key-prefix convention — nothing to exec, nothing that can already exist.
func TestMemcachedProvisionTenantIsNoOp(t *testing.T) {
	x := &fakeExecer{}
	res, err := memcachedProvisionTenant(context.Background(), x, "dokku-shared-memcached",
		TenantProvisionParams{Slug: "app1", Password: "ignored"})
	if err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
	if res["key_prefix"] != "app1:" {
		t.Fatalf("got %+v", res)
	}
}

func TestMemcachedProvisionTenantRejectsInvalidSlug(t *testing.T) {
	if _, err := memcachedProvisionTenant(context.Background(), &fakeExecer{}, "c",
		TenantProvisionParams{Slug: "Bad Slug"}); err == nil {
		t.Fatal("want error for invalid slug")
	}
}

func TestMemcachedDestroyTenantPurgesPrefixOnly(t *testing.T) {
	x := &fakeExecer{outputs: []string{memcachedDump, ""}}
	if err := memcachedDestroyTenant(context.Background(), x, "dokku-shared-memcached", "app1"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 2 { // metadump, then batched deletes
		t.Fatalf("want 2 execs, got %d", len(x.calls))
	}
	if x.calls[0].stdin != "lru_crawler metadump all\r\nquit\r\n" {
		t.Fatalf("metadump payload wrong: %q", x.calls[0].stdin)
	}
	del := x.calls[1].stdin
	if !strings.Contains(del, "delete app1:session:1") || !strings.Contains(del, "delete app1:cart") {
		t.Fatalf("URL-decoded tenant keys not deleted: %q", del)
	}
	if strings.Contains(del, "other:key") {
		t.Fatalf("foreign tenant key deleted: %q", del)
	}
	if got := x.calls[1].cmd; got[0] != "nc" {
		t.Fatalf("want nc inside container, got %v", got)
	}
}

// A metadump key decoding to CRLF/space bytes must be SKIPPED, not written
// into the delete payload — a tenant-crafted key could otherwise smuggle
// commands (flush_all) into the batch.
func TestMemcachedPurgeSkipsProtocolInjectingKeys(t *testing.T) {
	dump := "key=app1%3Aok exp=-1 la=1 cas=1 fetch=no cls=1 size=10 flags=0\n" +
		"key=app1%3Aevil%0D%0Aflush_all%0D%0Adelete%20x exp=-1 la=1 cas=2 fetch=no cls=1 size=10 flags=0\n" +
		"key=app1%3Awith%20space exp=-1 la=1 cas=3 fetch=no cls=1 size=10 flags=0\nEND"
	x := &fakeExecer{outputs: []string{dump, ""}}
	if err := memcachedDestroyTenant(context.Background(), x, "dokku-shared-memcached", "app1"); err != nil {
		t.Fatal(err)
	}
	del := x.calls[1].stdin
	if !strings.Contains(del, "delete app1:ok") {
		t.Fatalf("valid key not deleted: %q", del)
	}
	if strings.Contains(del, "flush_all") || strings.Contains(del, "with space") {
		t.Fatalf("injecting key reached the payload: %q", del)
	}
}

// A tenant with no keys destroys cleanly — one metadump, no delete round.
func TestMemcachedDestroyTenantNoKeysTolerant(t *testing.T) {
	x := &fakeExecer{outputs: []string{"END"}}
	if err := memcachedDestroyTenant(context.Background(), x, "c", "ghost"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 1 {
		t.Fatalf("want 1 exec (metadump only), got %d", len(x.calls))
	}
}

func TestMemcachedCheckQuotasSumsAndFlushesOverCap(t *testing.T) {
	x := &fakeExecer{outputs: []string{memcachedDump, ""}}
	got, err := memcachedCheckQuotas(context.Background(), x, "dokku-shared-memcached", []TenantQuota{
		{Slug: "app1", CapBytes: 300}, // 100+250=350 > 300 -> over, flushed
		{Slug: "other", CapBytes: 5000},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !got[0].Over || got[0].SizeBytes != 350 || got[0].ReadOnly {
		t.Fatalf("got %+v", got[0]) // memcached has no read-only state; enforcement = flush
	}
	if got[1].Over || got[1].SizeBytes != 999 {
		t.Fatalf("got %+v", got[1])
	}
	if len(x.calls) != 2 { // ONE metadump for the sweep + one purge for the over tenant
		t.Fatalf("want 2 execs, got %d", len(x.calls))
	}
	if !strings.Contains(x.calls[1].stdin, "delete app1:") {
		t.Fatalf("over-cap tenant not flushed: %q", x.calls[1].stdin)
	}
}

func TestMemcachedCheckQuotasRejectsInvalidSlug(t *testing.T) {
	x := &fakeExecer{}
	if _, err := memcachedCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "bad slug!", CapBytes: 1}}); err == nil {
		t.Fatal("want error for invalid slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
}
