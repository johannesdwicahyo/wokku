package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// dedicatedEngineSpec is the per-engine translation table for
// service.create/set_limits — one row per dedicated engine, no bash. New
// engine = one entry here (spec §10's documented ceiling for Valkey etc).
type dedicatedEngineSpec struct {
	dataPath string // container-side bind mount target
	// env builds the container env from the admin password and, when non-empty,
	// the application database to create on first boot (Task 10). Empty database
	// adds no DB-creation env (redis, or any no-db case).
	env func(adminPass, database string) []string
	// setConnsCmd builds the exec command that applies max_connections;
	// nil = engine has no such knob wired here (redis/mongo cap connections
	// via config, not a runtime SQL statement — out of scope per the brief).
	setConnsCmd          func(n int) []string
	restartAfterSetConns bool // postgres needs a restart for ALTER SYSTEM to take; mariadb's SET GLOBAL doesn't
	// cmd overrides the image CMD (nil = image default). prepare runs host-side
	// after VolumeCreate, before ContainerCreate — for config that must live in
	// the data dir (redis requirepass). adminPass is "" on ensure recreates.
	cmd     []string
	prepare func(volumePath, adminPass string) error
	// minMemoryMB clamps any requested limit up (0 = no floor). Mongo's
	// first-boot init runs mongosh beside mongod; below ~512 MB it is
	// OOM-killed before the root user exists (prod smoke 2026-10-07).
	minMemoryMB int
}

var dedicatedEngines = map[string]dedicatedEngineSpec{
	"postgres": {
		dataPath: "/var/lib/postgresql/data",
		// PGDATA pins the data dir to our bind mount for ALL postgres majors.
		// postgres:18 changed the image default to /var/lib/postgresql/<ver>/docker,
		// so without this an 18 container ignores the mount ("unused mount/volume")
		// and crash-loops on first boot (verified on jkt-01, 2026-07-18). Setting
		// it explicitly is a no-op on 16 (already the default) and lets the image
		// pin bump to 18+ safely.
		env: func(pw, db string) []string {
			e := []string{"POSTGRES_PASSWORD=" + pw, "PGDATA=/var/lib/postgresql/data"}
			if db != "" {
				e = append(e, "POSTGRES_DB="+db)
			}
			return e
		},
		setConnsCmd: func(n int) []string {
			return []string{"psql", "-U", "postgres", "-c", fmt.Sprintf("ALTER SYSTEM SET max_connections = %d;", n)}
		},
		restartAfterSetConns: true,
	},
	"mariadb": {
		dataPath: "/var/lib/mysql",
		// MARIADB_DATABASE is read in the same docker_setup_env as
		// MARIADB_ROOT_PASSWORD and creates the DB (CREATE DATABASE IF NOT
		// EXISTS) during first-boot init regardless of the root password — the
		// documented standard usage.
		env: func(pw, db string) []string {
			e := []string{"MARIADB_ROOT_PASSWORD=" + pw}
			if db != "" {
				e = append(e, "MARIADB_DATABASE="+db)
			}
			return e
		},
		setConnsCmd: func(n int) []string {
			// `SET GLOBAL max_connections` is runtime-only and is lost when the
			// entrypoint restarts mysqld after bootstrap (op reports success,
			// value stays at the 151 default — prod bug 2026-07-17). Persist it
			// in a conf.d file instead, and restartAfterSetConns below makes
			// mysqld read it.
			return mysqlLimitsCmd("mariadb-admin", n)
		},
		restartAfterSetConns: true,
	},
	"mysql": {
		dataPath: "/var/lib/mysql",
		env: func(pw, db string) []string {
			e := []string{"MYSQL_ROOT_PASSWORD=" + pw}
			if db != "" {
				e = append(e, "MYSQL_DATABASE="+db)
			}
			return e
		},
		// Same persisted conf.d file as mariadb (the official mysql image
		// includes /etc/mysql/conf.d from /etc/my.cnf).
		setConnsCmd: func(n int) []string { return mysqlLimitsCmd("mysqladmin", n) },
		restartAfterSetConns: true,
		// MySQL 8/9 defaults idle at ~400 MB+, mostly performance_schema — the
		// reason it was retired 2026-07-09. These flags fit a small box.
		cmd: []string{
			"mysqld",
			"--performance-schema=OFF",
			"--innodb-buffer-pool-size=64M",
			"--innodb-log-buffer-size=8M",
			"--table-open-cache=400",
			"--table-definition-cache=400",
			"--temptable-max-ram=32M",
		},
		// Matches Resources::Shape::ENGINE_MIN_MEMORY_MB (the 512 MB smallest SQL preset).
		minMemoryMB: 512,
	},
	"redis": {
		dataPath: "/data",
		env:      func(pw, db string) []string { return nil }, // redis has no application-database concept; db ignored
		// The official redis image has NO auth env — a stock boot is
		// passwordless while the control-plane DSN advertises a password
		// (chatwoot's AUTH failed against exactly that, 2026-07-22). The
		// password lives in a conf INSIDE the data dir: service.ensure
		// recreates carry no credentials (the databasement boundary), so
		// auth must travel with the data, not the op params.
		cmd: []string{"redis-server", "/data/redis.conf"},
		prepare: func(volumePath, adminPass string) error {
			if adminPass == "" {
				// ensure/recreate: the conf already lives in the intact data dir.
				return nil
			}
			// The control plane generates hex-only passwords, but never trust a
			// network boundary once (validSlug's rule): a newline here would
			// inject arbitrary redis config directives.
			if strings.ContainsAny(adminPass, "\r\n") {
				return fmt.Errorf("admin_pass must not contain newlines")
			}
			return os.WriteFile(filepath.Join(volumePath, "redis.conf"),
				[]byte("requirepass "+adminPass+"\n"), 0o600)
		},
	},
	"mongodb": {
		dataPath:    "/data/db",
		minMemoryMB: 512,
		env: func(pw, db string) []string {
			e := []string{"MONGO_INITDB_ROOT_USERNAME=root", "MONGO_INITDB_ROOT_PASSWORD=" + pw}
			if db != "" {
				e = append(e, "MONGO_INITDB_DATABASE="+db)
			}
			return e
		},
	},
}

// serviceCreate stands up a dedicated datastore container: host volume dir,
// container (bind mount + env + restart-always), network attach, start,
// then memory/conn limits via the same code path as service.set_limits.
// setConnsRetry*: how long serviceSetLimits waits for a freshly started
// engine to accept admin connections (30 × 2s ≈ 60s; postgres initdb on
// slow disks is the ceiling-setter). Interval is a var so tests zero it.
const setConnsRetryAttempts = 30

var setConnsRetryInterval = 2 * time.Second

// mysqlLimitsCmd writes the max_connections conf.d file, but only once the
// server answers on TCP. First boot runs init on a --skip-networking temp
// server and creates root@'%' last; writing + restarting before then (as
// serviceSetLimits does right after start) killed init midway, leaving only
// root@localhost — every app got "Host ... is not allowed to connect"
// (wordpress/bookstack/ghost test deploys, 2026-11-03). `admin ping` exits 0
// even on access denied, so it needs no credentials.
func mysqlLimitsCmd(admin string, n int) []string {
	return []string{"sh", "-c", fmt.Sprintf(
		"for i in $(seq 1 120); do %s --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1 && break; sleep 1; done; "+
			"%s --protocol=tcp -h127.0.0.1 ping >/dev/null 2>&1 || exit 1; "+
			"printf '[mysqld]\\nmax_connections=%d\\n' > /etc/mysql/conf.d/zz-wokku-limits.cnf", admin, admin, n)}
}

// dedicatedAliases: the container name, plus the hyphenated
// `dokku-<type>-<name>` alias the dokku plugins gave their services. Apps
// adopted from dokku still dial that host; without it a recreate (ensure)
// strands them with ENOTFOUND (ghost-uoes, 2026-11-03).
func dedicatedAliases(containerName string) []string {
	aliases := []string{containerName}
	if strings.HasPrefix(containerName, "dokku.") {
		aliases = append(aliases, strings.ReplaceAll(containerName, ".", "-"))
	}
	return aliases
}

func serviceCreate(ctx context.Context, d dockerAPI, containerName string, p CreateParams) error {
	spec, ok := dedicatedEngines[p.ServiceType]
	if !ok {
		return fmt.Errorf("unsupported service_type: %q", p.ServiceType)
	}

	if err := d.ImageEnsure(ctx, p.Image); err != nil {
		return fmt.Errorf("image: %w", err)
	}

	if err := d.VolumeCreate(ctx, p.VolumePath); err != nil {
		return fmt.Errorf("volume dir: %w", err)
	}

	if spec.prepare != nil {
		if err := spec.prepare(p.VolumePath, p.AdminPass); err != nil {
			return fmt.Errorf("prepare data dir: %w", err)
		}
	}

	cs := ContainerSpec{
		Name:  containerName,
		Image: p.Image,
		Env:   spec.env(p.AdminPass, p.Database),
		Cmd:   spec.cmd,
	}
	if p.VolumePath != "" {
		cs.Bind = p.VolumePath + ":" + spec.dataPath
	}
	if err := d.ContainerCreate(ctx, cs); err != nil {
		return fmt.Errorf("container create: %w", err)
	}

	if p.Network != "" {
		// User-defined networks are created on demand ("bridge" always
		// exists and can't be NetworkCreate'd).
		if p.Network != "bridge" {
			if err := d.NetworkEnsure(ctx, p.Network); err != nil {
				return fmt.Errorf("network ensure: %w", err)
			}
		}
		if err := d.NetworkConnect(ctx, p.Network, containerName, dedicatedAliases(containerName)...); err != nil {
			return fmt.Errorf("network connect: %w", err)
		}
	}

	if err := d.ContainerStart(ctx, containerName); err != nil {
		return fmt.Errorf("container start: %w", err)
	}

	return serviceSetLimits(ctx, d, containerName, p.ServiceType, p.MemoryMB, p.MaxConns, p.CPU)
}

// serviceSetLimits mirrors database_resources.rb:27-50 exactly: docker
// update for memory/cpu (skip if both <=0), then the engine's ALTER for
// max_connections (skip if <=0), restarting only when the engine requires
// it (postgres does, mariadb doesn't).
func serviceSetLimits(ctx context.Context, d dockerAPI, containerName, serviceType string, memoryMB, maxConns int, cpu float64) error {
	if floor := dedicatedEngines[serviceType].minMemoryMB; memoryMB > 0 && memoryMB < floor {
		memoryMB = floor
	}
	if memoryMB > 0 || cpu > 0 {
		if err := d.ContainerUpdate(ctx, containerName, memoryMB, cpu); err != nil {
			return fmt.Errorf("update memory: %w", err)
		}
	}
	if maxConns > 0 {
		spec, ok := dedicatedEngines[serviceType]
		if ok && spec.setConnsCmd != nil {
			// A just-started engine may still be initializing (postgres
			// initdb has no socket yet) — retry the first admin exec until
			// it comes up, bounded.
			var err error
			for attempt := 0; attempt <= setConnsRetryAttempts; attempt++ {
				if _, err = d.Exec(ctx, containerName, "", spec.setConnsCmd(maxConns)...); err == nil {
					break
				}
				time.Sleep(setConnsRetryInterval)
			}
			if err != nil {
				return fmt.Errorf("set max_connections: %w", err)
			}
			if spec.restartAfterSetConns {
				if err := d.ContainerRestart(ctx, containerName); err != nil {
					return fmt.Errorf("restart after max_connections: %w", err)
				}
			}
		}
	}
	return nil
}

// serviceDestroy stops and removes the container. It never touches the
// bind-mounted host directory — data deletion is a human decision, not
// something an agent does on its own.
// ponytail: disk cleanup is a human decision, rm -rf never ships in an agent.
// The force gate lives in ops.go's dispatch, not here — by the time this
// runs, the caller has already confirmed force=true.
// servicesDataRoot scopes destroy's data removal — RemoveAll never runs
// outside it, and never on a shared parent's subtree (shared-*: one
// container, many tenants — its data is never one service's to destroy).
// A var so tests can point it at a temp dir.
var servicesDataRoot = "/var/lib/dokku/services/"

// destroyableDataDir reports whether a container bind source is a dedicated
// service's own data dir, safe for destroy to remove. Split out for
// table-testing without a daemon.
func destroyableDataDir(hostPath string) bool {
	rel, ok := strings.CutPrefix(hostPath, servicesDataRoot)
	if !ok || rel == "" {
		return false
	}
	return !strings.HasPrefix(rel, "shared-")
}

func serviceDestroy(ctx context.Context, d dockerAPI, containerName string) error {
	// Capture the bind sources BEFORE removal — the container is the only
	// record of its data dir. Best-effort: an uninspectable container is
	// still removed (today's behavior), just without data cleanup.
	var dataDirs []string
	if info, err := d.ContainerInspect(ctx, containerName); err == nil {
		for _, b := range info.Binds {
			host := strings.SplitN(b, ":", 2)[0]
			if destroyableDataDir(host) {
				dataDirs = append(dataDirs, host)
			}
		}
	}
	if err := d.ContainerStop(ctx, containerName); err != nil {
		return fmt.Errorf("stop: %w", err)
	}
	if err := d.ContainerRemove(ctx, containerName); err != nil {
		return fmt.Errorf("remove: %w", err)
	}
	// Destroy means destroy (dokku parity): keeping the data dir made a
	// same-name recreate boot the OLD credentials against the NEW DSN
	// (chatwoot's redis, 2026-07-22). The empty parent (<type>/<name>/) is
	// swept too — os.Remove is non-recursive, so a non-empty parent stays.
	for _, dir := range dataDirs {
		if err := os.RemoveAll(dir); err != nil {
			return fmt.Errorf("data dir remove: %w", err)
		}
		_ = os.Remove(filepath.Dir(dir))
	}
	return nil
}

// serviceAdopt inspects an existing container and returns everything Rails
// needs to backfill a database_services row — image, volume, network,
// running state, a best-effort DSN, and (for the shared-postgres parent
// only) the tenant metadata files the plugin already writes host-side.
func serviceAdopt(ctx context.Context, d dockerAPI, containerName string) (*AdoptResult, error) {
	info, err := d.ContainerInspect(ctx, containerName)
	if err != nil {
		return nil, fmt.Errorf("inspect: %w", err)
	}

	res := &AdoptResult{
		Image:   info.Image,
		Running: info.Running,
	}
	if len(info.Networks) > 0 {
		res.Network = info.Networks[0]
	}
	if len(info.Binds) > 0 {
		res.Volume = strings.SplitN(info.Binds[0], ":", 2)[0]
	}
	// B4 gate 8: one entry per engine (was postgres-only, leaving adopted
	// mariadb/mysql/mongo rows without a DSN). Formats mirror Rails'
	// compose_dsn exactly. redis has no password env on dokku images —
	// its adopt DSN stays Rails-side (dokku info).
	for _, spec := range adoptDSNEnvs {
		if pw, ok := envValue(info.Env, spec.envKey); ok {
			res.EnvDSN = fmt.Sprintf(spec.format, pw, containerName, containerShortName(containerName))
			break
		}
	}
	if containerName == sharedPostgresContainer {
		res.Tenants = readAdoptedTenants(sharedPostgresMetaDir)
	}
	return res, nil
}

// adoptDSNEnvs maps each engine's root-password env var to the DSN shape
// Rails' compose_dsn builds (database_provisioner.rb).
var adoptDSNEnvs = []struct {
	envKey string
	format string
}{
	{"POSTGRES_PASSWORD", "postgres://postgres:%s@%s:5432/%s"},
	{"MARIADB_ROOT_PASSWORD", "mysql://root:%s@%s:3306/%s"},
	{"MYSQL_ROOT_PASSWORD", "mysql://root:%s@%s:3306/%s"},
	{"MONGO_INITDB_ROOT_PASSWORD", "mongodb://root:%s@%s:27017/%s?authSource=admin"}, // root lives in admin
}

// sharedPostgresContainer is the fixed shared-parent container name (spec
// §2/§4) — a single global container, not one per tenant.
const sharedPostgresContainer = "dokku-shared-postgres"

// sharedPostgresMetaDir is the shared-postgres plugin's host metadata
// directory. var, not const, so tests can point it at a tmpdir.
var sharedPostgresMetaDir = "/var/lib/dokku/services/shared-postgres"

// envValue reads a "KEY=VALUE" entry out of a container's env list.
func envValue(env []string, key string) (string, bool) {
	prefix := key + "="
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, prefix); ok {
			return v, true
		}
	}
	return "", false
}

// containerShortName strips the "dokku.<type>." prefix convention down to
// the bare service name for DSN composition — best-effort cosmetic value,
// never used to route an operation.
func containerShortName(containerName string) string {
	parts := strings.Split(containerName, ".")
	return parts[len(parts)-1]
}

// serviceTypeFromContainerName recovers the engine from the
// "dokku.<type>.<name>" naming convention (database_resources.rb's
// container_name) — set_limits' params carry no service_type of their own,
// so the container name (op.Service) is the only place it's still visible.
// Returns "" for anything that doesn't match (e.g. the shared-postgres
// parent's flat name), which callers treat as "no engine-specific ALTER".
func serviceTypeFromContainerName(containerName string) string {
	parts := strings.SplitN(containerName, ".", 3)
	if len(parts) == 3 && parts[0] == "dokku" {
		return parts[1]
	}
	return ""
}

// readAdoptedTenants enumerates the shared-postgres plugin's per-tenant
// metadata directories. A tenant missing any file is skipped rather than
// failing the whole adopt — degraded-but-partial beats an adopt that can't
// complete because one tenant's files are mid-write.
func readAdoptedTenants(baseDir string) []AdoptedTenant {
	entries, err := os.ReadDir(baseDir)
	if err != nil {
		return nil
	}
	var out []AdoptedTenant
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		slug := e.Name()
		dir := filepath.Join(baseDir, slug)
		password, ok := readMetaFile(dir, "PASSWORD")
		if !ok {
			continue
		}
		role, _ := readMetaFile(dir, "ROLE")
		database, _ := readMetaFile(dir, "DATABASE")
		quotaMBRaw, _ := readMetaFile(dir, "QUOTA_MB")
		quotaMB, _ := strconv.Atoi(quotaMBRaw)
		violatedRaw, _ := readMetaFile(dir, "QUOTA_VIOLATED")

		out = append(out, AdoptedTenant{
			Slug:          slug,
			Role:          role,
			Database:      database,
			Password:      password,
			QuotaMB:       quotaMB,
			QuotaViolated: violatedRaw == "true" || violatedRaw == "1",
		})
	}
	return out
}

func readMetaFile(dir, name string) (string, bool) {
	raw, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(raw)), true
}
