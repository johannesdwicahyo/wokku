// Package builder is wokkud's build executor (Track A Phase 4c): claim a
// pending deploy's build, fetch its source tarball, build with buildx
// (Dockerfile present) or nixpacks (everything else), push to the local
// registry, stream output to the control plane, report the outcome.
// All failures are REPORTED, never returned — the control plane's
// TarballDeployJob is the one holding the deploy state machine.
package builder

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"wokku.cloud/wokkud/internal/control"
)

// Executor serializes builds: one at a time, dedup by deploy id (the
// heartbeat re-announces pending ids every 15s, so dropped enqueues
// self-heal). ponytail: single worker — parallel builds fight for host
// CPU/disk; add a small pool only if queue latency ever matters.
type Executor struct {
	client   *control.Client
	queue    chan string
	mu       sync.Mutex
	inFlight map[string]bool

	busyMu sync.Mutex
	busy   bool
}

func NewExecutor(ctx context.Context, client *control.Client) *Executor {
	e := &Executor{client: client, queue: make(chan string, 16), inFlight: map[string]bool{}}
	go e.work(ctx)
	return e
}

func (e *Executor) Enqueue(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.inFlight[id] {
		return
	}
	select {
	case e.queue <- id:
		e.inFlight[id] = true
	default: // queue full — the next heartbeat re-delivers the id
	}
}

func (e *Executor) work(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case id := <-e.queue:
			job, err := e.client.ClaimBuild(id)
			if err != nil {
				log.Printf("wokkud: claim %s: %v", id, err)
			}
			if job != nil {
				e.setBusy(true)
				Run(ctx, e.client, job)
				e.setBusy(false)
			}
			e.mu.Lock()
			delete(e.inFlight, id)
			e.mu.Unlock()
		}
	}
}

func (e *Executor) setBusy(v bool) {
	e.busyMu.Lock()
	e.busy = v
	e.busyMu.Unlock()
}

// Busy reports whether a claimed build is running right now — the registry
// GC ticker checks this so it never contends with a build for disk I/O.
func (e *Executor) Busy() bool {
	e.busyMu.Lock()
	defer e.busyMu.Unlock()
	return e.busy
}

// Run executes one claimed build end to end.
func Run(ctx context.Context, client *control.Client, job *control.BuildJob) {
	parent := ctx
	ctx, cancel := context.WithTimeout(ctx, time.Duration(job.TimeoutSeconds)*time.Second)
	defer cancel()
	log.Printf("wokkud: building %s (deploy %s)", job.AppName, job.ID)

	dir, err := os.MkdirTemp("", "wokkud-build-")
	if err != nil {
		fail(client, job, fmt.Sprintf("temp dir: %v", err))
		return
	}
	defer os.RemoveAll(dir)

	src := filepath.Join(dir, "src")
	if err := fetchAndExtract(ctx, job.ArchiveURL, dir, src); err != nil {
		fail(client, job, err.Error())
		return
	}

	// Close (flush) the sink BEFORE reporting: the report unblocks
	// TarballDeployJob's final read of deploy.log, and once the deploy goes
	// terminal a late chunk gets a 410. Close is idempotent (sync.Once), so
	// the defer is just the abandoned-path backstop.
	sink := newLogSink(client, job.ID)
	defer sink.Close()
	if err := ensureBuilder(ctx, job.PushRef); err != nil {
		sink.Close()
		fail(client, job, fmt.Sprintf("build sandbox unavailable: %v", err))
		return
	}
	formation := parseProcfile(src) // before buildCommands — it may remove the Procfile
	var buildArgs []string
	if _, err := os.Stat(filepath.Join(src, "Dockerfile")); err != nil {
		plan := exec.CommandContext(ctx, "nixpacks", "plan", src)
		plan.Env = buildEnv(os.Environ())
		out, err := plan.Output()
		if err == nil {
			buildArgs, err = planBuildArgs(out)
		}
		if err != nil {
			sink.Close()
			fail(client, job, fmt.Sprintf("nixpacks plan: %v", err))
			return
		}
	}
	for _, args := range buildCommands(src, job.PushRef, formation["web"], buildArgs) {
		cmd := exec.CommandContext(ctx, args[0], args[1:]...)
		cmd.Dir = src
		cmd.Env = buildEnv(os.Environ())
		cmd.Stdout = sink
		cmd.Stderr = sink
		if err := cmd.Run(); err != nil {
			sink.Close()
			if parent.Err() != nil { // agent shutting down, not a build problem
				fail(client, job, "build interrupted by a host agent restart — retry the deploy")
				return
			}
			fail(client, job, fmt.Sprintf("%s: %v", args[0], err))
			return
		}
	}
	sink.Close()
	log.Printf("wokkud: build %s pushed %s", job.ID, job.PushRef)
	if err := client.ReportBuild(job.ID, "succeeded", "", formation); err != nil {
		log.Printf("wokkud: report %s: %v", job.ID, err)
	}
}

// buildCommands picks the build recipe: Dockerfile wins; otherwise
// nixpacks only writes its plan (--out) into .nixpacks/. Either way the
// capped rootless builder (capped.go, rootless.go) builds and pushes in one step.
//
// A Procfile web command is baked in via --start-cmd and the Procfile is
// removed from the build context: dokku git:from-image re-parses an
// in-image Procfile and word-splits its command over nixpacks'
// `ENTRYPOINT ["/bin/bash","-l","-c"]` — bash -c "node" "bin/www" runs a
// bare REPL and the app crashes. Nixpacks itself bakes the command as one
// string, which that entrypoint runs fine.
// ponytail: non-web Procfile entries are dropped on the dokku path (the
// lifecycle path gets them via formation_json) — plumb the full formation
// through dokku ps if a non-lifecycle multi-process app ever needs it.
func buildCommands(srcDir, pushRef, webCmd string, buildArgs []string) [][]string {
	buildx := []string{"docker", "buildx", "build", "--builder", builderName, "--push"}
	if _, err := os.Stat(filepath.Join(srcDir, "Dockerfile")); err == nil {
		return [][]string{append(buildx, "-t", pushRef, srcDir)}
	}
	nix := []string{"nixpacks", "build", srcDir, "--out", srcDir}
	if webCmd != "" {
		os.Remove(filepath.Join(srcDir, "Procfile"))
		nix = append(nix, "--start-cmd", webCmd)
	}
	buildx = append(buildx, buildArgs...)
	return [][]string{nix, append(buildx, "-f", filepath.Join(srcDir, ".nixpacks", "Dockerfile"), "-t", pushRef, srcDir)}
}

// planBuildArgs turns `nixpacks plan` JSON into --build-arg flags. nixpacks'
// Dockerfile declares its plan variables (GEM_HOME, NODE_ENV, ...) as ARGs
// that `nixpacks build` passes itself; we run buildx ourselves, so without
// these every such ENV was empty (an empty GEM_HOME crashes RubyGems on
// Ruby 3.4.13, 2026-11-21). Sorted for a stable cache key.
// Ruby plans only for now (see below).
func planBuildArgs(plan []byte) ([]string, error) {
	var p struct {
		Variables map[string]string `json:"variables"`
	}
	if err := json.Unmarshal(plan, &p); err != nil {
		return nil, err
	}
	// shortcut: Ruby only. Other stacks' variables (NODE_ENV=production,
	// CI=true, ...) would change existing apps' builds; widen after testing
	// every starter with them.
	if !strings.Contains(p.Variables["NIXPACKS_METADATA"], "ruby") {
		return nil, nil
	}
	keys := make([]string, 0, len(p.Variables))
	for k := range p.Variables {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var args []string
	for _, k := range keys {
		args = append(args, "--build-arg", k+"="+p.Variables[k])
	}
	return args, nil
}

// fetchAndExtract downloads the presigned archive and untars it. exec's
// GNU tar (not archive/tar): tar >=1.29 refuses ".." and absolute member
// paths without -P — exactly the traversal guard a user-uploaded archive
// needs, for free.
//
// -m (touch) stamps every file with the extraction time: BuildKit syncs the
// context incrementally under one shared key per host and skips a file whose
// path, size and mtime match the previous build's — with archive mtimes (git
// commit time, tenant-controlled) one app's file could land in another app's
// image (2026-11-21).
func fetchAndExtract(ctx context.Context, url, workDir, srcDir string) error {
	archive := filepath.Join(workDir, "src.tar.gz")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("archive download: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("archive download: HTTP %d", resp.StatusCode)
	}
	f, err := os.Create(archive)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return fmt.Errorf("archive download: %w", err)
	}
	f.Close()
	if err := os.Mkdir(srcDir, 0o755); err != nil {
		return err
	}
	if out, err := exec.CommandContext(ctx, "tar", "-xmzf", archive, "-C", srcDir).CombinedOutput(); err != nil {
		return fmt.Errorf("tar: %v: %s", err, out)
	}
	return nil
}

func fail(client *control.Client, job *control.BuildJob, msg string) {
	log.Printf("wokkud: build %s failed: %s", job.ID, msg)
	if err := client.ReportBuild(job.ID, "failed", msg, nil); err != nil {
		log.Printf("wokkud: report %s: %v", job.ID, err)
	}
}

// logSink batches build output into ~2s POSTs so a chatty build doesn't
// turn into hundreds of requests.
type logSink struct {
	client    *control.Client
	id        string
	mu        sync.Mutex
	buf       bytes.Buffer
	done      chan struct{}
	closeOnce sync.Once
}

func newLogSink(client *control.Client, id string) *logSink {
	s := &logSink{client: client, id: id, done: make(chan struct{})}
	go s.flusher()
	return s
}

func (s *logSink) Write(p []byte) (int, error) {
	s.mu.Lock()
	s.buf.Write(p)
	big := s.buf.Len() >= 32*1024
	s.mu.Unlock()
	if big {
		s.flush()
	}
	return len(p), nil
}

func (s *logSink) flusher() {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-t.C:
			s.flush()
		}
	}
}

func (s *logSink) flush() {
	s.mu.Lock()
	chunk := s.buf.String()
	s.buf.Reset()
	s.mu.Unlock()
	if chunk == "" {
		return
	}
	if err := s.client.PostBuildLog(s.id, chunk); err != nil {
		log.Printf("wokkud: build log: %v", err)
	}
}

func (s *logSink) Close() {
	s.closeOnce.Do(func() { close(s.done) })
	s.flush()
}
