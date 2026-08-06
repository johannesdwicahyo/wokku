package cronrun

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"time"
)

// DockerRunner runs an entry as a one-off container from the app's current
// release image — dokku one-off semantics, minus dokku. A never-deployed
// app's image_ref ("dokku/<app>:latest") simply won't exist on the host;
// `docker run` fails and that failure flows back as a non-zero exit code +
// log excerpt, same as any other command failure — never a crash.
type DockerRunner struct{}

// execRunDocker invokes the docker CLI and captures combined output. A
// package var so tests can fake process execution without a real docker
// daemon.
var execRunDocker = func(ctx context.Context, env []string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Env = env
	return cmd.CombinedOutput()
}

// execReapContainer force-removes a container by name, best-effort (error
// ignored). On a normal exit `--rm` already cleaned it up, so this usually
// no-ops; it only matters when ctx timeout SIGKILLed the docker CLI before
// it could clean up after itself, which otherwise orphans the container
// every interval and — since `docker run --name X` fails outright while X
// still exists — would also wedge the next fire.
var execReapContainer = func(name string) {
	_ = exec.Command("docker", "rm", "-f", name).Run()
}

func (DockerRunner) Run(e Entry, env map[string]string) (int, string) {
	timeout := time.Duration(e.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 15 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	containerName := "wokku-cron-" + e.ID
	args := []string{"run", "--rm", "--name", containerName, "--label", "wokku.cron=" + e.ID}
	for _, n := range e.Networks {
		args = append(args, "--network", n)
	}
	cmdEnv := os.Environ()
	for k, v := range env {
		args = append(args, "-e", k) // value comes from our env, not argv
		cmdEnv = append(cmdEnv, k+"="+v)
	}
	// ponytail: no resource limits on one-offs — dokku parity; B5 owns limits.
	args = append(args, e.ImageRef, "sh", "-c", e.Command)

	defer execReapContainer(containerName)

	out, err := execRunDocker(ctx, cmdEnv, args...)
	if ctx.Err() == context.DeadlineExceeded {
		return 124, string(out) + "\nwokku: task timed out"
	}
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode(), string(out)
		}
		return 125, string(out) + fmt.Sprintf("\nwokku: docker run failed: %v", err)
	}
	return 0, string(out)
}
