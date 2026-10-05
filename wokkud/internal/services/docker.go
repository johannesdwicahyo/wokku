// docker.go is the real Docker SDK implementation of dockerAPI (Task 6's
// executor.go placeholder). Same construction pattern as dockermon.New:
// client.FromEnv + WithAPIVersionNegotiation over the host's docker.sock.
package services

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"github.com/containerd/errdefs"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/api/types/network"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/jsonmessage"
	"github.com/docker/docker/pkg/stdcopy"
)

// sqlPasswordRe matches a `PASSWORD '...'` SQL literal, case-insensitive —
// postgres.go's pgProvisionTenant interpolates the tenant's cleartext
// password into a `CREATE ROLE ... PASSWORD '<pw>' ...` psql -c argument.
// Without this, a CREATE ROLE failure other than "already exists" would
// carry the secret through redactArgv into service_ops.error, logs, and
// Sentry (I1).
var sqlPasswordRe = regexp.MustCompile(`(?i)password\s*'[^']*'`)

// redactArgv masks credential-bearing exec arguments before they reach an
// error string (which flows to service_ops.error and logs). mysql/mariadb
// pass the password as `-p<pw>` (one element); mongo passes `-p <pw>` (the
// value in the following element); psql -c SQL carries it as a `PASSWORD
// '<pw>'` literal inside the SQL text itself.
func redactArgv(cmd []string) []string {
	out := make([]string, len(cmd))
	copy(out, cmd)
	for i, a := range out {
		switch {
		case a == "-p" || a == "--password":
			if i+1 < len(out) {
				out[i+1] = "***"
			}
		case strings.HasPrefix(a, "-p") || strings.HasPrefix(a, "--password="):
			out[i] = "-p***"
		case strings.HasPrefix(a, ">"):
			// redis `ACL SETUSER <user> on ><password>` — the tenant
			// password rides argv as a single ">pw" element.
			out[i] = ">***"
		}
		out[i] = sqlPasswordRe.ReplaceAllString(out[i], "PASSWORD '***'")
	}
	return out
}

// ContainerSpec is what service.create needs to stand up a datastore
// container, narrowed from container.Config/HostConfig to exactly the
// fields dedicated.go computes — so fakeDocker in tests records plain
// values instead of constructing real SDK structs.
type ContainerSpec struct {
	Name  string
	Image string
	Env   []string
	Bind  string   // "<host path>:<container path>", empty = no bind mount
	Cmd   []string // nil = image CMD (redis overrides to load /data/redis.conf)
}

// ContainerInfo is ContainerInspect's narrowed return — only what
// service.adopt and set_limits need.
type ContainerInfo struct {
	Image    string
	Env      []string
	Binds    []string // "<host>:<container>" per mount
	Networks []string
	Running  bool
}

// dockerAPI is the narrow Docker surface service-op handlers need — same
// pattern as dockermon's api interface and postgres.go's execer: the
// smallest shape callers need, not the full SDK client. A concrete
// *realDockerAPI's method set is a strict superset of execer's Exec, so it
// can be passed anywhere an execer is expected (Go's structural interface
// assignability) — no adapter type needed.
type dockerAPI interface {
	// ImageEnsure makes the image ref locally available (inspect,
	// pull-if-missing) — service.create on a fresh host has no image yet.
	ImageEnsure(ctx context.Context, ref string) error
	VolumeCreate(ctx context.Context, hostPath string) error
	ContainerCreate(ctx context.Context, spec ContainerSpec) error
	ContainerInspect(ctx context.Context, name string) (ContainerInfo, error)
	ContainerStart(ctx context.Context, name string) error
	ContainerStop(ctx context.Context, name string) error
	ContainerRestart(ctx context.Context, name string) error
	ContainerRemove(ctx context.Context, name string) error
	ContainerUpdate(ctx context.Context, name string, memoryMB int, cpu float64) error
	// ContainerExists reports whether a container with this name exists
	// (any state). A not-found is (false, nil); any other docker error is
	// (false, err) so callers never mistake a broken socket for "missing".
	ContainerExists(ctx context.Context, name string) (bool, error)
	NetworkConnect(ctx context.Context, networkName, name string, aliases ...string) error
	// NetworkEnsure creates the named user-defined bridge network if it
	// doesn't exist (B4 gate 3: the default bridge has no DNS, so
	// hostname DSNs only resolve on a user-defined network).
	NetworkEnsure(ctx context.Context, name string) error
	Exec(ctx context.Context, container, stdin string, cmd ...string) (string, error)
	// ExecStream runs cmd streaming stdin in and stdout out CONCURRENTLY, so
	// a multi-MB dump/restore can't deadlock stdin against an unread stdout
	// (the buffered Exec above writes all stdin first — fine for one-shot
	// SQL, fatal for a stream). stdin may be nil (export). A non-zero exit
	// is an error.
	ExecStream(ctx context.Context, container string, stdin io.Reader, stdout io.Writer, cmd ...string) error
}

type realDockerAPI struct {
	cli *client.Client
}

func newDockerAPI() (*realDockerAPI, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, err
	}
	return &realDockerAPI{cli: cli}, nil
}

// VolumeCreate ensures the bind-mount host directory exists, 0700 (owner
// rw/x only — these dirs hold live database files). Dedicated services
// bind-mount a plain host path (mirrors the current Dokku plugin layout
// under /var/lib/dokku/services/<type>/<name>/data), not a Docker-managed
// named volume, so this is a directory create rather than a
// VolumeCreate API call.
// ponytail: bind mount, not `docker volume create` — matches the existing
// on-disk layout Rails already assumes (VolumePath is a host path in
// CreateParams), no reason to add a second volume-naming scheme.
// ImageEnsure makes the ref locally available: inspect first (never
// re-pulls a tag that's already present — no surprise upgrades), pull on
// not-found. Pull-stream errors surface via jsonmessage (a failed pull
// otherwise "succeeds" with the error only in the JSON lines).
func (r *realDockerAPI) ImageEnsure(ctx context.Context, ref string) error {
	if _, err := r.cli.ImageInspect(ctx, ref); err == nil {
		return nil
	}
	rc, err := r.cli.ImagePull(ctx, ref, image.PullOptions{})
	if err != nil {
		return fmt.Errorf("image pull %s: %w", ref, err)
	}
	defer rc.Close()
	if err := jsonmessage.DisplayJSONMessagesStream(rc, io.Discard, 0, false, nil); err != nil {
		return fmt.Errorf("image pull %s: %w", ref, err)
	}
	return nil
}

func (r *realDockerAPI) VolumeCreate(ctx context.Context, hostPath string) error {
	return os.MkdirAll(hostPath, 0o700)
}

func (r *realDockerAPI) ContainerCreate(ctx context.Context, spec ContainerSpec) error {
	var binds []string
	if spec.Bind != "" {
		binds = []string{spec.Bind}
	}
	cfg := &container.Config{Image: spec.Image, Env: spec.Env, Cmd: spec.Cmd}
	hostCfg := &container.HostConfig{
		Binds: binds,
		// dokku plugin convention: datastore containers always restart with
		// the host. B5 changes app-container restart behavior, not this.
		RestartPolicy: container.RestartPolicy{Name: container.RestartPolicyAlways},
	}
	// Memory/conn limits are applied post-start via the same ContainerUpdate
	// path as service.set_limits (dedicated.go's serviceCreate calls
	// serviceSetLimits right after ContainerStart) — not set here.
	_, err := r.cli.ContainerCreate(ctx, cfg, hostCfg, &network.NetworkingConfig{}, nil, spec.Name)
	return err
}

func (r *realDockerAPI) ContainerInspect(ctx context.Context, name string) (ContainerInfo, error) {
	insp, err := r.cli.ContainerInspect(ctx, name)
	if err != nil {
		return ContainerInfo{}, err
	}
	info := ContainerInfo{Running: insp.State != nil && insp.State.Running}
	if insp.Config != nil {
		info.Image = insp.Config.Image
		info.Env = insp.Config.Env
	}
	for _, m := range insp.Mounts {
		if m.Source != "" && m.Destination != "" {
			info.Binds = append(info.Binds, m.Source+":"+m.Destination)
		}
	}
	if insp.NetworkSettings != nil {
		for netName := range insp.NetworkSettings.Networks {
			info.Networks = append(info.Networks, netName)
		}
	}
	return info, nil
}

func (r *realDockerAPI) ContainerStart(ctx context.Context, name string) error {
	return r.cli.ContainerStart(ctx, name, container.StartOptions{})
}

func (r *realDockerAPI) ContainerStop(ctx context.Context, name string) error {
	return r.cli.ContainerStop(ctx, name, container.StopOptions{})
}

func (r *realDockerAPI) ContainerRestart(ctx context.Context, name string) error {
	return r.cli.ContainerRestart(ctx, name, container.StopOptions{})
}

func (r *realDockerAPI) ContainerRemove(ctx context.Context, name string) error {
	// RemoveVolumes stays false: destroy never deletes data (brief +
	// dedicated.go's serviceDestroy comment) — only the anonymous
	// mount-point record would be removed anyway, never the bind-mounted
	// host directory itself.
	return r.cli.ContainerRemove(ctx, name, container.RemoveOptions{})
}

func (r *realDockerAPI) ContainerUpdate(ctx context.Context, name string, memoryMB int, cpu float64) error {
	res := container.Resources{}
	if memoryMB > 0 {
		mb := int64(memoryMB) * 1024 * 1024
		res.Memory, res.MemorySwap = mb, mb
	}
	if cpu > 0 {
		res.NanoCPUs = int64(cpu * 1e9)
	}
	_, err := r.cli.ContainerUpdate(ctx, name, container.UpdateConfig{Resources: res})
	return err
}

func (r *realDockerAPI) ContainerExists(ctx context.Context, name string) (bool, error) {
	_, err := r.cli.ContainerInspect(ctx, name)
	if err == nil {
		return true, nil
	}
	if errdefs.IsNotFound(err) {
		return false, nil
	}
	return false, err
}

func (r *realDockerAPI) NetworkConnect(ctx context.Context, networkName, name string, aliases ...string) error {
	return r.cli.NetworkConnect(ctx, networkName, name, &network.EndpointSettings{Aliases: aliases})
}

func (r *realDockerAPI) NetworkEnsure(ctx context.Context, name string) error {
	if _, err := r.cli.NetworkInspect(ctx, name, network.InspectOptions{}); err == nil {
		return nil
	}
	_, err := r.cli.NetworkCreate(ctx, name, network.CreateOptions{Driver: "bridge"})
	if err != nil && strings.Contains(err.Error(), "already exists") {
		return nil // lost a create race — the network exists, which is all we need
	}
	return err
}

// Exec runs cmd inside container via ContainerExecCreate/Attach, writes
// stdin if non-empty, and returns combined stdout (stderr folded in on
// failure so the caller's error message carries the engine's complaint).
// A non-zero exit code becomes an error — psql/mysql's ON_ERROR_STOP
// semantics only matter if callers can see the failure.
func (r *realDockerAPI) Exec(ctx context.Context, containerName, stdin string, cmd ...string) (string, error) {
	created, err := r.cli.ContainerExecCreate(ctx, containerName, container.ExecOptions{
		Cmd:          cmd,
		AttachStdin:  stdin != "",
		AttachStdout: true,
		AttachStderr: true,
	})
	if err != nil {
		return "", fmt.Errorf("exec create: %w", err)
	}

	resp, err := r.cli.ContainerExecAttach(ctx, created.ID, container.ExecAttachOptions{})
	if err != nil {
		return "", fmt.Errorf("exec attach: %w", err)
	}
	defer resp.Close()

	if stdin != "" {
		if _, err := resp.Conn.Write([]byte(stdin)); err != nil {
			return "", fmt.Errorf("exec stdin: %w", err)
		}
		_ = resp.CloseWrite()
	}

	var stdout, stderr bytes.Buffer
	if _, err := stdcopy.StdCopy(&stdout, &stderr, resp.Reader); err != nil {
		return "", fmt.Errorf("exec output: %w", err)
	}

	inspect, err := r.cli.ContainerExecInspect(ctx, created.ID)
	if err != nil {
		return "", fmt.Errorf("exec inspect: %w", err)
	}
	if inspect.ExitCode != 0 {
		return stdout.String(), fmt.Errorf("exec %v: exit %d: %s", redactArgv(cmd), inspect.ExitCode, stderr.String())
	}
	return stdout.String(), nil
}

func (r *realDockerAPI) ExecStream(ctx context.Context, containerName string, stdin io.Reader, stdout io.Writer, cmd ...string) error {
	created, err := r.cli.ContainerExecCreate(ctx, containerName, container.ExecOptions{
		Cmd:          cmd,
		AttachStdin:  stdin != nil,
		AttachStdout: true,
		AttachStderr: true,
	})
	if err != nil {
		return fmt.Errorf("exec create: %w", err)
	}

	resp, err := r.cli.ContainerExecAttach(ctx, created.ID, container.ExecAttachOptions{})
	if err != nil {
		return fmt.Errorf("exec attach: %w", err)
	}
	// Closed explicitly after StdCopy (below) so a stuck stdin writer is
	// unblocked before the <-stdinDone wait; every post-attach path passes
	// through that close, so no defer is needed.

	// Copy stdin in its own goroutine while StdCopy drains stdout below —
	// the two run concurrently so neither blocks the other.
	stdinDone := make(chan error, 1)
	if stdin != nil {
		go func() {
			_, cErr := io.Copy(resp.Conn, stdin)
			// EOF on stdin lets the process finish and close stdout.
			if cwErr := resp.CloseWrite(); cErr == nil {
				cErr = cwErr
			}
			stdinDone <- cErr
		}()
	} else {
		stdinDone <- nil
	}

	var stderr bytes.Buffer
	_, copyErr := stdcopy.StdCopy(stdout, &stderr, resp.Reader)
	// Close the hijacked connection now that stdout has drained — this
	// unblocks a stdin goroutine still stuck on resp.Conn.Write against a
	// process that already exited, so the <-stdinDone wait can't hang.
	resp.Close()
	stdinErr := <-stdinDone
	if copyErr != nil {
		return fmt.Errorf("exec output: %w", copyErr)
	}
	if stdinErr != nil {
		return fmt.Errorf("exec stdin: %w", stdinErr)
	}

	inspect, err := r.cli.ContainerExecInspect(ctx, created.ID)
	if err != nil {
		return fmt.Errorf("exec inspect: %w", err)
	}
	if inspect.ExitCode != 0 {
		return fmt.Errorf("exec %v: exit %d: %s", redactArgv(cmd), inspect.ExitCode, stderr.String())
	}
	return nil
}
