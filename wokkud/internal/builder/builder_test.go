package builder

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

func TestBuildCommandsDockerfile(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Dockerfile"), []byte("FROM scratch"), 0o644)
	os.WriteFile(filepath.Join(dir, "Procfile"), []byte("web: node bin/www\n"), 0o644)
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "node bin/www", nil)
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
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "", []string{"--build-arg", "GEM_HOME=/g"})
	want := [][]string{
		{"nixpacks", "build", dir, "--out", dir},
		{"docker", "buildx", "build", "--builder", "wokku-build-rootless", "--push", "--build-arg", "GEM_HOME=/g", "-f", filepath.Join(dir, ".nixpacks", "Dockerfile"), "-t", "127.0.0.1:5000/wokku/blog:id-1", dir},
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
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "node bin/www", nil)
	if want := []string{"nixpacks", "build", dir, "--out", dir, "--start-cmd", "node bin/www"}; !reflect.DeepEqual(got[0], want) {
		t.Fatalf("got %v", got[0])
	}
	if _, err := os.Stat(filepath.Join(dir, "Procfile")); !os.IsNotExist(err) {
		t.Fatal("Procfile must be removed from the build context so it never lands in the image")
	}
}

// nixpacks' Dockerfile declares its plan variables as ARGs that
// `nixpacks build` passes itself; we run buildx ourselves, so we must pass
// them (an empty GEM_HOME crashes RubyGems on Ruby 3.4.13). Sorted, and
// values with spaces stay one argument.
func TestPlanBuildArgs(t *testing.T) {
	plan := []byte(`{"variables":{"GEM_HOME":"/usr/local/rvm/gems/3.4.13","A_FLAG":"two words","NIXPACKS_METADATA":"ruby"},"phases":{}}`)
	got, err := planBuildArgs(plan)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"--build-arg", "A_FLAG=two words", "--build-arg", "GEM_HOME=/usr/local/rvm/gems/3.4.13", "--build-arg", "NIXPACKS_METADATA=ruby"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	// Every stack gets its plan variables (2026-11-22, all 14 starters
	// checked): without them nixpacks bakes e.g. NODE_ENV="" into the image.
	node, _ := planBuildArgs([]byte(`{"variables":{"NODE_ENV":"production","NIXPACKS_METADATA":"node","NPM_CONFIG_PRODUCTION":"false"}}`))
	if want := []string{"--build-arg", "NIXPACKS_METADATA=node", "--build-arg", "NODE_ENV=production", "--build-arg", "NPM_CONFIG_PRODUCTION=false"}; !reflect.DeepEqual(node, want) {
		t.Fatalf("node plan: got %v", node)
	}
	if got, _ := planBuildArgs([]byte(`{}`)); got != nil {
		t.Fatalf("a plan without variables passes no build args, got %v", got)
	}
	if _, err := planBuildArgs([]byte("not json")); err == nil {
		t.Fatal("bad plan must error")
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
	got := BuildEnv([]string{"PATH=/usr/bin", "HOME=/root", "WOKKUD_TOKEN=secret", "WOKKUD_URL=https://x", "DOCKER_CONFIG=/root/.docker"})
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

// BuildKit re-syncs the build context incrementally under one shared key per
// host and skips a file whose path, size and mtime match the previous build's,
// so two apps' same-size files with the same (git commit) mtime leaked across
// builds (2026-11-21: schdl's image got maukemana's credentials.yml.enc).
// Extracted files must carry the extraction time, never the archive's.
func TestFetchAndExtractIgnoresArchiveMtimes(t *testing.T) {
	tmp := t.TempDir()
	payload := filepath.Join(tmp, "payload")
	os.Mkdir(payload, 0o755)
	f := filepath.Join(payload, "secret.txt")
	os.WriteFile(f, []byte("tenant-a"), 0o644)
	old := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	os.Chtimes(f, old, old)
	archive := filepath.Join(tmp, "src.tar.gz")
	if out, err := exec.Command("tar", "-czf", archive, "-C", payload, ".").CombinedOutput(); err != nil {
		t.Fatalf("tar: %v %s", err, out)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.ServeFile(w, r, archive) }))
	defer srv.Close()

	work := t.TempDir()
	src := filepath.Join(work, "src")
	if err := fetchAndExtract(context.Background(), srv.URL, work, src); err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(filepath.Join(src, "secret.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(st.ModTime()) > time.Minute {
		t.Fatalf("extracted file kept the archive mtime %v", st.ModTime())
	}
}
