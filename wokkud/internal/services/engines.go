package services

import (
	"context"
	"errors"
	"fmt"
	"regexp"
)

// execer is the narrow exec-in-container surface engine handlers need —
// implemented over the Docker SDK once a real handler needs it (dockerAPI in
// executor.go stays a placeholder until then); tests fake it. Mirrors
// dockermon's `api` interface pattern: the smallest shape a caller needs,
// not the full Docker client.
type execer interface {
	Exec(ctx context.Context, container string, stdin string, cmd ...string) (string, error)
}

// TenantQuota is one tenant to check, as supplied by the control plane
// (service.check_quotas op params).
type TenantQuota struct {
	Slug     string `json:"slug"`
	CapBytes int64  `json:"cap_bytes"`
}

// TenantQuotaStatus is the typed per-tenant result of a quota check —
// replaces the plugin bash's QUOTA_LINE regex-parsed text with real JSON.
type TenantQuotaStatus struct {
	Slug      string `json:"slug"`
	SizeBytes int64  `json:"size_bytes"`
	CapBytes  int64  `json:"cap_bytes"`
	Over      bool   `json:"over"`
	ReadOnly  bool   `json:"read_only"`
	// Error is set (and the other fields are zero) when this tenant could
	// not be checked — the sweep continues for the rest. Callers must not
	// read Over from an errored status.
	Error string `json:"error,omitempty"`
}

// errTenantExists is the sentinel for a "role already exists" failure on
// tenant provisioning (reported control-plane-side with error_code
// "tenant_exists" — wiring that maps this sentinel to the report call is a
// separate task; not in this file's scope).
var errTenantExists = errors.New("tenant already exists")

// slugRE mirrors dokku-shared-postgres's PLUGIN_NAME_REGEX exactly.
var slugRE = regexp.MustCompile(`^[a-z][a-z0-9_-]{0,30}$`)

// reservedSlugs are PostgreSQL system databases that must never be targeted by
// tenant ops — targeting "postgres", "template0", or "template1" can poison
// the createdb template and break all future tenant provisioning (FORCE is
// dangerous on system DBs). validSlug denies these outright.
var reservedSlugs = map[string]bool{
	"postgres":  true,
	"template0": true,
	"template1": true,
}

// validSlug re-checks control-plane-validated slugs before SQL
// interpolation — belt and suspenders, never trust a network boundary once.
// Returns false for both regex mismatches and reserved system database names.
func validSlug(slug string) bool {
	return !reservedSlugs[slug] && slugRE.MatchString(slug)
}

// sharedTenantEngine bundles the three tenant ops for one shared parent.
// Dispatch key = op.Service — the parent container name Rails sends
// (DatabaseService#container_name is the row's name for shared_host
// parents: "dokku-shared-<engine>").
type sharedTenantEngine struct {
	provision func(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error)
	destroy   func(ctx context.Context, x execer, container, slug string) error
	check     func(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error)
}

var sharedTenantEngines = map[string]sharedTenantEngine{
	sharedPostgresContainer: {
		// pg* keep their Task 7 signatures (and tests) untouched; the
		// closure adapts to the table shape.
		provision: func(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
			if err := pgProvisionTenant(ctx, x, container, p.Slug, p.Password, p.QuotaMB, p.MaxConns); err != nil {
				return nil, err
			}
			return map[string]string{"slug": p.Slug}, nil
		},
		destroy: pgDestroyTenant,
		check:   pgCheckQuotas,
	},
	// rabbitmq + meilisearch removed from the offering 2026-10-05 (zero
	// tenants in prod) — their containers now get the friendly refusal below.
	sharedMariadbContainer:   {provision: mariadbProvisionTenant, destroy: mariadbDestroyTenant, check: mariadbCheckQuotas},
	"dokku-shared-redis":     {provision: redisProvisionTenant, destroy: redisDestroyTenant, check: redisCheckQuotas},
}

// sharedEngineFor resolves the tenant-op handler set for a parent
// container. Unknown containers keep failing with a friendly refusal
// (reported via ReportServiceOp, same as every other handler error).
func sharedEngineFor(container string) (sharedTenantEngine, error) {
	if e, ok := sharedTenantEngines[container]; ok {
		return e, nil
	}
	return sharedTenantEngine{}, fmt.Errorf("unsupported shared engine: no tenant ops for container %q", container)
}
