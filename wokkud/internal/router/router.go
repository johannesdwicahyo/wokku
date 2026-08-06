// Manager owns the wokku-caddy config lifecycle (Track B phase B1).
// Fail-static: every error path logs, keeps the last-good config serving,
// and leaves `applied` untouched so vitals expose the drift. The next
// heartbeat retries. Sync never returns an error and never panics the agent.
package router

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"

	"wokku.cloud/wokkud/internal/control"
)

type configFetcher interface {
	GetRouterConfig() (*control.RouterConfig, error)
}

type resolveFunc func(ctx context.Context, apps []control.RouterApp) (map[string][]string, error)

type Manager struct {
	fetch    configFetcher
	dir      string // /etc/wokku/caddy
	adminURL string // http://127.0.0.1:2019
	askURL   string
	resolve  resolveFunc
	validate func(ctx context.Context, path string) error
	// validateTimeout bounds caddyValidate's subprocess so a hung `caddy
	// validate` can never wedge Sync (and with it every future heartbeat).
	// Overridden to a few ms in tests; defaults to 10s via New().
	validateTimeout time.Duration

	mu       sync.Mutex
	cfg      *control.RouterConfig
	applied  string // version of the last successfully applied config
	lastJSON []byte
}

// New returns nil when caddy isn't installed on this host — the router
// duty is dark until deploy/install.sh provisions wokku-caddy. All Manager
// methods are nil-safe via the callers in main.go.
func New(f configFetcher, controlURL, token string) *Manager {
	if _, err := exec.LookPath("caddy"); err != nil {
		return nil
	}
	dcli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		log.Printf("router: docker client unavailable, duty dark: %v", err)
		return nil
	}
	return &Manager{
		fetch:           f,
		dir:             "/etc/wokku/caddy",
		adminURL:        "http://127.0.0.1:2019",
		askURL:          fmt.Sprintf("%s/api/v1/agent/router/tls_allowed?token=%s", controlURL, token),
		resolve:         dockerResolver(dcli),
		validate:        caddyValidate,
		validateTimeout: 10 * time.Second,
	}
}

// Sync brings the running Caddy to the control plane's desired config.
// Called every heartbeat; cheap no-op when version and upstreams match.
func (m *Manager) Sync(ctx context.Context, version string) {
	if m == nil || version == "" {
		return
	}
	if !m.mu.TryLock() {
		return // previous sync still running; next beat retries
	}
	defer m.mu.Unlock()

	if version != m.applied || m.cfg == nil {
		cfg, err := m.fetch.GetRouterConfig()
		if err != nil {
			log.Printf("router: config fetch: %v", err)
			return
		}
		m.cfg = cfg
	}

	resolved, err := m.resolve(ctx, m.cfg.Apps)
	if err != nil {
		log.Printf("router: resolve: %v", err)
		return
	}
	rendered, err := Render(m.cfg, resolved, m.askURL, filepath.Join(m.dir, "certs"))
	if err != nil {
		log.Printf("router: render: %v", err)
		return
	}
	if bytes.Equal(rendered, m.lastJSON) {
		return
	}
	if err := m.apply(ctx, rendered); err != nil {
		log.Printf("router: apply: %v", err)
		return
	}
	m.lastJSON = rendered
	m.applied = m.cfg.Version
	log.Printf("router: applied config %s (%d apps)", m.applied, len(m.cfg.Apps))
}

// apply: tmp write → caddy validate → admin /load → persist as last-good.
// Order matters: /load succeeds before the on-disk config.json is replaced,
// so a crash mid-apply still restarts caddy with the previous good config.
func (m *Manager) apply(ctx context.Context, rendered []byte) error {
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	tmp := filepath.Join(m.dir, "config.json.tmp")
	if err := os.WriteFile(tmp, rendered, 0o600); err != nil {
		return err
	}
	defer os.Remove(tmp)

	vctx, vcancel := context.WithTimeout(ctx, m.validateTimeout)
	verr := m.validate(vctx, tmp)
	vcancel()
	if verr != nil {
		if vctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("validate: timed out after %s: %w", m.validateTimeout, verr)
		}
		return fmt.Errorf("validate: %w", verr)
	}

	lctx, lcancel := context.WithTimeout(ctx, 10*time.Second)
	defer lcancel()
	req, err := http.NewRequestWithContext(lctx, http.MethodPost, m.adminURL+"/load", bytes.NewReader(rendered))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("caddy /load: HTTP %d", resp.StatusCode)
	}
	return os.Rename(tmp, filepath.Join(m.dir, "config.json"))
}

// Status reports for vitals: router health + last applied version.
func (m *Manager) Status(ctx context.Context) (router, applied string) {
	if m == nil {
		return "", ""
	}
	m.mu.Lock()
	applied = m.applied
	m.mu.Unlock()

	ctx, cancel := context.WithTimeout(ctx, time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, m.adminURL+"/config/", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "degraded", applied
	}
	resp.Body.Close()
	return "ok", applied
}

func caddyValidate(ctx context.Context, path string) error {
	out, err := exec.CommandContext(ctx, "caddy", "validate", "--config", path).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, out)
	}
	return nil
}

// dockerResolver lists running containers once per sync and maps each app
// to the container IPs of its `<app>.web.N` processes (dokku naming today;
// wokku.* labels join in B5). ponytail: container restarts surface within
// one beat (~15s) via the churn re-render in Sync; B5's rotate does
// explicit flips for zero-downtime.
//
// A failed ContainerList (docker daemon blip) is returned as an error
// rather than swallowed into an empty map: Sync treats resolve errors as
// fail-static and leaves the last-good config alone, instead of rendering
// and applying a config with every local app's upstreams dropped. Per-
// container ContainerInspect errors still `continue` — a container that
// vanished between List and Inspect is a normal race, not a fail-static
// condition.
func dockerResolver(cli *client.Client) resolveFunc {
	return func(ctx context.Context, apps []control.RouterApp) (map[string][]string, error) {
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		out := map[string][]string{}
		list, err := cli.ContainerList(ctx, container.ListOptions{})
		if err != nil {
			return nil, fmt.Errorf("container list: %w", err)
		}
		for _, app := range apps {
			// Only apps carrying a `local` upstream entry need container
			// resolution; Render() also guards this, but skipping it here
			// avoids a wasted container-name scan for dial-only (B5a
			// swarm-port) apps on every heartbeat.
			if !hasLocalUpstream(app) {
				continue
			}
			prefix := "/" + app.Name + ".web."
			for _, c := range list {
				for _, name := range c.Names {
					// Exact `<app>.web.<N>` only: dokku also runs staging
					// containers named `<app>.web.<N>.upcoming-<id>` during
					// deploys — prefix-matching those routed live traffic to
					// half-started containers (shadow soak catch, 2026-07-15).
					if isWebProcessName(name, prefix) {
						insp, err := cli.ContainerInspect(ctx, c.ID)
						if err != nil {
							continue
						}
						for _, netw := range insp.NetworkSettings.Networks {
							if netw.IPAddress != "" {
								out[app.Name] = append(out[app.Name],
									fmt.Sprintf("%s:%d", netw.IPAddress, app.ContainerPort))
								break
							}
						}
					}
				}
			}
		}
		return out, nil
	}
}

// hasLocalUpstream reports whether app declares a `local` upstream entry —
// the only case that needs docker container resolution. Dial-only apps
// (B5a wokkud-lifecycle, swarm port) and mesh-only apps (B8) don't.
func hasLocalUpstream(app control.RouterApp) bool {
	for _, u := range app.Upstreams {
		if u.Local {
			return true
		}
	}
	return false
}

// isWebProcessName reports whether name is exactly prefix followed by
// digits (e.g. "/app.web.12"), rejecting dokku's ".upcoming-" staging names.
func isWebProcessName(name, prefix string) bool {
	if len(name) <= len(prefix) || name[:len(prefix)] != prefix {
		return false
	}
	for _, r := range name[len(prefix):] {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
