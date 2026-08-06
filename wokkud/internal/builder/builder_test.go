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
	want := [][]string{{"docker", "buildx", "build", "--push", "-t", "127.0.0.1:5000/wokku/blog:id-1", dir}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "Procfile")); err != nil {
		t.Fatal("Dockerfile builds must leave the Procfile alone")
	}
}

func TestBuildCommandsNixpacks(t *testing.T) {
	dir := t.TempDir()
	got := buildCommands(dir, "127.0.0.1:5000/wokku/blog:id-1", "")
	want := [][]string{
		{"nixpacks", "build", dir, "--name", "127.0.0.1:5000/wokku/blog:id-1"},
		{"docker", "push", "127.0.0.1:5000/wokku/blog:id-1"},
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
	want := [][]string{
		{"nixpacks", "build", dir, "--name", "127.0.0.1:5000/wokku/blog:id-1", "--start-cmd", "node bin/www"},
		{"docker", "push", "127.0.0.1:5000/wokku/blog:id-1"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	if _, err := os.Stat(filepath.Join(dir, "Procfile")); !os.IsNotExist(err) {
		t.Fatal("Procfile must be removed from the build context so it never lands in the image")
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
