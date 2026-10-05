// ops.go is the op.Kind -> handler dispatch: decode op.Params by kind, route
// to the right typed function (Task 7's shared-postgres pg* functions or
// this task's dedicated.go functions), and translate a handful of
// known-failure sentinels into typed error_codes the control plane can act
// on. Every kind either has a case here or falls through to executor.go's
// stubHandler (unregistered kind -> "unsupported op kind" failure) —
// nothing panics, nothing returns an error upward past dispatchRunner.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"wokku.cloud/wokkud/internal/control"
)

// Op params structs, copied verbatim from spec §4
// (docs/superpowers/specs/2026-07-09-track-b-phase-b4-datastores.md).

type CreateParams struct { // "service.create"
	ServiceType string  `json:"service_type"` // postgres|redis|mariadb|mongodb|shared parents
	Image       string  `json:"image"`        // e.g. "postgres:16-alpine"
	MemoryMB    int     `json:"memory_mb"`
	CPU         float64 `json:"cpu"` // 0 = unlimited/unchanged
	MaxConns    int     `json:"max_connections"`
	Network     string  `json:"network"`
	VolumePath  string  `json:"volume_path"` // host dir, created 0700
	AdminPass   string  `json:"admin_pass"`  // control-plane-generated
	Database    string  `json:"database"`    // Task 10: application DB to create on first boot (POSTGRES_DB/MARIADB_DATABASE/MONGO_INITDB_DATABASE); "" = none (redis)
}
type AdoptParams struct{}     // "service.adopt" — inspect + return AdoptResult
type LifecycleParams struct{} // "service.start" | "service.stop" | "service.restart" | "service.destroy" (destroy: params {"force": true} required)
type SetLimitsParams struct { // "service.set_limits" — docker update + ALTER SYSTEM, then restart if engine requires
	MemoryMB int     `json:"memory_mb"`
	CPU      float64 `json:"cpu"` // 0 = unlimited/unchanged
	MaxConns int     `json:"max_connections"`
}
type TenantProvisionParams struct { // "tenant.provision" (shared parents only)
	Slug     string `json:"slug"`
	Password string `json:"password"` // control-plane-generated
	QuotaMB  int    `json:"quota_mb"`
	MaxConns int    `json:"max_connections"` // default 40 (Solid Queue pools)
}
type TenantDestroyParams struct {
	Force bool   `json:"force"`
	Slug  string `json:"slug"` // control plane sends the tenant slug explicitly — op.Service is the parent container name, never a slug (C1)
} // "tenant.destroy"
type TenantQuotaParams struct {
	QuotaMB int    `json:"quota_mb"`
	Slug    string `json:"slug"` // same C1 contract as tenant.destroy: op.Service is the parent container, never a slug
}                              // "tenant.set_quota"
type QuotaCheckParams struct { // "service.check_quotas" — control plane is the metadata owner
	// (spec §3 #1): the tenant list + caps come from Rails
	// (SharedDatabaseQuotaJob), not host QUOTA_MB files — those never get
	// written for tenants provisioned via tenant.provision, which made them
	// permanently invisible to the sweep.
	Tenants []TenantQuota `json:"tenants"`
}

// AdoptResult is service.adopt's report body (spec §4's example).
type AdoptResult struct {
	Image   string          `json:"image"`
	Volume  string          `json:"volume"`
	Network string          `json:"network"`
	Running bool            `json:"running"`
	EnvDSN  string          `json:"env_dsn"`
	Tenants []AdoptedTenant `json:"tenants,omitempty"`
}

type AdoptedTenant struct {
	Slug          string `json:"slug"`
	Role          string `json:"role"`
	Database      string `json:"database"`
	Password      string `json:"password"`
	QuotaMB       int    `json:"quota_mb"`
	QuotaViolated bool   `json:"quota_violated"`
}

// opError carries a typed error_code through dispatchRunner's
// ReportServiceOp call (executor.go unwraps it via errors.As). Plain errors
// stay error_code "" — only the handful of failures a caller needs to
// branch on programmatically (tenant_exists, service_destroy_needs_force)
// get one.
type opError struct {
	code string
	err  error
}

func (e *opError) Error() string { return e.err.Error() }
func (e *opError) Unwrap() error { return e.err }

func typedFail(code string, err error) error { return &opError{code: code, err: err} }

// errDestroyNeedsForce backs both tenant.destroy and service.destroy's
// force gate (carry-forward from the Task 7 review): the DROP function
// itself is unguarded by design, so the gate has to live here, before the
// handler that would actually drop anything is ever called.
var errDestroyNeedsForce = errors.New("destroy requires force: true")

const errCodeDestroyNeedsForce = "service_destroy_needs_force"
const errCodeTenantExists = "tenant_exists"

func init() {
	for _, kind := range []string{
		"service.create", "service.adopt", "service.start", "service.stop",
		"service.restart", "service.destroy", "service.set_limits", "service.check_quotas",
		"service.ensure", "service.export", "service.import",
		"tenant.provision", "tenant.destroy", "tenant.set_quota",
	} {
		handlers[kind] = runOp
	}
}

// runOp is the single dispatch point registered for every kind this task
// owns. docker (dockerAPI) satisfies execer too (same Exec method
// signature), so it's passed straight through to Task 7's pg* functions
// without an adapter.
func runOp(ctx context.Context, client *control.Client, docker dockerAPI, op *queuedOp) (any, error) {
	switch op.kind {
	case "service.create":
		var p CreateParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		// Fresh create only — service.ensure's recreate path calls
		// serviceCreate directly and REQUIRES existing data. This op-level
		// guard is the inverse: booting an engine over leftover data keeps
		// the old credentials against the new DSN (chatwoot, 2026-07-22).
		if dataDirNonEmpty(p.VolumePath) {
			return nil, typedFail("data_dir_exists",
				fmt.Errorf("%s already has data at %q — destroy it (removes data) or restore instead of re-creating over it", op.service, p.VolumePath))
		}
		if err := serviceCreate(ctx, docker, op.service, p); err != nil {
			return nil, typedFail("service_create_failed", err)
		}
		return map[string]string{"container": op.service}, nil

	case "service.adopt":
		result, err := serviceAdopt(ctx, docker, op.service)
		if err != nil {
			return nil, err
		}
		return result, nil

	case "service.start":
		if err := docker.ContainerStart(ctx, op.service); err != nil {
			return nil, err
		}
		return map[string]string{"status": "running"}, nil

	case "service.stop":
		if err := docker.ContainerStop(ctx, op.service); err != nil {
			return nil, err
		}
		return map[string]string{"status": "stopped"}, nil

	case "service.restart":
		if err := docker.ContainerRestart(ctx, op.service); err != nil {
			return nil, err
		}
		return map[string]string{"status": "running"}, nil

	case "service.destroy":
		var p struct {
			Force bool `json:"force"`
		}
		_ = json.Unmarshal(op.params, &p) // malformed/absent params -> force stays false, gate still fires
		if !p.Force {
			return nil, typedFail(errCodeDestroyNeedsForce, errDestroyNeedsForce)
		}
		if err := serviceDestroy(ctx, docker, op.service); err != nil {
			return nil, err
		}
		return map[string]string{"status": "destroyed"}, nil

	case "service.set_limits":
		var p SetLimitsParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		serviceType := serviceTypeFromContainerName(op.service)
		if err := serviceSetLimits(ctx, docker, op.service, serviceType, p.MemoryMB, p.MaxConns, p.CPU); err != nil {
			return nil, err
		}
		return map[string]string{"status": "applied"}, nil

	case "service.check_quotas":
		var p QuotaCheckParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		eng, err := sharedEngineFor(op.service)
		if err != nil {
			return nil, err
		}
		statuses, err := eng.check(ctx, docker, op.service, p.Tenants)
		if err != nil {
			return nil, typedFail("quota_check_failed", err)
		}
		return map[string]any{"tenants": statuses}, nil

	case "service.ensure":
		var p CreateParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		res, err := serviceEnsure(ctx, docker, op.service, p)
		if err != nil {
			if strings.HasPrefix(err.Error(), "data_dir_missing:") {
				return nil, typedFail("data_dir_missing", err)
			}
			return nil, typedFail("service_ensure_failed", err)
		}
		return res, nil

	case "service.export":
		var p ExportParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		n, err := runExport(ctx, docker, op.service, p)
		if err != nil {
			return nil, typedFail("service_export_failed", err)
		}
		return map[string]any{"bytes": n}, nil

	case "service.import":
		var p ImportParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		n, err := runImport(ctx, docker, op.service, p)
		if err != nil {
			return nil, typedFail("service_import_failed", err)
		}
		return map[string]any{"bytes": n}, nil

	case "tenant.provision":
		var p TenantProvisionParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		eng, err := sharedEngineFor(op.service)
		if err != nil {
			return nil, err
		}
		result, err := eng.provision(ctx, docker, op.service, p)
		if err != nil {
			if errors.Is(err, errTenantExists) {
				return nil, typedFail(errCodeTenantExists, err)
			}
			return nil, err
		}
		return result, nil

	case "tenant.destroy":
		var p TenantDestroyParams
		_ = json.Unmarshal(op.params, &p) // malformed/absent params -> Force stays false, gate still fires
		if !p.Force {
			return nil, typedFail(errCodeDestroyNeedsForce, errDestroyNeedsForce)
		}
		eng, err := sharedEngineFor(op.service)
		if err != nil {
			return nil, err
		}
		// op.service is the PARENT container name (C1), never the tenant
		// slug — the slug travels in params only.
		if err := eng.destroy(ctx, docker, op.service, p.Slug); err != nil {
			return nil, err
		}
		return map[string]string{"status": "destroyed"}, nil

	case "tenant.set_quota":
		var p TenantQuotaParams
		if err := json.Unmarshal(op.params, &p); err != nil {
			return nil, fmt.Errorf("decode params: %w", err)
		}
		// B4 gate 6 (other half of C1): op.service is the PARENT container
		// name — using it as the slug silently targeted a nonexistent
		// tenant. The slug must travel in params, like tenant.destroy.
		if !validSlug(p.Slug) {
			return nil, typedFail("bad_slug", fmt.Errorf("tenant.set_quota requires params.slug (got %q)", p.Slug))
		}
		eng, err := sharedEngineFor(op.service)
		if err != nil {
			return nil, err
		}
		statuses, err := eng.check(ctx, docker, op.service,
			[]TenantQuota{{Slug: p.Slug, CapBytes: int64(p.QuotaMB) * 1024 * 1024}})
		if err != nil {
			return nil, typedFail("quota_check_failed", err)
		}
		if statuses[0].Error != "" { // per-tenant failure (mariadb continues sweeps)
			return nil, typedFail("quota_check_failed", errors.New(statuses[0].Error))
		}
		return statuses[0], nil

	default:
		return nil, fmt.Errorf("unknown kind: %q", op.kind)
	}
}
