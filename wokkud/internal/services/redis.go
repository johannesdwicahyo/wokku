package services

import (
	"context"
	"fmt"
	"strconv"
	"strings"
)

// redisPwDiscovery sets $pw to the parent's admin password, found
// IN-CONTAINER (no host-side .admin_password file): REDIS_PASSWORD env, else
// the requirepass line in /data/redis.conf (wokkud's dedicated create writes
// it; for the adopted plugin parent the operator pins it there — that parent
// loads an --aclfile whose `default` user shipped `nopass ~* +@all`,
// reachable unauthenticated from every app on wokku-services, 2026-10-06;
// redis-server never reads this file, the --aclfile does the enforcing).
// Empty → no auth. Its --requirepass argv is NOT discoverable: redis
// rewrites its process title, so /proc/1/cmdline shows "redis-server *:6379".
const redisPwDiscovery = `pw="${REDIS_PASSWORD:-}"
if [ -z "$pw" ] && [ -f /data/redis.conf ]; then pw="$(sed -n 's/^requirepass //p' /data/redis.conf)"; fi
`

// redisAdminWrapper execs redis-cli as the parent's admin. The password
// never crosses into argv, so it can't leak through exec error strings.
const redisAdminWrapper = redisPwDiscovery + `if [ -n "$pw" ]; then exec redis-cli --no-auth-warning -a "$pw" "$@"; fi
exec redis-cli --no-auth-warning "$@"`

// Lua scripts copied verbatim from dokku-shared-redis/functions —
// tenant_usage returns "<key_count> <memory_bytes>", purge_tenant_keys
// deletes every key matching the tenant prefix. Single round trip each.
const redisUsageLua = `local c='0' local n=0 local s=0 repeat local r=redis.call('SCAN',c,'MATCH',KEYS[1],'COUNT',1000) c=r[1] for i,k in ipairs(r[2]) do n=n+1 s=s+(tonumber(redis.call('MEMORY','USAGE',k)) or 0) end until c=='0' return n..' '..s`
const redisPurgeLua = `local c='0' local n=0 repeat local r=redis.call('SCAN',c,'MATCH',KEYS[1],'COUNT',1000) c=r[1] for i,k in ipairs(r[2]) do redis.call('DEL',k) n=n+1 end until c=='0' return n`

// runRedisAdmin execs redis-cli as admin inside the parent container.
// redis-cli exits 0 even when the server rejects the command (ACL syntax
// error, NOPERM, ...) — the plugin greps reply prefixes to catch that, and
// so do we.
func runRedisAdmin(ctx context.Context, x execer, container string, args ...string) (string, error) {
	cmd := append([]string{"sh", "-c", redisAdminWrapper, "redis-cli"}, args...)
	out, err := x.Exec(ctx, container, "", cmd...)
	if err != nil {
		return out, err
	}
	for _, line := range strings.Split(out, "\n") {
		l := strings.TrimSpace(line)
		for _, p := range []string{"ERR ", "WRONGPASS", "NOPERM", "NOAUTH", "(error)"} {
			if strings.HasPrefix(l, p) {
				return out, fmt.Errorf("redis: %s", l)
			}
		}
	}
	return out, nil
}

// Tenant command grants. The key pattern (~slug:*) only fences commands
// that NAME keys — keyless ones (FLUSHALL, CONFIG SET, ACL SETUSER, SHUTDOWN,
// KEYS) reach every tenant on the shared parent, so they must never be
// granted (the plugin-era +@all did). Each set starts with `nocommands`
// because ACL SETUSER is additive: re-granting without a reset would keep
// whatever an earlier flip allowed. +info: client libs (ioredis ready
// check, BullMQ) call it on connect and it is @dangerous only for leaking
// server stats.
var (
	redisTenantGrants = []string{"nocommands", "+@all", "-@admin", "-@dangerous", "+info"}
	// Over quota: read-only, but DEL/UNLINK stay so the tenant can free
	// space and get back under (the next sweep restores redisTenantGrants).
	redisOverQuotaGrants = []string{"nocommands", "+@read", "+@connection", "-@admin", "-@dangerous", "+info", "+del", "+unlink"}
)

// redisProvisionTenant creates the tenant ACL user, translated from the
// plugin's service_create: login on, password, keys scoped to "<slug>:*",
// redisTenantGrants, persisted via ACL SAVE. QuotaMB/MaxConns are
// accepted per the op params contract but unused (quota enforcement is
// redisCheckQuotas's job; redis has no per-user connection limit knob here).
func redisProvisionTenant(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
	if !validSlug(p.Slug) {
		return nil, fmt.Errorf("invalid tenant slug: %q", p.Slug)
	}
	// ACL SETUSER is an upsert — it can't report "already exists", so probe
	// first (the plugin used a host metadata dir for this; we ask Redis:
	// GETUSER on a missing user prints nothing).
	out, err := runRedisAdmin(ctx, x, container, "ACL", "GETUSER", p.Slug)
	if err != nil {
		return nil, fmt.Errorf("acl getuser: %w", err)
	}
	if strings.TrimSpace(out) != "" {
		return nil, fmt.Errorf("tenant %q: %w", p.Slug, errTenantExists)
	}
	args := append([]string{"ACL", "SETUSER", p.Slug, "on", ">" + p.Password, "~" + p.Slug + ":*"}, redisTenantGrants...)
	if _, err := runRedisAdmin(ctx, x, container, args...); err != nil {
		return nil, fmt.Errorf("acl setuser: %w", err)
	}
	if _, err := runRedisAdmin(ctx, x, container, "ACL", "SAVE"); err != nil {
		return nil, fmt.Errorf("acl save: %w", err)
	}
	return map[string]string{"slug": p.Slug, "user": p.Slug, "key_prefix": p.Slug + ":"}, nil
}

// redisDestroyTenant purges the tenant's keys and deletes its ACL user,
// translated from the plugin's service_destroy. ACL DELUSER on a missing
// user returns 0 (no error) — not-found tolerance comes for free.
func redisDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}
	if _, err := runRedisAdmin(ctx, x, container, "EVAL", redisPurgeLua, "1", slug+":*"); err != nil {
		return fmt.Errorf("purge keys: %w", err)
	}
	if _, err := runRedisAdmin(ctx, x, container, "ACL", "DELUSER", slug); err != nil {
		return fmt.Errorf("acl deluser: %w", err)
	}
	if _, err := runRedisAdmin(ctx, x, container, "ACL", "SAVE"); err != nil {
		return fmt.Errorf("acl save: %w", err)
	}
	return nil
}

// redisCheckQuotas measures each tenant's key count + memory via the
// plugin's EVAL usage script and applies the ACL read-only flip in the same
// pass (plugin's acl_set_readonly/acl_set_full), unconditionally like
// pgCheckQuotas — no host-side QUOTA_VIOLATED marker. Only the byte cap is
// enforced: the control plane sends cap_bytes; the plugin's separate
// key-count cap was not ported (TenantQuota has no keys field).
func redisCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		if !validSlug(t.Slug) {
			return nil, fmt.Errorf("invalid tenant slug: %q", t.Slug)
		}
		out, err := runRedisAdmin(ctx, x, container, "EVAL", redisUsageLua, "1", t.Slug+":*")
		if err != nil {
			return nil, fmt.Errorf("usage %q: %w", t.Slug, err)
		}
		fields := strings.Fields(strings.ReplaceAll(out, `"`, ""))
		if len(fields) != 2 {
			return nil, fmt.Errorf("usage %q: unexpected output %q", t.Slug, out)
		}
		size, err := strconv.ParseInt(fields[1], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse usage %q: %w", t.Slug, err)
		}

		over := size > t.CapBytes
		grants := redisTenantGrants
		if over {
			grants = redisOverQuotaGrants
		}
		flip := append([]string{"ACL", "SETUSER", t.Slug}, grants...)
		if _, err := runRedisAdmin(ctx, x, container, flip...); err != nil {
			return nil, fmt.Errorf("quota flip %q: %w", t.Slug, err)
		}
		if _, err := runRedisAdmin(ctx, x, container, "ACL", "SAVE"); err != nil {
			return nil, fmt.Errorf("acl save %q: %w", t.Slug, err)
		}

		statuses = append(statuses, TenantQuotaStatus{
			Slug:      t.Slug,
			SizeBytes: size,
			CapBytes:  t.CapBytes,
			Over:      over,
			ReadOnly:  over,
		})
	}
	return statuses, nil
}
