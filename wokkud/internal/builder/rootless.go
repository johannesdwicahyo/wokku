package builder

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// The rootless builder (security F-01). Proven on jkt-01 (Ubuntu 24.04,
// kernel 6.8, Docker 29) before rollout; every flag below is load-bearing.
const (
	builderName           = "wokku-build-rootless" // buildx builder (remote driver)
	builderContainer      = "wokku-buildkitd"      // the rootless daemon container
	cacheVolume           = "wokku-buildkit-cache"
	buildkitRootlessImage = "moby/buildkit:v0.29.0-rootless"
	apparmorProfileName   = "wokku-buildkit"
	apparmorProfilePath   = "/etc/apparmor.d/" + apparmorProfileName
	// The daemon's host uid and the host uid range build processes map into.
	// Never uid 1000: on our hosts that's a real login (with sudo).
	builderUID  = 61000
	subIDStart  = 3000000
	subIDLength = 65536
)

// apparmorProfile lets the builder create user namespaces. Ubuntu 24.04
// restricts unprivileged user namespaces host-wide
// (kernel.apparmor_restrict_unprivileged_userns=1); this allows them for the
// builder container only instead of lifting that restriction.
const apparmorProfile = `# Rootless BuildKit for Wokku tenant builds (managed by wokkud; security F-01).
abi <abi/4.0>,
include <tunables/global>

profile ` + apparmorProfileName + ` flags=(unconfined) {
  userns,
}
`

// rootlessImageDockerfile derives the builder image from the official
// rootless one: the network tools RootlessKit/BuildKit need (slirp4netns,
// iproute2 instead of busybox ip, iptables for the in-namespace bridge), a
// dedicated uid + subordinate range, and the buildkitd config baked in.
func rootlessImageDockerfile(pushRef string) string {
	uid := fmt.Sprint(builderUID)
	cfg := strings.NewReplacer(`"`, `\"`, "\n", `\n`, "%", "%%").Replace(buildkitdConfig(pushRef))
	return "FROM " + buildkitRootlessImage + "\n" +
		"USER root\n" +
		"RUN apk add --no-cache slirp4netns iproute2 iptables && \\\n" +
		"    sed -i 's/^user:x:1000:1000:/user:x:" + uid + ":" + uid + ":/' /etc/passwd && \\\n" +
		"    sed -i 's/^user:x:1000:/user:x:" + uid + ":/' /etc/group && \\\n" +
		fmt.Sprintf("    echo 'user:%d:%d' > /etc/subuid && echo 'user:%d:%d' > /etc/subgid && \\\n", subIDStart, subIDLength, subIDStart, subIDLength) +
		"    mkdir -p /run/user/" + uid + " /home/user/.config/buildkit /home/user/.local/share/buildkit /home/user/.local/tmp && \\\n" +
		"    printf \"" + cfg + "\" > /home/user/.config/buildkit/buildkitd.toml && \\\n" +
		"    chown -R " + uid + ":" + uid + " /home/user /run/user/" + uid + "\n" +
		"ENV XDG_RUNTIME_DIR=/run/user/" + uid + " BUILDKIT_HOST=unix:///run/user/" + uid + "/buildkit/buildkitd.sock\n" +
		"USER " + uid + ":" + uid + "\n"
}

// rootlessImageTag names the derived image by its Dockerfile, so a config
// or version change builds (and runs) a new image.
func rootlessImageTag(dockerfile string) string {
	sum := sha256.Sum256([]byte(dockerfile))
	return "wokku/buildkit-rootless:" + hex.EncodeToString(sum[:])[:12]
}

func daemonRunArgs(image string, apparmor bool) []string {
	args := []string{"docker", "run", "-d", "--name", builderContainer,
		"--restart", "unless-stopped",
		"--network", "host", // the daemon pushes to the loopback registry
		"--device", "/dev/net/tun", // slirp4netns
		"-v", cacheVolume + ":/home/user/.local/share/buildkit",
		"--security-opt", "seccomp=unconfined", // unshare/mount for runc + snapshotter
		"--security-opt", "systempaths=unconfined", // a fresh /proc per build step
		"--security-opt", "no-new-privileges=false", // newuidmap/newgidmap file caps (dockerd defaults NNP on)
	}
	if apparmor {
		args = append(args, "--security-opt", "apparmor="+apparmorProfileName)
	}
	return append(args,
		"--entrypoint", "rootlesskit", image,
		// Build steps live in a detached slirp4netns namespace that can't
		// reach 127.0.0.1 on the host; buildkitd itself stays on the host net.
		"--net=slirp4netns", "--disable-host-loopback", "--detach-netns",
		"--copy-up=/etc", "--copy-up=/var/lib", "--copy-up=/run",
		"buildkitd", "--oci-worker-net=bridge")
}

func apparmorEnabled() bool {
	b, err := os.ReadFile("/sys/module/apparmor/parameters/enabled")
	return err == nil && strings.TrimSpace(string(b)) == "Y"
}

// ensureApparmorProfile installs and loads the profile when it's missing or
// stale. wokkud runs as root.
func ensureApparmorProfile(ctx context.Context, run func(...string) error) error {
	current, _ := os.ReadFile(apparmorProfilePath)
	loaded, _ := os.ReadFile("/sys/kernel/security/apparmor/profiles")
	if string(current) == apparmorProfile && bytes.Contains(loaded, []byte(apparmorProfileName+" ")) {
		return nil
	}
	if err := os.WriteFile(apparmorProfilePath, []byte(apparmorProfile), 0o644); err != nil {
		return err
	}
	return run("apparmor_parser", "-r", apparmorProfilePath)
}

func ensureRootlessBuilder(ctx context.Context, run func(...string) error, pushRef string) error {
	apparmor := apparmorEnabled()
	if apparmor {
		if err := ensureApparmorProfile(ctx, run); err != nil {
			return fmt.Errorf("apparmor profile: %w", err)
		}
	}

	dockerfile := rootlessImageDockerfile(pushRef)
	image := rootlessImageTag(dockerfile)
	if run("docker", "image", "inspect", image) != nil {
		cmd := exec.CommandContext(ctx, "docker", "build", "-q", "-t", image, "-")
		cmd.Env = BuildEnv(os.Environ())
		cmd.Stdin = strings.NewReader(dockerfile)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("build %s: %v: %s", image, err, strings.TrimSpace(string(out)))
		}
	}

	out, err := exec.CommandContext(ctx, "docker", "inspect", "-f", "{{.Config.Image}} {{.State.Running}}", builderContainer).Output()
	switch state := strings.TrimSpace(string(out)); {
	case err != nil || !strings.HasPrefix(state, image+" "):
		run("docker", "rm", "-f", builderContainer) // absent or outdated
		if err := run(daemonRunArgs(image, apparmor)...); err != nil {
			return err
		}
	case state != image+" true":
		if err := run("docker", "start", builderContainer); err != nil {
			return err
		}
	}

	if run("docker", "buildx", "inspect", builderName) != nil {
		if err := run("docker", "buildx", "create", "--name", builderName,
			"--driver", "remote", "docker-container://"+builderContainer); err != nil {
			return err
		}
	}
	// A freshly started daemon needs a few seconds before it answers.
	var lastErr error
	for i := 0; i < 15; i++ {
		if lastErr = run("docker", "buildx", "inspect", "--bootstrap", builderName); lastErr == nil {
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return lastErr
}
