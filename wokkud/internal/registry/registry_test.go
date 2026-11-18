package registry

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeRegistry serves the slice of the docker registry v2 API Prune needs:
// tags/list, manifest HEAD (digest lookup), manifest DELETE. tags == nil
// simulates a repo that was never pushed (tags/list 404s).
type fakeRegistry struct {
	t        *testing.T
	mu       sync.Mutex
	tags     []string
	digest   map[string]string // tag -> digest
	vanished map[string]bool   // tag -> HEAD 404s (deleted by someone else mid-run)
	deleted  []string          // DELETE calls, in order, by digest
}

func (f *fakeRegistry) start() *httptest.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v2/{repo}/tags/list", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.tags == nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string][]string{"tags": f.tags})
	})
	mux.HandleFunc("HEAD /v2/{repo}/manifests/{tag}", func(w http.ResponseWriter, r *http.Request) {
		if f.t != nil {
			accepts := r.Header.Values("Accept")
			if !containsAll(accepts, manifestV2Accept, ociManifestAccept) {
				f.t.Errorf("HEAD manifest: want both Accept headers, got %v", accepts)
			}
		}
		tag := r.PathValue("tag")
		f.mu.Lock()
		defer f.mu.Unlock()
		if f.vanished[tag] {
			http.NotFound(w, r)
			return
		}
		d, ok := f.digest[tag]
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Docker-Content-Digest", d)
	})
	mux.HandleFunc("DELETE /v2/{repo}/manifests/{digest}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		f.deleted = append(f.deleted, r.PathValue("digest"))
		f.mu.Unlock()
		w.WriteHeader(http.StatusAccepted)
	})
	return httptest.NewServer(mux)
}

func containsAll(haystack []string, want ...string) bool {
	for _, w := range want {
		found := false
		for _, h := range haystack {
			if h == w {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

func TestPruneDeletesExclusiveDigests(t *testing.T) {
	f := &fakeRegistry{
		t:    t,
		tags: []string{"a", "b", "c"},
		digest: map[string]string{
			"a": "sha256:aaa",
			"b": "sha256:bbb",
			"c": "sha256:ccc",
		},
	}
	srv := f.start()
	defer srv.Close()

	res, err := Prune(context.Background(), srv.URL, "myapp", []string{"a"})
	if err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if res != (PruneResult{Deleted: 2, Kept: 1, SkippedShared: 0}) {
		t.Fatalf("result = %+v", res)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.deleted) != 2 {
		t.Fatalf("deleted calls = %v", f.deleted)
	}
}

func TestPruneSkipsSharedDigest(t *testing.T) {
	f := &fakeRegistry{
		t:    t,
		tags: []string{"a", "b"},
		digest: map[string]string{
			"a": "sha256:shared",
			"b": "sha256:shared", // b shares a's (kept) digest — must survive
		},
	}
	srv := f.start()
	defer srv.Close()

	res, err := Prune(context.Background(), srv.URL, "myapp", []string{"a"})
	if err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if res != (PruneResult{Deleted: 0, Kept: 1, SkippedShared: 1}) {
		t.Fatalf("result = %+v", res)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.deleted) != 0 {
		t.Fatalf("deleted calls = %v, want none", f.deleted)
	}
}

// TestPruneDedupesCandidatesSharingDigest pins the counting semantic: when
// two non-kept candidates share one digest, exactly one DELETE hits the
// registry (deleting a digest once is enough — a second DELETE on an
// already-gone manifest just 404s), but `deleted` counts TAGS, not DELETE
// calls, so the caller's "N images pruned" reporting matches what disappeared
// from `docker images`.
func TestPruneDedupesCandidatesSharingDigest(t *testing.T) {
	f := &fakeRegistry{
		t:    t,
		tags: []string{"a", "b", "c"},
		digest: map[string]string{
			"a": "sha256:aaa",
			"b": "sha256:shared-not-kept",
			"c": "sha256:shared-not-kept",
		},
	}
	srv := f.start()
	defer srv.Close()

	res, err := Prune(context.Background(), srv.URL, "myapp", []string{"a"})
	if err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if res != (PruneResult{Deleted: 2, Kept: 1, SkippedShared: 0}) {
		t.Fatalf("result = %+v", res)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.deleted) != 1 {
		t.Fatalf("deleted calls = %v, want exactly 1 DELETE", f.deleted)
	}
}

func TestPruneMissingRepo404(t *testing.T) {
	f := &fakeRegistry{tags: nil}
	srv := f.start()
	defer srv.Close()

	res, err := Prune(context.Background(), srv.URL, "ghost", []string{"a"})
	if err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if res != (PruneResult{}) {
		t.Fatalf("result = %+v, want zero value", res)
	}
}

func TestPruneTagVanishesMidway(t *testing.T) {
	f := &fakeRegistry{
		tags: []string{"a", "b", "c"},
		digest: map[string]string{
			"a": "sha256:aaa",
			"c": "sha256:ccc",
		},
		vanished: map[string]bool{"b": true}, // deleted by another process mid-run
	}
	srv := f.start()
	defer srv.Close()

	res, err := Prune(context.Background(), srv.URL, "myapp", []string{"a"})
	if err != nil {
		t.Fatalf("Prune: %v", err)
	}
	if res != (PruneResult{Deleted: 1, Kept: 1, SkippedShared: 0}) {
		t.Fatalf("result = %+v", res)
	}
}

// fakeExecer records Run calls; faked in place of a real "docker" binary.
type fakeExecer struct {
	mu    sync.Mutex
	calls [][]string
	err   error
}

func (f *fakeExecer) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, append([]string{name}, args...))
	return nil, f.err
}

func TestGCCommand(t *testing.T) {
	f := &fakeExecer{}
	if err := GC(context.Background(), f); err != nil {
		t.Fatalf("GC: %v", err)
	}
	want := [][]string{
		{"docker", "exec", "wokku-registry", "registry", "garbage-collect", "/etc/docker/registry/config.yml", "--delete-untagged=false"},
		{"docker", "image", "prune", "-f"},
		{"docker", "restart", "wokku-registry"},
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Fatalf("calls = %v, want %v", f.calls, want)
	}
	for _, call := range f.calls {
		for _, arg := range call {
			if arg == "-a" {
				t.Fatalf("call %v must NEVER use -a", call)
			}
		}
	}
}

func TestGCSkipsWhileBusy(t *testing.T) {
	f := &fakeExecer{}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		RunGCTicker(ctx, 5*time.Millisecond, func() bool { return true }, f)
		close(done)
	}()
	time.Sleep(30 * time.Millisecond)
	cancel()
	<-done

	f.mu.Lock()
	n := len(f.calls)
	f.mu.Unlock()
	if n != 0 {
		t.Fatalf("expected zero exec calls while busy() is always true, got %d", n)
	}
}

func TestGCRunsWhenNotBusy(t *testing.T) {
	f := &fakeExecer{}
	var ticks int32
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		RunGCTicker(ctx, 5*time.Millisecond, func() bool {
			return atomic.AddInt32(&ticks, 1) > 1 // busy from the second tick on
		}, f)
		close(done)
	}()
	time.Sleep(40 * time.Millisecond)
	cancel()
	<-done

	f.mu.Lock()
	n := len(f.calls)
	f.mu.Unlock()
	if n == 0 {
		t.Fatalf("expected at least one GC run while not busy, got 0")
	}
}

// scriptedExecer answers `docker images` with a fixed tag list and records
// every call; rmiErr makes each `docker rmi` fail (e.g. image in use).
type scriptedExecer struct {
	tags   string
	rmiErr error
	calls  [][]string
}

func (f *scriptedExecer) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	f.calls = append(f.calls, append([]string{name}, args...))
	if len(args) > 0 && args[0] == "images" {
		return []byte(f.tags), nil
	}
	return []byte("Error response from daemon: conflict"), f.rmiErr
}

// GC's `docker image prune -f` only removes UNTAGGED images, so the host's
// tagged local copies of pruned (or deleted-app) tags leaked forever.
// RemoveLocalImages untags every local tag of repo not in keep — without -f,
// so an image a container still uses is never removed.
func TestRemoveLocalImagesUntagsAllButKept(t *testing.T) {
	f := &scriptedExecer{tags: "keep\nold1\nold2\n<none>\n", rmiErr: errors.New("in use")}
	RemoveLocalImages(context.Background(), f, "wokku/app", []string{"keep"})
	want := [][]string{
		{"docker", "images", "--format", "{{.Tag}}", "127.0.0.1:5000/wokku/app"},
		{"docker", "rmi", "127.0.0.1:5000/wokku/app:old1"},
		{"docker", "rmi", "127.0.0.1:5000/wokku/app:old2"},
	}
	if !reflect.DeepEqual(f.calls, want) {
		t.Fatalf("calls = %v, want %v", f.calls, want)
	}
}

func TestRemoveLocalImagesEmptyKeepRemovesEverything(t *testing.T) {
	f := &scriptedExecer{tags: "a\n"}
	RemoveLocalImages(context.Background(), f, "wokku/gone", nil)
	if got := f.calls[len(f.calls)-1]; !reflect.DeepEqual(got, []string{"docker", "rmi", "127.0.0.1:5000/wokku/gone:a"}) {
		t.Fatalf("last call = %v", got)
	}
}
