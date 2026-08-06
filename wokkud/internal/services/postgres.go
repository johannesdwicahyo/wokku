package services

import (
	"context"
	"fmt"
	"strconv"
	"strings"
)

// psqlArgs builds the admin psql invocation shared by every shared-postgres
// op, mirroring dokku-shared-postgres/functions run_psql_admin. -t -A
// (unaligned, tuples-only) is harmless on DDL and required for the size
// query, so every call gets it — one arg shape, not two.
func psqlArgs(sql string) []string {
	return []string{"psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", sql}
}

// sqlQuote escapes a single-quoted SQL string literal's embedded quotes
// (standard ” doubling). Slugs never need this (validSlug's regex forbids
// the quote character entirely); password is control-plane-generated but
// not otherwise constrained, so it's the one interpolation that needs it.
func sqlQuote(s string) string {
	return strings.ReplaceAll(s, "'", "''")
}

// pgProvisionTenant creates a tenant role + database on the shared postgres
// container, translated from dokku-shared-postgres's service_create. quotaMB
// is accepted (matches the control-plane op params contract) but unused here
// — quota enforcement is pgCheckQuotas's job, not provisioning's.
func pgProvisionTenant(ctx context.Context, x execer, container, slug, password string, quotaMB, maxConns int) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}

	createRole := fmt.Sprintf(`CREATE ROLE "%s_role" LOGIN PASSWORD '%s' CONNECTION LIMIT %d;`, slug, sqlQuote(password), maxConns)
	if _, err := x.Exec(ctx, container, "", psqlArgs(createRole)...); err != nil {
		if strings.Contains(err.Error(), "already exists") {
			return fmt.Errorf("tenant %q: %w", slug, errTenantExists)
		}
		return fmt.Errorf("create role: %w", err)
	}

	createDB := fmt.Sprintf(`CREATE DATABASE "%s" OWNER "%s_role";`, slug, slug)
	if _, err := x.Exec(ctx, container, "", psqlArgs(createDB)...); err != nil {
		return fmt.Errorf("create database: %w", err)
	}

	revoke := fmt.Sprintf(`REVOKE CONNECT ON DATABASE "%s" FROM PUBLIC;`, slug)
	if _, err := x.Exec(ctx, container, "", psqlArgs(revoke)...); err != nil {
		return fmt.Errorf("revoke public connect: %w", err)
	}

	return nil
}

// pgDestroyTenant drops a tenant's database and role, translated from
// dokku-shared-postgres's service_destroy (WITH (FORCE) added so an active
// session on the database doesn't block the drop).
func pgDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}

	dropDB := fmt.Sprintf(`DROP DATABASE IF EXISTS "%s" WITH (FORCE);`, slug)
	if _, err := x.Exec(ctx, container, "", psqlArgs(dropDB)...); err != nil {
		return fmt.Errorf("drop database: %w", err)
	}

	dropRole := fmt.Sprintf(`DROP ROLE IF EXISTS "%s_role";`, slug)
	if _, err := x.Exec(ctx, container, "", psqlArgs(dropRole)...); err != nil {
		return fmt.Errorf("drop role: %w", err)
	}

	return nil
}

// pgSetQuota flips a tenant database's read-only flag. There's no host
// state anymore (quota_mb lives control-plane-side) — this op exists purely
// to apply the on/off decision it's told, mirroring the plugin's
// service_check_quota ALTER but without the QUOTA_MB/marker file bookkeeping.
func pgSetQuota(ctx context.Context, x execer, container, slug string, readOnly bool) error {
	if !validSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}
	onOff := "off"
	if readOnly {
		onOff = "on"
	}
	sql := fmt.Sprintf(`ALTER DATABASE "%s" SET default_transaction_read_only = %s;`, slug, onOff)
	if _, err := x.Exec(ctx, container, "", psqlArgs(sql)...); err != nil {
		return fmt.Errorf("set read-only %s: %w", onOff, err)
	}
	return nil
}

// pgCheckQuotas measures each tenant's database size and enforces the
// read-only flip in the same pass, translated from the plugin's
// service_check_quota — but returns typed results instead of the bash
// version's QUOTA_LINE regex-parsed text, and applies the flip
// unconditionally (over -> on, under -> off) since there's no host-side
// marker file to track "already flipped".
func pgCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		if !validSlug(t.Slug) {
			return nil, fmt.Errorf("invalid tenant slug: %q", t.Slug)
		}

		sizeSQL := fmt.Sprintf(`SELECT pg_database_size('%s');`, t.Slug)
		out, err := x.Exec(ctx, container, "", psqlArgs(sizeSQL)...)
		if err != nil {
			return nil, fmt.Errorf("size %q: %w", t.Slug, err)
		}
		size, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse size %q: %w", t.Slug, err)
		}

		over := size > t.CapBytes
		if err := pgSetQuota(ctx, x, container, t.Slug, over); err != nil {
			return nil, err
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
