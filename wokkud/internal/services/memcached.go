package services

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// runMemcachedAdmin speaks the memcached text protocol to the shared parent
// via busybox nc INSIDE the container against loopback (dokku-shared-
// memcached's run_memcached_admin). Payload on stdin; `quit` closes the
// connection so nc exits cleanly.
func runMemcachedAdmin(ctx context.Context, x execer, container, payload string) (string, error) {
	return x.Exec(ctx, container, payload+"\r\nquit\r\n", "nc", "-w", "2", "127.0.0.1", "11211")
}

type memcachedKey struct {
	key  string
	size int64
}

// memcachedMetadump walks every LRU via `lru_crawler metadump all` (the
// plugin's tenant_scan — `stats cachedump` is unreliable in modern
// memcached) and returns decoded key names + sizes. Keys arrive
// URL-encoded (`tenant%3Ahello`); PathUnescape decodes %XX without
// mangling '+' the way QueryUnescape would.
func memcachedMetadump(ctx context.Context, x execer, container string) ([]memcachedKey, error) {
	out, err := runMemcachedAdmin(ctx, x, container, "lru_crawler metadump all")
	if err != nil {
		return nil, fmt.Errorf("metadump: %w", err)
	}
	var keys []memcachedKey
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "key=") {
			continue
		}
		var k memcachedKey
		for _, f := range strings.Fields(line) {
			if v, ok := strings.CutPrefix(f, "key="); ok {
				if dec, decErr := url.PathUnescape(v); decErr == nil {
					k.key = dec
				} else {
					k.key = v
				}
			} else if v, ok := strings.CutPrefix(f, "size="); ok {
				k.size, _ = strconv.ParseInt(v, 10, 64)
			}
		}
		if k.key != "" {
			keys = append(keys, k)
		}
	}
	return keys, nil
}

// memcachedPurge batch-deletes every dumped key under prefix in one nc
// round trip (plugin's purge_tenant_keys). No keys = no-op.
//
// Keys come %XX-decoded from metadump, so a tenant-crafted key embedding
// CRLF/whitespace could otherwise smuggle extra commands (flush_all…) into
// the payload — skip anything that isn't a valid text-protocol key.
func memcachedPurge(ctx context.Context, x execer, container string, keys []memcachedKey, prefix string) error {
	var b strings.Builder
	for _, k := range keys {
		if strings.HasPrefix(k.key, prefix) && validMemcachedKey(k.key) {
			b.WriteString("delete " + k.key + "\r\n")
		}
	}
	if b.Len() == 0 {
		return nil
	}
	if _, err := runMemcachedAdmin(ctx, x, container, strings.TrimSuffix(b.String(), "\r\n")); err != nil {
		return fmt.Errorf("purge: %w", err)
	}
	return nil
}

// memcached text-protocol keys: 1-250 printable non-space ASCII bytes.
func validMemcachedKey(key string) bool {
	if len(key) == 0 || len(key) > 250 {
		return false
	}
	for i := 0; i < len(key); i++ {
		if key[i] <= ' ' || key[i] > '~' {
			return false
		}
	}
	return true
}

// memcachedProvisionTenant is deliberately a no-op on the wire.
// ponytail: memcached has no users, ACLs, or namespaces — the plugin's
// "tenant" was only a key-prefix convention plus host metadata files we no
// longer keep. Isolation = the app prefixing its keys with "<slug>:"; the
// endpoint is the shared container. Nothing to create, and nothing that can
// "already exist" — this engine has no tenant_exists sentinel.
func memcachedProvisionTenant(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
	if !validSlug(p.Slug) {
		return nil, fmt.Errorf("invalid tenant slug: %q", p.Slug)
	}
	return map[string]string{"slug": p.Slug, "key_prefix": p.Slug + ":"}, nil
}

// memcachedDestroyTenant deletes every key under the tenant prefix
// (plugin's service_destroy minus the metadata dir rm). A tenant with no
// keys destroys cleanly — the metadump simply matches nothing.
func memcachedDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}
	keys, err := memcachedMetadump(ctx, x, container)
	if err != nil {
		return err
	}
	return memcachedPurge(ctx, x, container, keys, slug+":")
}

// memcachedCheckQuotas sums each tenant's dumped-key bytes and, when over
// cap, flushes the tenant's prefix — memcached cannot make a prefix
// read-only, so flushing is the enforcement lever (plugin's
// service_check_quota). One metadump serves the whole sweep (the plugin
// re-scanned per tenant). ReadOnly stays false: there is no read-only state
// to report for this engine.
func memcachedCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	for _, t := range tenants {
		if !validSlug(t.Slug) {
			return nil, fmt.Errorf("invalid tenant slug: %q", t.Slug)
		}
	}
	keys, err := memcachedMetadump(ctx, x, container)
	if err != nil {
		return nil, err
	}
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		prefix := t.Slug + ":"
		var size int64
		for _, k := range keys {
			if strings.HasPrefix(k.key, prefix) {
				size += k.size
			}
		}
		over := size > t.CapBytes
		if over {
			if err := memcachedPurge(ctx, x, container, keys, prefix); err != nil {
				return nil, fmt.Errorf("flush %q: %w", t.Slug, err)
			}
		}
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
