package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEnsureRunningIsNoOp(t *testing.T) {
	f := &fakeDocker{
		existing: map[string]bool{"dokku.postgres.app-db": true},
		inspect:  ContainerInfo{Networks: []string{"wokku-services"}},
	}
	res, err := serviceEnsure(context.Background(), f, "dokku.postgres.app-db", CreateParams{ServiceType: "postgres", VolumePath: "/tmp/x"})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "none" {
		t.Fatalf("present container must be a no-op, got action %q", res.Action)
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "ContainerCreate") || strings.HasPrefix(c, "NetworkConnect") {
			t.Fatalf("no-op must not create or re-attach: %v", f.calls)
		}
	}
}

// A present container OFF the wokku-services overlay gets attached with its
// name as alias — Swarm tasks only resolve datastore hosts there (the
// dokku-era shared parents were born on their own bridges; native apps
// couldn't reach shared-redis until a manual attach, 2026-07-22).
func TestEnsureExistingOffOverlayGetsAttached(t *testing.T) {
	f := &fakeDocker{
		existing: map[string]bool{"dokku-shared-redis": true},
		inspect:  ContainerInfo{Networks: []string{"dokku-shared-redis"}},
	}
	res, err := serviceEnsure(context.Background(), f, "dokku-shared-redis", CreateParams{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "attached" {
		t.Fatalf("want attached, got %q", res.Action)
	}
	want := "NetworkConnect(wokku-services,dokku-shared-redis,aliases=dokku-shared-redis)"
	found := false
	for _, c := range f.calls {
		if c == want {
			found = true
		}
		if strings.HasPrefix(c, "ContainerCreate") {
			t.Fatalf("attach must not recreate: %v", f.calls)
		}
	}
	if !found {
		t.Fatalf("want %q in calls %v", want, f.calls)
	}
}

// TestEnsureContainerExistsErrorNeverRecreates locks down ensure's most
// dangerous failure mode: a docker error from ContainerExists (broken
// socket, daemon hiccup, etc.) must propagate as an error and must NEVER be
// mistaken for "container missing" — that misread would trigger a spurious
// recreate over a healthy, live customer database. This runs every 3
// minutes against real data; there is no safe way to get this wrong.
func TestEnsureContainerExistsErrorNeverRecreates(t *testing.T) {
	f := &fakeDocker{failOn: map[string]error{"ContainerExists": fmt.Errorf("broken pipe: docker daemon socket")}}
	_, err := serviceEnsure(context.Background(), f, "dokku.postgres.app-db", CreateParams{
		ServiceType: "postgres", Image: "postgres:16-alpine", VolumePath: t.TempDir(),
	})
	if err == nil {
		t.Fatal("ContainerExists error must propagate, not be swallowed")
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "ContainerCreate") {
			t.Fatalf("a docker error must NEVER be read as 'missing' and trigger a recreate over a healthy DB: %v", f.calls)
		}
	}
}

func TestEnsureMissingWithDataRecreatesDedicated(t *testing.T) {
	dir := t.TempDir() // stands in for an intact data dir
	f := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f, "dokku.postgres.app-db", CreateParams{
		ServiceType: "postgres", Image: "postgres:16-alpine", VolumePath: dir,
		Network: "wokku-services", AdminPass: "reused-by-create-inert-on-existing-data",
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "recreated" {
		t.Fatalf("missing+data must recreate, got %q", res.Action)
	}
	joined := strings.Join(f.calls, " | ")
	if !strings.Contains(joined, "ContainerCreate") || !strings.Contains(joined, "NetworkConnect(wokku-services,dokku.postgres.app-db") {
		t.Fatalf("dedicated recreate missing create/attach: %v", f.calls)
	}
}

func TestEnsureMissingSharedParentUsesConstantsAndAlias(t *testing.T) {
	// The shared parent's data dir lives at a package-var path; reassign it to a
	// temp dir and restore so this doesn't leak into other tests.
	orig := sharedPostgresMetaDir
	t.Cleanup(func() { sharedPostgresMetaDir = orig })
	base := t.TempDir() // stand in for the shared parent's baked-in data dir
	sharedPostgresMetaDir = base
	if err := os.MkdirAll(filepath.Join(base, "_pgdata"), 0o700); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f, sharedPostgresContainer, CreateParams{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "recreated" {
		t.Fatalf("shared parent missing+data must recreate, got %q", res.Action)
	}
	joined := strings.Join(f.calls, " | ")
	if !strings.Contains(joined, "NetworkConnect(dokku-shared-postgres,dokku-shared-postgres") { // bridge attach
		t.Fatalf("shared parent must attach its bridge: %v", f.calls)
	}
	if !strings.Contains(joined, "NetworkConnect(wokku-services,dokku-shared-postgres,aliases=dokku-shared-postgres)") {
		t.Fatalf("shared parent must attach the overlay WITH its alias: %v", f.calls)
	}
}

func TestEnsureMissingWithoutDataRefuses(t *testing.T) {
	f := &fakeDocker{existing: map[string]bool{}}
	_, err := serviceEnsure(context.Background(), f, "dokku.postgres.gone", CreateParams{
		ServiceType: "postgres", VolumePath: "/tmp/definitely-does-not-exist-987654",
	})
	if err == nil {
		t.Fatal("missing container + absent data dir must error, not silently init")
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "ContainerCreate") {
			t.Fatalf("must NOT create over absent data: %v", f.calls)
		}
	}
}

func withSharedRedisDir(t *testing.T) string {
	t.Helper()
	orig := sharedRedisDataDir
	t.Cleanup(func() { sharedRedisDataDir = orig })
	sharedRedisDataDir = t.TempDir()
	return sharedRedisDataDir
}

// The generic dedicated path would boot `redis-server /data/redis.conf` with
// no --aclfile: every tenant user gone, admin auth gone (2026-10-07 audit).
func TestEnsureMissingSharedRedisRecreatesWithACLFile(t *testing.T) {
	base := withSharedRedisDir(t)
	if err := os.WriteFile(filepath.Join(base, "users.acl"), []byte("user default on #x ~* &* +@all\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	f := &fakeDocker{existing: map[string]bool{}}
	res, err := serviceEnsure(context.Background(), f, sharedRedisContainer, CreateParams{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Action != "recreated" {
		t.Fatalf("got %q", res.Action)
	}
	joined := strings.Join(f.calls, " | ")
	for _, want := range []string{
		"image=redis:7-alpine",
		"bind=" + base + ":/data",
		"cmd=[redis-server --appendonly yes --aclfile /data/users.acl]",
		"NetworkConnect(dokku-shared-redis,dokku-shared-redis",
		"NetworkConnect(wokku-services,dokku-shared-redis,aliases=dokku-shared-redis)",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("missing %q in %v", want, f.calls)
		}
	}
}

func TestEnsureMissingSharedRedisRefusesWithoutACLFile(t *testing.T) {
	withSharedRedisDir(t) // data dir present, users.acl absent
	f := &fakeDocker{existing: map[string]bool{}}
	if _, err := serviceEnsure(context.Background(), f, sharedRedisContainer, CreateParams{}); err == nil {
		t.Fatal("must refuse: without users.acl the parent boots with no tenants and a passwordless default")
	}
	for _, c := range f.calls {
		if strings.HasPrefix(c, "ContainerCreate") {
			t.Fatalf("must NOT create: %v", f.calls)
		}
	}
}

func TestEnsureMissingSharedRedisRefusesWithoutDataDir(t *testing.T) {
	orig := sharedRedisDataDir
	t.Cleanup(func() { sharedRedisDataDir = orig })
	sharedRedisDataDir = "/tmp/definitely-not-here-shared-redis-123"
	f := &fakeDocker{existing: map[string]bool{}}
	if _, err := serviceEnsure(context.Background(), f, sharedRedisContainer, CreateParams{}); err == nil {
		t.Fatal("missing data dir must refuse")
	}
}
