package services

import (
	"context"
	"errors"
	"strings"
	"testing"
)

const meiliEmptyKeys = `{"results":[],"offset":0,"limit":1000,"total":0}`

func TestMeiliProvisionTenantSequence(t *testing.T) {
	x := &fakeExecer{outputs: []string{
		meiliEmptyKeys,
		`{"uid":"u-rw","key":"k-rw","actions":["search"],"indexes":["app1-*"]}`,
		`{"uid":"u-ro","key":"k-ro","actions":["search"],"indexes":["app1-*"]}`,
	}}
	res, err := meiliProvisionTenant(context.Background(), x, "dokku-shared-meilisearch",
		TenantProvisionParams{Slug: "app1", Password: "unused"})
	if err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 3 { // list keys, create rw, create ro
		t.Fatalf("want 3 execs, got %d", len(x.calls))
	}
	// key bodies travel on stdin (curl --data @-), never argv
	if !strings.Contains(x.calls[1].stdin, `"app1-*"`) || !strings.Contains(x.calls[1].stdin, "documents.add") {
		t.Fatalf("rw key body wrong: %q", x.calls[1].stdin)
	}
	if strings.Contains(x.calls[2].stdin, "documents.add") || !strings.Contains(x.calls[2].stdin, "search") {
		t.Fatalf("ro key body must be read-only actions: %q", x.calls[2].stdin)
	}
	// master key comes from container env inside sh -c, never argv
	joined := strings.Join(x.calls[1].cmd, " ")
	if !strings.Contains(joined, "$MEILI_MASTER_KEY") {
		t.Fatalf("master key not sourced from container env: %v", x.calls[1].cmd)
	}
	want := map[string]string{
		"api_key": "k-rw", "api_key_uid": "u-rw",
		"api_key_ro": "k-ro", "api_key_ro_uid": "u-ro",
		"index_prefix": "app1-",
	}
	for k, v := range want {
		if res[k] != v {
			t.Errorf("res[%q] = %q, want %q", k, res[k], v)
		}
	}
}

func TestMeiliProvisionTenantExistsSentinel(t *testing.T) {
	x := &fakeExecer{outputs: []string{
		`{"results":[{"uid":"u1","key":"k1","indexes":["app1-*"]}]}`,
	}}
	_, err := meiliProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "app1"})
	if !errors.Is(err, errTenantExists) {
		t.Fatalf("want errTenantExists, got %v", err)
	}
	if len(x.calls) != 1 {
		t.Fatalf("want to stop after key list, got %d calls", len(x.calls))
	}
}

// Hyphens are forbidden for meilisearch slugs: "foo"'s "foo-*" key pattern
// would match "foo-bar"'s indexes — cross-tenant leak (plugin config note).
func TestMeiliProvisionTenantRejectsHyphenSlug(t *testing.T) {
	x := &fakeExecer{}
	if _, err := meiliProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "foo-bar"}); err == nil {
		t.Fatal("want error for hyphenated slug")
	}
	if len(x.calls) != 0 {
		t.Fatalf("want no execs, got %d", len(x.calls))
	}
}

func TestMeiliProvisionTenantKeyCreateFailureIsError(t *testing.T) {
	x := &fakeExecer{outputs: []string{
		meiliEmptyKeys,
		`{"message":"invalid actions","code":"invalid_api_key_actions"}`,
	}}
	if _, err := meiliProvisionTenant(context.Background(), x, "c",
		TenantProvisionParams{Slug: "app1"}); err == nil {
		t.Fatal("want error when key creation returns no key")
	}
}

func TestMeiliDestroyTenantDeletesKeysAndIndexes(t *testing.T) {
	x := &fakeExecer{outputs: []string{
		`{"results":[{"uid":"u-rw","key":"k","indexes":["app1-*"]},{"uid":"u-other","key":"k2","indexes":["other-*"]}]}`,
		"", // DELETE /keys/u-rw
		`{"results":[{"uid":"app1-products"},{"uid":"otherapp"}]}`,
		"", // DELETE /indexes/app1-products
	}}
	if err := meiliDestroyTenant(context.Background(), x, "dokku-shared-meilisearch", "app1"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 4 {
		t.Fatalf("want 4 execs, got %d", len(x.calls))
	}
	if !strings.Contains(strings.Join(x.calls[1].cmd, " "), "/keys/u-rw") {
		t.Fatalf("wrong key deleted: %v", x.calls[1].cmd)
	}
	if !strings.Contains(strings.Join(x.calls[3].cmd, " "), "/indexes/app1-products") {
		t.Fatalf("wrong index deleted: %v", x.calls[3].cmd)
	}
}

func TestMeiliDestroyTenantNothingToDeleteTolerant(t *testing.T) {
	x := &fakeExecer{outputs: []string{meiliEmptyKeys, `{"results":[]}`}}
	if err := meiliDestroyTenant(context.Background(), x, "c", "ghost"); err != nil {
		t.Fatal(err)
	}
	if len(x.calls) != 2 { // list keys, list indexes — no deletes
		t.Fatalf("want 2 execs, got %d", len(x.calls))
	}
}

func TestMeiliCheckQuotasSumsIndexStats(t *testing.T) {
	x := &fakeExecer{outputs: []string{
		`{"results":[{"uid":"app1-products"},{"uid":"app1-users"},{"uid":"other-idx"}]}`,
		`{"numberOfDocuments":10,"rawDocumentDbSize":60000000}`,
		`{"numberOfDocuments":5,"rawDocumentDbSize":50000000}`,
	}}
	got, err := meiliCheckQuotas(context.Background(), x, "dokku-shared-meilisearch",
		[]TenantQuota{{Slug: "app1", CapBytes: 104857600}})
	if err != nil {
		t.Fatal(err)
	}
	// 110MB > 100MB cap -> over; ReadOnly stays false (enforcement = the
	// control plane swapping linked apps onto api_key_ro, not a host op)
	if !got[0].Over || got[0].SizeBytes != 110000000 || got[0].ReadOnly {
		t.Fatalf("got %+v", got[0])
	}
	if len(x.calls) != 3 { // list indexes + 2 stats (foreign index skipped)
		t.Fatalf("want 3 execs, got %d", len(x.calls))
	}
}

func TestMeiliCheckQuotasNoIndexesUnder(t *testing.T) {
	x := &fakeExecer{outputs: []string{`{"results":[]}`}}
	got, err := meiliCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 100}})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].Over || got[0].SizeBytes != 0 {
		t.Fatalf("got %+v", got[0])
	}
}

func TestMeiliCheckQuotasBadJSONIsError(t *testing.T) {
	x := &fakeExecer{outputs: []string{"<html>bad gateway</html>"}}
	if _, err := meiliCheckQuotas(context.Background(), x, "c",
		[]TenantQuota{{Slug: "app1", CapBytes: 100}}); err == nil {
		t.Fatal("want error for non-JSON response")
	}
}
