package builder

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

// Tenant builds run on a dedicated buildx builder ("wokku-build"), never on
// dockerd's built-in one, so they can be capped (security F-01, 2026-11-19):
//
//   - buildkitd runs in its own container on the HOST network so it can push
//     to the loopback registry (127.0.0.1:5000), while --oci-worker-net=bridge
//     gives every RUN step its own netns — tenant code cannot reach host
//     loopback services.
//   - memory/cpu/pids limits are applied with `docker update` on the builder
//     container; RUN steps are nested cgroups beneath it, so one build can't
//     starve co-tenant apps (fork bomb, OOM). buildx's cgroup-parent driver
//     opt is ignored under the systemd cgroup driver, hence docker update.
//
// The limits are re-applied before every build: cheap, idempotent, and it
// covers a builder container that buildx recreated.
// ponytail: still a privileged buildkitd as root — a rootless/ephemeral
// builder is the real isolation fix (tracked separately).
const (
	builderName      = "wokku-build"
	builderContainer = "buildx_buildkit_" + builderName + "0"
	buildkitImage    = "moby/buildkit:v0.29.0"
)

type limits struct {
	Memory string
	CPUs   float64
	Pids   int
}

// buildLimits: 16g / 8 CPUs / 4096 pids, overridable per host with
// WOKKUD_BUILD_MEMORY / WOKKUD_BUILD_CPUS / WOKKUD_BUILD_PIDS. CPUs clamp to
// the host (docker update rejects more than it has).
func buildLimits(getenv func(string) string, ncpu int) limits {
	l := limits{Memory: "16g", CPUs: 8, Pids: 4096}
	if v := getenv("WOKKUD_BUILD_MEMORY"); v != "" {
		l.Memory = v
	}
	if v, err := strconv.ParseFloat(getenv("WOKKUD_BUILD_CPUS"), 64); err == nil && v > 0 {
		l.CPUs = v
	}
	if v, err := strconv.Atoi(getenv("WOKKUD_BUILD_PIDS")); err == nil && v > 0 {
		l.Pids = v
	}
	if l.CPUs > float64(ncpu) {
		l.CPUs = float64(ncpu)
	}
	return l
}

func updateArgs(l limits) []string {
	return []string{"docker", "update",
		"--memory", l.Memory, "--memory-swap", l.Memory, // swap == memory: no swap escape
		"--cpus", strconv.FormatFloat(l.CPUs, 'f', -1, 64),
		"--pids-limit", strconv.Itoa(l.Pids),
		builderContainer}
}

// buildkitdConfig marks a loopback registry as plain http (it has no TLS)
// and bounds the build cache (30GB, and never below 15% free disk).
func buildkitdConfig(pushRef string) string {
	host := strings.SplitN(pushRef, "/", 2)[0]
	cfg := "[worker.oci]\n  gc = true\n  maxUsedSpace = \"30GB\"\n  minFreeSpace = \"15%\"\n"
	if strings.HasPrefix(host, "127.0.0.1") || strings.HasPrefix(host, "localhost") {
		cfg += fmt.Sprintf("\n[registry.%q]\n  http = true\n", host)
	}
	return cfg
}

// buildEnv is the allowlist every build subprocess gets — never wokkud's
// own env, which carries WOKKUD_TOKEN (security F-08).
func buildEnv(environ []string) []string {
	keep := map[string]bool{"PATH": true, "HOME": true, "DOCKER_CONFIG": true, "DOCKER_HOST": true, "TMPDIR": true, "LANG": true}
	var out []string
	for _, kv := range environ {
		if k, _, _ := strings.Cut(kv, "="); keep[k] {
			out = append(out, kv)
		}
	}
	return out
}

// ensureBuilder makes sure the capped builder exists and is running, then
// (re)applies the limits. Any failure fails the build — never fall back to
// the uncapped default builder.
func ensureBuilder(ctx context.Context, pushRef string) error {
	run := func(args ...string) error {
		cmd := exec.CommandContext(ctx, args[0], args[1:]...)
		cmd.Env = buildEnv(os.Environ())
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("%s: %v: %s", strings.Join(args[:3], " "), err, strings.TrimSpace(string(out)))
		}
		return nil
	}
	if run("docker", "buildx", "inspect", "--bootstrap", builderName) != nil {
		f, err := os.CreateTemp("", "wokku-buildkitd-*.toml")
		if err != nil {
			return err
		}
		defer os.Remove(f.Name())
		f.WriteString(buildkitdConfig(pushRef))
		f.Close()
		if err := run("docker", "buildx", "create", "--name", builderName,
			"--driver", "docker-container",
			"--driver-opt", "network=host",
			"--driver-opt", "image="+buildkitImage,
			"--driver-opt", "restart-policy=unless-stopped",
			"--buildkitd-flags", "--oci-worker-net=bridge",
			"--buildkitd-config", f.Name(),
			"--bootstrap"); err != nil {
			return err
		}
	}
	return run(updateArgs(buildLimits(os.Getenv, runtime.NumCPU()))...)
}
