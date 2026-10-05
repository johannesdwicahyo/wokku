package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

// EnsureResult is service.ensure's report body. Action is "none" (already
// present) or "recreated" (was missing, rebuilt on intact data).
type EnsureResult struct {
	Running bool   `json:"running"`
	Action  string `json:"action"`
}

// sharedPostgresImage pins the shared parent's image — its data is PG_VERSION
// 16 and the 2026-07-21 recovery used postgres:16-alpine. A pin (not a param)
// because the shared parent has no control-plane-stored image (the row carries
// none); wokkud owns this fact the same way it owns the name and data path.
const sharedPostgresImage = "postgres:16-alpine"

// serviceEnsure is the idempotent supervision primitive: if the container
// exists (running OR stopped) it is a no-op — RestartPolicyAlways owns
// crash/stop recovery and ensure must never fight it. If it is MISSING, ensure
// recreates it FROM ITS INTACT DATA — but refuses when the data dir is absent
// (a missing data dir is a louder failure than a missing container; silently
// running an empty engine would re-init and orphan the tenants' expectations —
// that is a human's restore decision, not ensure's). Credentials never appear
// here: recreate is data + run-spec only.
func serviceEnsure(ctx context.Context, d dockerAPI, name string, p CreateParams) (EnsureResult, error) {
	exists, err := d.ContainerExists(ctx, name)
	if err != nil {
		return EnsureResult{}, fmt.Errorf("inspect %s: %w", name, err)
	}
	if exists {
		// A present container must also be REACHABLE: Swarm tasks resolve
		// datastore hosts only on the wokku-services overlay, and the
		// dokku-era shared parents were born on their own bridges (native
		// apps couldn't reach shared-redis until a manual attach,
		// 2026-07-22). Idempotent: inspect-first, attach only when absent,
		// container name as alias (load-bearing for the shared-pg parent).
		attached, err := ensureOverlayAttachment(ctx, d, name)
		if err != nil {
			return EnsureResult{}, fmt.Errorf("overlay attach %s: %w", name, err)
		}
		if attached {
			return EnsureResult{Running: true, Action: "attached"}, nil
		}
		return EnsureResult{Running: true, Action: "none"}, nil
	}

	if name == sharedPostgresContainer {
		return ensureSharedParent(ctx, d)
	}
	if name == sharedMariadbContainer {
		return ensureSharedMariadb(ctx, d)
	}
	return ensureDedicated(ctx, d, name, p)
}

// dataDirPresent guards the recreate: a populated data dir means "start the
// existing cluster"; an absent one is the refuse case.
func dataDirPresent(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// dataDirNonEmpty is create's inverse guard: a FRESH create must never boot
// over existing data — the engine skips init on a populated dir and keeps
// the OLD credentials while the control plane hands out new ones (chatwoot's
// redis auth failure, 2026-07-22). Ensure requires data; create requires none.
func dataDirNonEmpty(path string) bool {
	if path == "" {
		return false
	}
	entries, err := os.ReadDir(path)
	return err == nil && len(entries) > 0
}

func ensureDedicated(ctx context.Context, d dockerAPI, name string, p CreateParams) (EnsureResult, error) {
	if !dataDirPresent(p.VolumePath) {
		return EnsureResult{}, errDataDirMissing(name, p.VolumePath)
	}
	// serviceCreate recreates on the intact data (the engine image skips init
	// on a populated data dir and just starts the existing cluster), attaches
	// p.Network, starts, and re-applies limits. The data-dir guard above is
	// the only thing serviceCreate lacks for the ensure contract.
	if err := serviceCreate(ctx, d, name, p); err != nil {
		return EnsureResult{}, fmt.Errorf("recreate %s: %w", name, err)
	}
	return EnsureResult{Running: true, Action: "recreated"}, nil
}

func ensureSharedParent(ctx context.Context, d dockerAPI) (EnsureResult, error) {
	dataDir := filepath.Join(sharedPostgresMetaDir, "_pgdata")
	if !dataDirPresent(dataDir) {
		return EnsureResult{}, errDataDirMissing(sharedPostgresContainer, dataDir)
	}
	if err := d.ImageEnsure(ctx, sharedPostgresImage); err != nil {
		return EnsureResult{}, fmt.Errorf("image: %w", err)
	}
	// Recreate exactly as the 2026-07-21 recovery did: bind the intact cluster,
	// no password env (the superuser already lives in the data dir; postgres
	// ignores POSTGRES_PASSWORD on a non-empty PGDATA anyway), restart-always.
	if err := d.ContainerCreate(ctx, ContainerSpec{
		Name:  sharedPostgresContainer,
		Image: sharedPostgresImage,
		Bind:  dataDir + ":/var/lib/postgresql/data",
	}); err != nil {
		return EnsureResult{}, fmt.Errorf("container create: %w", err)
	}
	// Its own bridge (tenants adopted pre-Swarm), then the wokku-services
	// overlay WITH the alias Swarm app tasks resolve. The alias is load-bearing:
	// without it the container comes back but tenants can't reach it.
	if err := d.NetworkConnect(ctx, sharedPostgresContainer, sharedPostgresContainer); err != nil {
		return EnsureResult{}, fmt.Errorf("bridge attach: %w", err)
	}
	if err := d.NetworkEnsure(ctx, "wokku-services"); err != nil {
		return EnsureResult{}, fmt.Errorf("overlay ensure: %w", err)
	}
	if err := d.NetworkConnect(ctx, "wokku-services", sharedPostgresContainer, sharedPostgresContainer); err != nil {
		return EnsureResult{}, fmt.Errorf("overlay attach: %w", err)
	}
	if err := d.ContainerStart(ctx, sharedPostgresContainer); err != nil {
		return EnsureResult{}, fmt.Errorf("start: %w", err)
	}
	return EnsureResult{Running: true, Action: "recreated"}, nil
}

// ensureOverlayAttachment connects an existing container to the
// wokku-services overlay (name as alias) when it isn't already on it.
// Returns whether an attach happened. NetworkEnsure no-ops on the existing
// overlay — same call ensureSharedParent's recreate path makes.
func ensureOverlayAttachment(ctx context.Context, d dockerAPI, name string) (bool, error) {
	info, err := d.ContainerInspect(ctx, name)
	if err != nil {
		return false, err
	}
	for _, n := range info.Networks {
		if n == "wokku-services" {
			return false, nil
		}
	}
	if err := d.NetworkEnsure(ctx, "wokku-services"); err != nil {
		return false, err
	}
	if err := d.NetworkConnect(ctx, "wokku-services", name, name); err != nil {
		return false, err
	}
	return true, nil
}

// errDataDirMissing → error_code "data_dir_missing": the container is gone AND
// its data dir is absent. The control plane maps this to "needs restore", never
// to a silent recreate.
func errDataDirMissing(name, path string) error {
	return fmt.Errorf("data_dir_missing: %s has no data dir at %q — refusing to init an empty engine", name, path)
}
