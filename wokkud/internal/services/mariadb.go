package services

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Shared MariaDB parent: one container per server, born by wokkud itself on
// the first service.ensure (unlike shared-postgres, which was adopted from
// the dokku plugin). wokkud owns name, image, data path and the root
// credential — the control plane never sees the root password.
const (
	sharedMariadbContainer = "dokku-shared-mariadb"
	// Pinned patch of the 11.4 LTS (newest on Docker Hub 2026-10-05); must
	// stay >= 11.4.2 (mariadb-dump sandbox / newline-in-identifier fix —
	// restores replay tenant-shaped dumps as root).
	sharedMariadbImage    = "mariadb:11.4.13"
	sharedMariadbMemoryMB = 1024
)

// sharedMariadbDir holds data/ (bind-mounted to /var/lib/mysql) and
// ROOT_PASSWORD (0600). Under servicesDataRoot's "shared-" subtree, so
// service.destroy can never remove it. var so tests can point it at a tmpdir.
var sharedMariadbDir = "/var/lib/dokku/services/shared-mariadb"

// sharedMariadbCmd sizes the parent for many small tenants: a 384M buffer
// pool inside the 1 GB container limit, 200 global connections (tenants are
// capped at MAX_USER_CONNECTIONS each), utf8mb4 by default.
var sharedMariadbCmd = []string{
	"mariadbd",
	"--innodb-buffer-pool-size=384M",
	"--max-connections=200", // 1 GB budget: per-thread buffers on top of the pool; tenants cap at 40 each
	"--character-set-server=utf8mb4",
	"--collation-server=utf8mb4_unicode_ci",
}

// mariadbReservedSlugs: system schemas and built-in accounts. A tenant slug
// is both a database AND a user name — "root" would let tenant.destroy drop
// root@'%'.
var mariadbReservedSlugs = map[string]bool{
	"mysql": true, "sys": true, "information_schema": true,
	"performance_schema": true, "root": true, "healthcheck": true,
}

func mariadbValidSlug(slug string) bool {
	return validSlug(slug) && !mariadbReservedSlugs[slug]
}

// mariadbAdminWrapper runs the client as root INSIDE the container, reading
// the root password from the container's own env — it never crosses argv or
// the control plane. SQL arrives as $1 (no shell interpolation of it).
const mariadbAdminWrapper = `MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot -N -B -e "$1"`

func mariadbArgs(sql string) []string {
	return []string{"sh", "-c", mariadbAdminWrapper, "mariadb", sql}
}

// mariadbQuote escapes a single-quoted MariaDB string literal (backslash is
// an escape character there, unlike standard SQL).
func mariadbQuote(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), "'", `\'`)
}

// mariadbGrantDB is the slug as a GRANT database pattern: '_' is a wildcard
// in db-level grants, so "my_app" unescaped would also grant on "myxapp".
func mariadbGrantDB(slug string) string {
	return "`" + strings.ReplaceAll(slug, "_", `\_`) + "`.*"
}

func mariadbUser(slug string) string { return "'" + slug + "'@'%'" }

// mariadbProvisionTenant: user (password, per-user connection cap) + utf8mb4
// database + ALL on that database only. QuotaMB is enforced by
// mariadbCheckQuotas, not here (same split as postgres).
func mariadbProvisionTenant(ctx context.Context, x execer, container string, p TenantProvisionParams) (map[string]string, error) {
	if !mariadbValidSlug(p.Slug) {
		return nil, fmt.Errorf("invalid tenant slug: %q", p.Slug)
	}
	maxConns := p.MaxConns
	if maxConns <= 0 {
		maxConns = 40
	}
	createUser := fmt.Sprintf(`CREATE USER %s IDENTIFIED BY '%s' WITH MAX_USER_CONNECTIONS %d;`,
		mariadbUser(p.Slug), mariadbQuote(p.Password), maxConns)
	if _, err := x.Exec(ctx, container, "", mariadbArgs(createUser)...); err != nil {
		// ERROR 1396: Operation CREATE USER failed for 'x'@'%'
		if strings.Contains(err.Error(), "Operation CREATE USER failed") {
			return nil, fmt.Errorf("tenant %q: %w", p.Slug, errTenantExists)
		}
		return nil, fmt.Errorf("create user: %w", err)
	}
	// Review fix 7: a failure after CREATE USER must not strand the user
	// (every retry would hit tenant_exists with no reusable row). Undo only
	// what THIS call created: a CREATE DATABASE failure may mean someone
	// else's database already exists, so that path drops just the user.
	dropUser := fmt.Sprintf("DROP USER IF EXISTS %s;", mariadbUser(p.Slug))
	createDB := fmt.Sprintf("CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", p.Slug)
	if _, err := x.Exec(ctx, container, "", mariadbArgs(createDB)...); err != nil {
		_, _ = x.Exec(ctx, container, "", mariadbArgs(dropUser)...)
		return nil, fmt.Errorf("create database: %w", err)
	}
	grant := fmt.Sprintf("GRANT ALL PRIVILEGES ON %s TO %s;", mariadbGrantDB(p.Slug), mariadbUser(p.Slug))
	if _, err := x.Exec(ctx, container, "", mariadbArgs(grant)...); err != nil {
		_ = mariadbDestroyTenant(ctx, x, container, p.Slug) // we created both
		return nil, fmt.Errorf("grant: %w", err)
	}
	return map[string]string{"slug": p.Slug, "user": p.Slug, "database": p.Slug}, nil
}

// mariadbDestroyTenant drops the tenant's database and user; IF EXISTS makes
// an already-gone tenant a success (compensation paths rely on it).
func mariadbDestroyTenant(ctx context.Context, x execer, container, slug string) error {
	if !mariadbValidSlug(slug) {
		return fmt.Errorf("invalid tenant slug: %q", slug)
	}
	if _, err := x.Exec(ctx, container, "", mariadbArgs(fmt.Sprintf("DROP DATABASE IF EXISTS `%s`;", slug))...); err != nil {
		return fmt.Errorf("drop database: %w", err)
	}
	if _, err := x.Exec(ctx, container, "", mariadbArgs(fmt.Sprintf("DROP USER IF EXISTS %s;", mariadbUser(slug)))...); err != nil {
		return fmt.Errorf("drop user: %w", err)
	}
	return nil
}

// mariadbCheckQuotas: MariaDB has no per-database size cap, so measure
// data_length+index_length from information_schema and flip privileges in
// the same pass, unconditionally (like pgCheckQuotas).
//   - over:  SELECT, DELETE, DROP, ALTER only (review fix 5) — read and clean
//     up; DROP/TRUNCATE are what actually free InnoDB space. INSERT, UPDATE,
//     CREATE etc. are revoked.
//   - under: ALL restored.
//
// On the sweep that FLIPS a tenant to over (it still held INSERT), its live
// connections are killed (review fix 4): db-level privilege changes only
// reach new connections, so pooled writers would otherwise keep writing.
// A failure on one tenant is reported in that tenant's status and the
// sweep continues (review fix 6) — one stale row can't stall the server.
func mariadbCheckQuotas(ctx context.Context, x execer, container string, tenants []TenantQuota) ([]TenantQuotaStatus, error) {
	statuses := make([]TenantQuotaStatus, 0, len(tenants))
	for _, t := range tenants {
		st, err := mariadbCheckTenant(ctx, x, container, t)
		if err != nil {
			st = TenantQuotaStatus{Slug: t.Slug, CapBytes: t.CapBytes, Error: err.Error()}
		}
		statuses = append(statuses, st)
	}
	return statuses, nil
}

func mariadbCheckTenant(ctx context.Context, x execer, container string, t TenantQuota) (TenantQuotaStatus, error) {
	if !mariadbValidSlug(t.Slug) {
		return TenantQuotaStatus{}, fmt.Errorf("invalid tenant slug: %q", t.Slug)
	}
	// One round trip: size + whether the user can still write (GRANTEE is
	// the quoted account, ''-doubled inside the literal).
	sizeSQL := fmt.Sprintf(`SELECT COALESCE(SUM(data_length + index_length), 0), `+
		`(SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES WHERE GRANTEE = '''%[1]s''@''%%''' AND PRIVILEGE_TYPE = 'INSERT') `+
		`FROM information_schema.tables WHERE table_schema = '%[1]s';`, t.Slug)
	out, err := x.Exec(ctx, container, "", mariadbArgs(sizeSQL)...)
	if err != nil {
		return TenantQuotaStatus{}, fmt.Errorf("size %q: %w", t.Slug, err)
	}
	fields := strings.Fields(out)
	if len(fields) != 2 {
		return TenantQuotaStatus{}, fmt.Errorf("size %q: unexpected output %q", t.Slug, out)
	}
	size, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return TenantQuotaStatus{}, fmt.Errorf("parse size %q: %w", t.Slug, err)
	}
	writable := fields[1] != "0"

	over := size > t.CapBytes
	db, user := mariadbGrantDB(t.Slug), mariadbUser(t.Slug)
	flip := fmt.Sprintf("GRANT ALL PRIVILEGES ON %s TO %s;", db, user)
	if over {
		// The leading GRANT guarantees a db-level grant row exists, so
		// REVOKE ALL can never fail with "no such grant".
		flip = fmt.Sprintf("GRANT SELECT ON %[1]s TO %[2]s; REVOKE ALL PRIVILEGES ON %[1]s FROM %[2]s; GRANT SELECT, DELETE, DROP, ALTER ON %[1]s TO %[2]s;", db, user)
	}
	if _, err := x.Exec(ctx, container, "", mariadbArgs(flip)...); err != nil {
		return TenantQuotaStatus{}, fmt.Errorf("quota flip %q: %w", t.Slug, err)
	}
	if over && writable {
		if _, err := x.Exec(ctx, container, "", mariadbArgs(fmt.Sprintf("KILL USER %s;", user))...); err != nil {
			return TenantQuotaStatus{}, fmt.Errorf("kill connections %q: %w", t.Slug, err)
		}
	}
	return TenantQuotaStatus{Slug: t.Slug, SizeBytes: size, CapBytes: t.CapBytes, Over: over, ReadOnly: over}, nil
}

// ensureSharedMariadb (re)creates the missing shared parent. ROOT_PASSWORD
// is the "this parent was born" marker:
//   - no marker, no data  → first boot: mint the root password, create.
//   - marker, data dir    → recreate on the intact data (password from file).
//   - marker, no data dir → data_dir_missing: tenants' data is gone, that is
//     a human's restore decision (same refusal as shared-postgres).
//   - data but no marker  → refuse: never boot over data we can't log into.
func ensureSharedMariadb(ctx context.Context, d dockerAPI) (EnsureResult, error) {
	dataDir := filepath.Join(sharedMariadbDir, "data")
	pw, born := readMetaFile(sharedMariadbDir, "ROOT_PASSWORD")
	action := "recreated"
	switch {
	case !born && dataDirNonEmpty(dataDir):
		return EnsureResult{}, fmt.Errorf("%s has data at %q but no ROOT_PASSWORD — refusing to boot over it", sharedMariadbContainer, dataDir)
	case !born:
		// Order matters (review fix 1): pull the image and create the data
		// dir BEFORE the marker. A failed pull then leaves nothing behind
		// (retry = first boot again), and once the marker exists its data
		// dir does too — "marker but no data dir" stays a genuine data loss.
		if err := d.ImageEnsure(ctx, sharedMariadbImage); err != nil {
			return EnsureResult{}, fmt.Errorf("image: %w", err)
		}
		if err := os.MkdirAll(dataDir, 0o700); err != nil {
			return EnsureResult{}, err
		}
		buf := make([]byte, 16)
		if _, err := rand.Read(buf); err != nil {
			return EnsureResult{}, err
		}
		pw = hex.EncodeToString(buf)
		// Written BEFORE anything boots: a container must never hold a root
		// password wokkud can't recover on the next recreate.
		if err := os.WriteFile(filepath.Join(sharedMariadbDir, "ROOT_PASSWORD"), []byte(pw+"\n"), 0o600); err != nil {
			return EnsureResult{}, err
		}
		action = "created"
	case !dataDirPresent(dataDir):
		return EnsureResult{}, errDataDirMissing(sharedMariadbContainer, dataDir)
	}

	if err := d.ImageEnsure(ctx, sharedMariadbImage); err != nil { // no-op when already pulled
		return EnsureResult{}, fmt.Errorf("image: %w", err)
	}
	if err := d.VolumeCreate(ctx, dataDir); err != nil {
		return EnsureResult{}, fmt.Errorf("volume dir: %w", err)
	}
	if err := d.ContainerCreate(ctx, ContainerSpec{
		Name:  sharedMariadbContainer,
		Image: sharedMariadbImage,
		// root@localhost only (review fix 8): no root@'%' reachable from app
		// tasks on the overlay. Admin execs use the in-container socket.
		Env:  []string{"MARIADB_ROOT_PASSWORD=" + pw, "MARIADB_ROOT_HOST=localhost"},
		Bind: dataDir + ":/var/lib/mysql",
		Cmd:  sharedMariadbCmd,
	}); err != nil {
		return EnsureResult{}, fmt.Errorf("container create: %w", err)
	}
	// Overlay WITH the alias: tenant DSNs use the container name as host.
	if err := d.NetworkEnsure(ctx, "wokku-services"); err != nil {
		return EnsureResult{}, fmt.Errorf("overlay ensure: %w", err)
	}
	if err := d.NetworkConnect(ctx, "wokku-services", sharedMariadbContainer, sharedMariadbContainer); err != nil {
		return EnsureResult{}, fmt.Errorf("overlay attach: %w", err)
	}
	if err := d.ContainerStart(ctx, sharedMariadbContainer); err != nil {
		return EnsureResult{}, fmt.Errorf("start: %w", err)
	}
	if err := d.ContainerUpdate(ctx, sharedMariadbContainer, sharedMariadbMemoryMB, 0); err != nil {
		return EnsureResult{}, fmt.Errorf("memory limit: %w", err)
	}
	if err := waitMariadbReady(ctx, d); err != nil {
		return EnsureResult{}, err
	}
	return EnsureResult{Running: true, Action: action}, nil
}

// waitMariadbReady polls over TCP on purpose: the entrypoint's first-boot
// temp server runs --skip-networking, so a socket ping can succeed and then
// die when the entrypoint restarts mysqld. TCP only answers once the real
// server is up — tenant.provision right after ensure must not race init.
// No credentials: root is localhost-only, and `mariadb-admin ping` exits 0
// whenever the server answers, even with "Access denied" (documented).
func waitMariadbReady(ctx context.Context, d dockerAPI) error {
	probe := []string{"mariadb-admin", "-h127.0.0.1", "--protocol=tcp", "ping"}
	var err error
	for attempt := 0; attempt <= setConnsRetryAttempts; attempt++ {
		if _, err = d.Exec(ctx, sharedMariadbContainer, "", probe...); err == nil {
			return nil
		}
		time.Sleep(setConnsRetryInterval)
	}
	return fmt.Errorf("%s not ready: %w", sharedMariadbContainer, err)
}
