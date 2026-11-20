package builder

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"

	"wokku.cloud/wokkud/internal/control"
)

func TestBuildCommandsDockerfile(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Dockerfile"), []byte("FROM scratch"), 0o644)
	os.WriteFile(filepath.Join(dir, "Procfile"), []byte("web: node bin/www\n"), 0o644)
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "node bin/www")
	want := [][]string{{"docker", "buildx", "build", "--builder", "wokku-build-rootless", "--push", "-t", "127.0.0.1:5000/wokku/blog:id-1", dir}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "Procfile")); err != nil {
		t.Fatal("Dockerfile builds must leave the Procfile alone")
	}
}

// nixpacks only writes the plan (--out); the capped wokku-build builder does
// the actual build, so a tenant's RUN steps never run on the uncapped
// default builder.
func TestBuildCommandsNixpacks(t *testing.T) {
	dir := t.TempDir()
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "")
	want := [][]string{
		{"nixpacks", "build", dir, "--out", dir},
		{"docker", "buildx", "build", "--builder", "wokku-build-rootless", "--push", "-f", filepath.Join(dir, ".nixpacks", "Dockerfile"), "-t", "127.0.0.1:5000/wokku/blog:id-1", dir},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

// A Procfile web command must be baked in via --start-cmd and the Procfile
// kept OUT of the image — dokku git:from-image re-parses an in-image
// Procfile, word-splitting its command over nixpacks' bash -l -c entrypoint
// (bash -c "node" "bin/www" runs a bare REPL and the app crashes).
func TestBuildCommandsNixpacksProcfile(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Procfile"), []byte("web: node bin/www\n"), 0o644)
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "node bin/www")
	if want := []string{"nixpacks", "build", dir, "--out", dir, "--start-cmd", "node bin/www"}; !reflect.DeepEqual(got[0], want) {
		t.Fatalf("got %v", got[0])
	}
	if _, err := os.Stat(filepath.Join(dir, "Procfile")); !os.IsNotExist(err) {
		t.Fatal("Procfile must be removed from the build context so it never lands in the image")
	}
}

func TestBuildLimitsDefaultsAndClamp(t *testing.T) {
	none := func(string) string { return "" }
	if got := buildLimits(none, 36); got != (limits{Memory: "16g", CPUs: 8, Pids: 4096}) {
		t.Fatalf("defaults: %+v", got)
	}
	// docker update rejects --cpus above the host's CPU count.
	if got := buildLimits(none, 2); got.CPUs != 2 {
		t.Fatalf("cpus must clamp to the host: %+v", got)
	}
	env := map[string]string{"WOKKUD_BUILD_MEMORY": "4g", "WOKKUD_BUILD_CPUS": "3", "WOKKUD_BUILD_PIDS": "1024"}
	if got := buildLimits(func(k string) string { return env[k] }, 36); got != (limits{Memory: "4g", CPUs: 3, Pids: 1024}) {
		t.Fatalf("overrides: %+v", got)
	}
	bad := map[string]string{"WOKKUD_BUILD_CPUS": "lots", "WOKKUD_BUILD_PIDS": "-1"}
	if got := buildLimits(func(k string) string { return bad[k] }, 36); got.CPUs != 8 || got.Pids != 4096 {
		t.Fatalf("garbage overrides must fall back to defaults: %+v", got)
	}
}

func TestUpdateArgs(t *testing.T) {
	got := updateArgs(limits{Memory: "16g", CPUs: 8, Pids: 4096}, "wokku-buildkitd")
	want := []string{"docker", "update", "--memory", "16g", "--memory-swap", "16g", "--cpus", "8", "--pids-limit", "4096", "wokku-buildkitd"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

func TestBuildkitdConfig(t *testing.T) {
	if got := buildkitdConfig("127.0.0.1:5000/wokku/blog:1"); !strings.Contains(got, `[registry."127.0.0.1:5000"]`) || !strings.Contains(got, "http = true") {
		t.Fatalf("loopback registry must be plain http: %q", got)
	}
	if got := buildkitdConfig("registry.example.com/wokku/blog:1"); strings.Contains(got, "http = true") {
		t.Fatalf("a remote registry must stay https: %q", got)
	}
}

// F-08: the build must not inherit wokkud's control-plane token.
func TestBuildEnvDropsSecrets(t *testing.T) {
	got := buildEnv([]string{"PATH=/usr/bin", "HOME=/root", "WOKKUD_TOKEN=secret", "WOKKUD_URL=https://x", "DOCKER_CONFIG=/root/.docker"})
	want := []string{"PATH=/usr/bin", "HOME=/root", "DOCKER_CONFIG=/root/.docker"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
}

// chunkRecorder captures the chunk of every PostBuildLog the sink sends.
type chunkRecorder struct {
	mu     sync.Mutex
	chunks []string
}

func (r *chunkRecorder) server(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		body, _ := io.ReadAll(req.Body)
		var payload struct {
			Chunk string `json:"chunk"`
		}
		json.Unmarshal(body, &payload)
		r.mu.Lock()
		r.chunks = append(r.chunks, payload.Chunk)
		r.mu.Unlock()
	}))
}

func (r *chunkRecorder) joined() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return strings.Join(r.chunks, "")
}

func TestLogSinkFlushesBigWritesImmediately(t *testing.T) {
	rec := &chunkRecorder{}
	srv := rec.server(t)
	defer srv.Close()
	s := newLogSink(control.New(srv.URL, "tok", "test"), "id-1")
	defer s.Close()

	big := strings.Repeat("x", 32*1024)
	s.Write([]byte(big))
	if got := rec.joined(); got != big {
		t.Fatalf("32KB write not flushed immediately: got %d bytes", len(got))
	}
}

func TestLogSinkCloseFlushesRemainderAndIsIdempotent(t *testing.T) {
	rec := &chunkRecorder{}
	srv := rec.server(t)
	defer srv.Close()
	s := newLogSink(control.New(srv.URL, "tok", "test"), "id-1")

	s.Write([]byte("tail output\n")) // under threshold — buffered
	s.Close()
	s.Close() // must not panic (sync.Once) and must not re-send
	if got := rec.joined(); got != "tail output\n" {
		t.Fatalf("close flush: got %q", got)
	}
}
