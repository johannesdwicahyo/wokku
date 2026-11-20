package builder

import (
	"strings"
	"testing"
)

// Security assessment 2026-11-19, F-01: tenant builds run under a rootless
// BuildKit daemon — no host root, no privileged container, build steps on
// their own network without the host's loopback.

func TestRootlessImageDockerfile(t *testing.T) {
	df := rootlessImageDockerfile("127.0.0.1:5000/wokku/blog:1")
	for _, want := range []string{
		"FROM " + buildkitRootlessImage,
		"apk add --no-cache slirp4netns iproute2 iptables",
		"user:x:61000:61000:",           // dedicated host uid, never 1000 (a real login on our hosts)
		"user:3000000:65536",            // dedicated subordinate range
		`[registry.\"127.0.0.1:5000\"]`, // loopback registry is plain http
		"USER 61000:61000",
		"XDG_RUNTIME_DIR=/run/user/61000",
	} {
		if !strings.Contains(df, want) {
			t.Errorf("Dockerfile missing %q:\n%s", want, df)
		}
	}
	if strings.Contains(rootlessImageDockerfile("registry.example.com/x:1"), "http = true") {
		t.Error("a remote registry must stay https")
	}
}

func TestRootlessImageTagFollowsTheDockerfile(t *testing.T) {
	a := rootlessImageTag(rootlessImageDockerfile("127.0.0.1:5000/a:1"))
	b := rootlessImageTag(rootlessImageDockerfile("127.0.0.1:5000/b:2"))
	c := rootlessImageTag(rootlessImageDockerfile("registry.example.com/a:1"))
	if a != b {
		t.Errorf("same registry, different tags: %s %s", a, b)
	}
	if a == c {
		t.Error("a config change must produce a new image tag")
	}
	if !strings.HasPrefix(a, "wokku/buildkit-rootless:") {
		t.Errorf("tag = %s", a)
	}
}

func TestDaemonRunArgs(t *testing.T) {
	args := strings.Join(daemonRunArgs("wokku/buildkit-rootless:abc", true), " ")
	for _, want := range []string{
		"--name " + builderContainer,
		"--network host", // the daemon pushes to the loopback registry…
		"--device /dev/net/tun",
		"--security-opt apparmor=" + apparmorProfileName,
		"--security-opt seccomp=unconfined",
		"--security-opt systempaths=unconfined",
		"--security-opt no-new-privileges=false", // newuidmap's file capability
		"--entrypoint rootlesskit wokku/buildkit-rootless:abc",
		"--net=slirp4netns --disable-host-loopback", // …while build steps can't reach it
		"--detach-netns",
		"buildkitd --oci-worker-net=bridge",
		"-v " + cacheVolume + ":/home/user/.local/share/buildkit",
	} {
		if !strings.Contains(args, want) {
			t.Errorf("run args missing %q:\n%s", want, args)
		}
	}
	if strings.Contains(args, "--privileged") || strings.Contains(args, "--user 0") {
		t.Errorf("builder must not run privileged or as root: %s", args)
	}
	if strings.Contains(strings.Join(daemonRunArgs("img", false), " "), "apparmor=") {
		t.Error("no AppArmor option on a host without AppArmor")
	}
}

func TestApparmorProfileOnlyAllowsUserNamespaces(t *testing.T) {
	for _, want := range []string{"profile " + apparmorProfileName + " flags=(unconfined)", "userns,"} {
		if !strings.Contains(apparmorProfile, want) {
			t.Errorf("profile missing %q", want)
		}
	}
}
