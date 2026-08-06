// Package registry talks to the per-host docker registry (registry:2 bound
// to 127.0.0.1:5000, started by deploy/install.sh) — the wokkud-side
// replacement for app/services/dokku/registry.rb's #delete_tag, which
// deleted by TAG and silently killed every other tag sharing that tag's
// digest (live incident 2026-07-26: two tags, one digest, one delete nuked
// both). Prune resolves tags to manifest digests first and only deletes a
// digest that isn't referenced by any tag the caller wants kept.
//
// It also owns registry GC: deleting a manifest only unlinks it, so disk is
// reclaimed by a self-scheduled `registry garbage-collect`, run only when
// the builder isn't mid-build (both hammer the same disk).
package registry

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"time"
)

// DefaultBaseURL is the registry started by install.sh — loopback-only,
// never exposed off-host.
const DefaultBaseURL = "http://127.0.0.1:5000"

const (
	// Accept headers copied verbatim from the deleted Dokku::Registry#delete_tag
	// (app/services/dokku/registry.rb) — both must be sent so the registry
	// resolves a manifest built by either the old docker builder or buildx/OCI.
	manifestV2Accept  = "application/vnd.docker.distribution.manifest.v2+json"
	ociManifestAccept = "application/vnd.oci.image.manifest.v1+json"

	registryContainer  = "wokku-registry"
	registryConfigPath = "/etc/docker/registry/config.yml"

	gcIntervalEnv  = "WOKKUD_REGISTRY_GC_INTERVAL"
	defaultGCEvery = 7 * 24 * time.Hour
)

// PruneResult is registry.prune's op result (wire contract:
// {"deleted","kept","skipped_shared"}).
type PruneResult struct {
	Deleted       int `json:"deleted"`
	Kept          int `json:"kept"`
	SkippedShared int `json:"skipped_shared"`
}

// Prune deletes every tag in repo NOT in keep, except when a candidate's
// manifest digest is also referenced by a kept tag (shared base image, a
// digest-level dedup by buildx/nixpacks layers) — that candidate survives
// and counts toward SkippedShared instead of Deleted.
//
// Counting semantic (pinned per the brief, since candidates can also share
// a digest AMONG THEMSELVES): a digest is DELETEd from the registry at most
// once, but `Deleted` counts TAGS, not DELETE calls — two tags collapsing
// to one already-issued DELETE both count, since both vanish from `docker
// images` once GC runs. See TestPruneDedupesCandidatesSharingDigest.
//
// A 404 on tags/list (repo never pushed) returns a zero PruneResult, no
// error. A 404 on a candidate's manifest HEAD (deleted by a concurrent
// prune, or already gone) is a silent skip — never counted, never an error.
func Prune(ctx context.Context, baseURL, repo string, keep []string) (PruneResult, error) {
	tags, err := listTags(ctx, baseURL, repo)
	if err != nil {
		return PruneResult{}, err
	}

	keepSet := make(map[string]bool, len(keep))
	for _, t := range keep {
		keepSet[t] = true
	}

	var result PruneResult
	keepDigests := make(map[string]bool)
	var candidates []string
	for _, t := range tags {
		if keepSet[t] {
			result.Kept++
			// A 404 here (ok=false) is NOT an abort: registry:2 deletes by
			// digest, and a delete is atomic across every tag that shares
			// that digest. If this keep tag's manifest is gone, its digest
			// was never live to begin with — so no candidate below can be
			// aliasing an unresolved keep digest. Proceeding can only ever
			// under-protect a digest that already doesn't exist, never
			// delete one a live keep tag still points to.
			if digest, ok, err := headDigest(ctx, baseURL, repo, t); err != nil {
				return PruneResult{}, err
			} else if ok {
				keepDigests[digest] = true
			}
			continue
		}
		candidates = append(candidates, t)
	}

	deletedDigests := make(map[string]bool)
	for _, t := range candidates {
		digest, ok, err := headDigest(ctx, baseURL, repo, t)
		if err != nil {
			return PruneResult{}, err
		}
		if !ok {
			continue // vanished mid-run — silent skip
		}
		if keepDigests[digest] {
			result.SkippedShared++
			continue
		}
		if !deletedDigests[digest] {
			if err := deleteDigest(ctx, baseURL, repo, digest); err != nil {
				return PruneResult{}, err
			}
			deletedDigests[digest] = true
		}
		result.Deleted++
	}
	return result, nil
}

func listTags(ctx context.Context, baseURL, repo string) ([]string, error) {
	url := fmt.Sprintf("%s/v2/%s/tags/list", baseURL, repo)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tags list %s: HTTP %d", repo, resp.StatusCode)
	}
	var out struct {
		Tags []string `json:"tags"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("tags list %s: %w", repo, err)
	}
	return out.Tags, nil
}

// headDigest resolves tag's manifest digest. (false, nil) on 404 — the
// caller treats that as a silent skip, not an error.
func headDigest(ctx context.Context, baseURL, repo, tag string) (digest string, ok bool, err error) {
	url := fmt.Sprintf("%s/v2/%s/manifests/%s", baseURL, repo, tag)
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		return "", false, err
	}
	req.Header.Add("Accept", manifestV2Accept)
	req.Header.Add("Accept", ociManifestAccept)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return "", false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("head manifest %s/%s: HTTP %d", repo, tag, resp.StatusCode)
	}
	d := resp.Header.Get("Docker-Content-Digest")
	if d == "" {
		return "", false, fmt.Errorf("head manifest %s/%s: missing Docker-Content-Digest", repo, tag)
	}
	return d, true, nil
}

func deleteDigest(ctx context.Context, baseURL, repo, digest string) error {
	url := fmt.Sprintf("%s/v2/%s/manifests/%s", baseURL, repo, digest)
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// A 404 here means someone else's prune (or a prior retry) already
	// deleted it — same as the vanished-tag path, not a failure.
	if resp.StatusCode >= 300 && resp.StatusCode != http.StatusNotFound {
		return fmt.Errorf("delete manifest %s/%s: HTTP %d", repo, digest, resp.StatusCode)
	}
	return nil
}

// execer runs one host command and returns combined output; faked in tests.
// Real callers get HostExec, a thin os/exec wrapper — GC only ever shells
// out to `docker`, so there's no Docker SDK dependency to carry here.
type execer interface {
	Run(ctx context.Context, name string, args ...string) ([]byte, error)
}

// HostExec is the production execer: exec.CommandContext, combined output.
type HostExec struct{}

func (HostExec) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	return exec.CommandContext(ctx, name, args...).CombinedOutput()
}

// GC reclaims registry blob disk: deleting a manifest only unlinks it, so
// `registry garbage-collect` is what actually frees space, followed by a
// plain `docker image prune -f` for the corresponding dangling local image
// layers left behind by rebuilds. NEVER -a — that would also prune the
// running app images, not just the dangling/untagged ones GC just orphaned.
//
// Finally, `docker restart wokku-registry`: registry:2 caches blob
// descriptors in memory, and after a garbage-collect that cache still
// thinks a just-deleted digest exists — a re-push of that exact digest
// (e.g. redeploying the same commit twice) then silently no-ops instead of
// relinking the blob, leaving the manifest 404 forever (the 2026-07-26
// incident signature). The busy-guard above already guarantees no build is
// mid-push when GC runs, so the restart's brief pull/push interruption
// never lands on an in-flight build.
func GC(ctx context.Context, docker execer) error {
	if out, err := docker.Run(ctx, "docker", "exec", registryContainer,
		"registry", "garbage-collect", registryConfigPath, "--delete-untagged=false"); err != nil {
		return fmt.Errorf("registry garbage-collect: %w: %s", err, out)
	}
	if out, err := docker.Run(ctx, "docker", "image", "prune", "-f"); err != nil {
		return fmt.Errorf("docker image prune: %w: %s", err, out)
	}
	if out, err := docker.Run(ctx, "docker", "restart", registryContainer); err != nil {
		return fmt.Errorf("docker restart %s: %w: %s", registryContainer, err, out)
	}
	return nil
}

// GCInterval is the ticker period: WOKKUD_REGISTRY_GC_INTERVAL (any
// time.ParseDuration string, e.g. "10s" for testing) overrides the default
// weekly cadence.
func GCInterval() time.Duration {
	if v := os.Getenv(gcIntervalEnv); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return defaultGCEvery
}

// RunGCTicker runs GC on a self-scheduled ticker until ctx is done, checking
// busy() immediately before each run and skipping (log only) a tick where a
// build is in flight — GC and a build both churn the same disk, and a
// build's own progress matters more than staying exactly on schedule; the
// next tick tries again.
func RunGCTicker(ctx context.Context, interval time.Duration, busy func() bool, docker execer) {
	// The rollout runbook greps the agent's journal for this exact line to
	// confirm the ticker armed on upgrade (replacing the old unguarded
	// cron.weekly) — keep the wording stable.
	log.Printf("wokkud: registry GC ticker armed (interval %s)", interval)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if busy != nil && busy() {
				log.Println("wokkud: registry GC skipped — builder busy")
				continue
			}
			if err := GC(ctx, docker); err != nil {
				log.Printf("wokkud: registry GC: %v", err)
			}
		}
	}
}
