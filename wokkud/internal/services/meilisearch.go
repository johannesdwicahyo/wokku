package services

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

// Action sets for the two per-tenant keys, copied from
// dokku-shared-meilisearch. The full key deliberately excludes keys.* (a
// tenant must never mint keys) and dumps/snapshots (host-level).
var meiliRWActions = []string{"search", "documents.add", "documents.get", "documents.delete", "indexes.create", "indexes.get", "indexes.update", "indexes.delete", "settings.get", "settings.update", "stats.get", "tasks.get"}
var meiliROActions = []string{"search", "documents.get", "indexes.get", "stats.get"}

// runMeiliAdmin performs a Meilisearch REST call as the master key,
// executing curl INSIDE the container over localhost (the plugin's
// run_meilisearch_admin). The master key comes from the container's own
// MEILI_MASTER_KEY env, expanded in-container by sh — never from host state
// and never through argv, so it can't leak into exec error strings.
func runMeiliAdmin(ctx context.Context, x execer, container, method, path, body string) (string, error) {
	script := `exec curl -sS -X "$1" -H "Authorization: Bearer $MEILI_MASTER_KEY" "http://localhost:7700$2"`
	if body != "" {
		script = `exec curl -sS -X "$1" -H "Authorization: Bearer $MEILI_MASTER_KEY" -H "Content-Type: application/json" --data @- "http://localhost:7700$2"`
	}
	return x.Exec(ctx, container, body, "sh", "-c", script, "curl", method, path)
}

// meiliValidSlug adds the plugin's stricter rule on top of validSlug:
// hyphen is FORBIDDEN because '-' is the index separator and Meilisearch
// key index patterns are pure prefix matches — tenant "foo"'s "foo-*" key
// would read "foo-bar"'s indexes (cross-tenant leak).
func meiliValidSlug(slug string) bool {
	return validSlug(slug) && !strings.Contains(slug, "-")
}

type meiliKey struct {
	UID     string   `json:"uid"`
	Key     string   `json:"key"`
	Indexes []string `json:"indexes"`
}

// meiliTenantKeys lists the API keys scoped to exactly ["<slug>-*"] — the
// no-host-state replacement for the plugin's KEY_*_UID files: the index
// pattern itself identifies the tenant's keys.
func meiliTenantKeys(ctx context.Context, x execer, container, slug string) ([]meiliKey, error) {
	out, err := runMeiliAdmin(ctx, x, container, "GET", "/keys?limit=1000", "")
	if err != nil {
		return nil, fmt.Errorf("list keys: %w", err)
	}
	var list struct {
		Results []meiliKey `json:"results"`
	}
	if err := json.Unmarshal([]byte(out), &list); err != nil {
		return nil, fmt.Errorf("list keys: unexpected response %q", out)
	}
	pattern := slug + "-*"
	var matched []meiliKey
	for _, k := range list.Results {
		if len(k.Indexes) == 1 && k.Indexes[0] == pattern {
			matched = append(matched, k)
		}
	}
	return matched, nil
}

func meiliCreateKey(ctx context.Context, x execer, container, slug string, actions []string) (meiliKey, error) {
	body, _ := json.Marshal(map[string]any{
		"actions":   actions,
		"indexes":   []string{slug + "-*"},
		"expiresAt": nil,
	})
	out, err := runMeiliAdmin(ctx, x, container, "POST", "/keys", string(body))
	if err != nil {
		return meiliKey{}, err
	}
	var k meiliKey
	if err := json.Unmarshal([]byte(out), &k); err != nil || k.Key == "" || k.UID == "" {
		return meiliKey{}, fmt.Errorf("key creation failed: %s", out)
	}
	return k, nil
}

// meiliTenantIndexUIDs lists index uids under the tenant's "<slug>-" prefix.
func meiliTenantIndexUIDs(ctx context.Context, x execer, container, slug string) ([]string, error) {
	out, err := runMeiliAdmin(ctx, x, container, "GET", "/indexes?limit=1000", "")
	if err != nil {
		return nil, fmt.Errorf("list indexes: %w", err)
	}
	var list struct {
		Results []struct {
			UID string `json:"uid"`
		} `json:"results"`
	}
	if err := json.Unmarshal([]byte(out), &list); err != nil {
		return nil, fmt.Errorf("list indexes: unexpected response %q", out)
	}
	var uids []string
	for _, r := range list.Results {
		if strings.HasPrefix(r.UID, slug+"-") {
			uids = append(uids, r.UID)
		}
	}
	return uids, nil
}

// meiliProvisionTenant mints the tenant's rw + ro API keys scoped to
// "<slug>-*" (plugin's service_create). Meilisearch generates key values
// server-side (derived from the master key), so unlike the other engines
// the control-plane password in params is UNUSED — the generated keys
// travel back in the op result and Rails composes env/DSN from them.
func meiliProvisionTenant(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
	if !meiliValidSlug(p.Slug) {
		return nil, fmt.Errorf("invalid tenant slug for meilisearch (no hyphens): %q", p.Slug)
	}
	existing, err := meiliTenantKeys(ctx, x, container, p.Slug)
	if err != nil {
		return nil, err
	}
	if len(existing) > 0 {
		return nil, fmt.Errorf("tenant %q: %w", p.Slug, errTenantExists)
	}
	rw, err := meiliCreateKey(ctx, x, container, p.Slug, meiliRWActions)
	if err != nil {
		return nil, fmt.Errorf("create rw key: %w", err)
	}
	ro, err := meiliCreateKey(ctx, x, container, p.Slug, meiliROActions)
	if err != nil {
		// Roll the rw key back so a retry doesn't trip the exists sentinel
		// (plugin's cleanup path).
		_, _ = runMeiliAdmin(ctx, x, container, "DELETE", "/keys/"+rw.UID, "")
		return nil, fmt.Errorf("create ro key: %w", err)
	}
	return map[string]string{
		"slug":           p.Slug,
		"index_prefix":   p.Slug + "-",
		"api_key":        rw.Key,
		"api_key_uid":    rw.UID,
		"api_key_ro":     ro.Key,
		"api_key_ro_uid": ro.UID,
	}, nil
}

// meiliDestroyTenant deletes the tenant's keys (found by index-pattern
// match, not stored uids) and every "<slug>-" index (plugin's
// service_destroy). A tenant with no keys/indexes destroys cleanly.
func meiliDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !meiliValidSlug(slug) {
		return fmt.Errorf("invalid tenant slug for meilisearch (no hyphens): %q", slug)
	}
	keys, err := meiliTenantKeys(ctx, x, container, slug)
	if err != nil {
		return err
	}
	for _, k := range keys {
		if _, err := runMeiliAdmin(ctx, x, container, "DELETE", "/keys/"+k.UID, ""); err != nil {
			return fmt.Errorf("delete key %s: %w", k.UID, err)
		}
	}
	uids, err := meiliTenantIndexUIDs(ctx, x, container, slug)
	if err != nil {
		return err
	}
	for _, uid := range uids {
		if _, err := runMeiliAdmin(ctx, x, container, "DELETE", "/indexes/"+uid, ""); err != nil {
			return fmt.Errorf("delete index %s: %w", uid, err)
		}
	}
	return nil
}

// meiliCheckQuotas sums rawDocumentDbSize across each tenant's "<slug>-"
// indexes (plugin's tenant_usage). MEASUREMENT ONLY: Meilisearch keys are
// immutable, so read-only enforcement = swapping which key the linked apps
// hold (api_key_ro from provision) — that's an app-env change, which is the
// control plane's job, not a host op. ReadOnly always reports false.
func meiliCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		if !meiliValidSlug(t.Slug) {
			return nil, fmt.Errorf("invalid tenant slug for meilisearch (no hyphens): %q", t.Slug)
		}
		uids, err := meiliTenantIndexUIDs(ctx, x, container, t.Slug)
		if err != nil {
			return nil, err
		}
		var size int64
		for _, uid := range uids {
			out, err := runMeiliAdmin(ctx, x, container, "GET", "/indexes/"+uid+"/stats", "")
			if err != nil {
				return nil, fmt.Errorf("stats %s: %w", uid, err)
			}
			var st struct {
				RawDocumentDbSize int64 `json:"rawDocumentDbSize"`
			}
			if err := json.Unmarshal([]byte(out), &st); err != nil {
				return nil, fmt.Errorf("stats %s: unexpected response %q", uid, out)
			}
			size += st.RawDocumentDbSize
		}
		over := size > t.CapBytes
		statuses = append(statuses, TenantQuotaStatus{
			Slug:      t.Slug,
			SizeBytes: size,
			CapBytes:  t.CapBytes,
			Over:      over,
			ReadOnly:  false,
		})
	}
	return statuses, nil
}
