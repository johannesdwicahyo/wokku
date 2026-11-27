// Package control is an HTTP client for the control plane's /api/v1/agent endpoints.
// Heartbeats are fire-and-forget (the next beat is 15s away); events
// retry briefly because a crash report is worth a little persistence.
// ponytail: in-memory retry only — no disk buffer. If the control plane
// is down longer than ~7s we drop the event; the CrashLoopDetector
// SSH-poll path still catches persistent loops.
package control

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"wokku.cloud/wokkud/internal/cronrun"
	"wokku.cloud/wokkud/internal/vitals"
)

type Event struct {
	Type        string    `json:"type"`
	Container   string    `json:"container"`
	App         string    `json:"app"`
	ContainerID string    `json:"container_id"`
	ExitCode    int       `json:"exit_code"`
	OOMKilled   bool      `json:"oom_killed"`
	ExitedAt    time.Time `json:"exited_at"`
	LogExcerpt  string    `json:"log_excerpt"`
}

type Client struct {
	baseURL     string
	token       string
	version     string
	http        *http.Client
	envHTTP     *http.Client
	backoffBase time.Duration
}

func New(baseURL, token, version string) *Client {
	return &Client{
		baseURL: baseURL,
		token:   token,
		version: version,
		http:    &http.Client{Timeout: 5 * time.Second},
		// GetAppEnv's request does a host SSH round-trip (Rails runs a
		// synchronous `dokku config:show` per fire), unlike every other
		// fast in-process config GET on this client. The shared 5s
		// timeout was tripping on tail latency and skipping the fire as
		// env_fetch_failed — a silently missed cron run, not just a slow
		// one. Give it its own longer budget.
		envHTTP:     &http.Client{Timeout: 30 * time.Second},
		backoffBase: time.Second,
	}
}

type HeartbeatResponse struct {
	Status                string   `json:"status"`
	PendingBuildIDs       []string `json:"pending_build_ids"`
	PendingServiceOpIDs   []string `json:"pending_service_op_ids"`
	PendingLifecycleOpIDs []string `json:"pending_lifecycle_op_ids"`
	RouterConfigVersion   string   `json:"router_config_version"`
	CronConfigVersion     string   `json:"cron_config_version"`
	PendingImageScanIDs   []string `json:"pending_image_scan_ids"`
}

// TaskState is one Swarm task's state slice, riding the heartbeat REQUEST
// body (Track B Phase B5a) so the control plane can fan container state out
// to app_records.live_containers.
type TaskState struct {
	App          string    `json:"app"`
	Process      string    `json:"process"`
	State        string    `json:"state"`
	DesiredState string    `json:"desired_state"`
	StartedAt    time.Time `json:"started_at"`
	ExitCode     int       `json:"exit_code"`
}

// LifecycleOp is a Swarm stack op (stack.converge / stack.remove) claimed
// off the heartbeat's pending_lifecycle_op_ids, mirroring ServiceOp.
type LifecycleOp struct {
	ID             string          `json:"id"`
	Kind           string          `json:"kind"`
	AppName        string          `json:"app_name"`
	Params         json.RawMessage `json:"params"`
	TimeoutSeconds int             `json:"timeout_seconds"`
}

// ServiceOp is a datastore-lifecycle operation (restart/backup/etc.) claimed
// off the heartbeat's pending_service_op_ids, mirroring BuildJob.
type ServiceOp struct {
	ID             string          `json:"id"`
	Kind           string          `json:"kind"`
	Service        string          `json:"service"`
	Params         json.RawMessage `json:"params"`
	TimeoutSeconds int             `json:"timeout_seconds"`
}

type BuildJob struct {
	ID             string `json:"-"`
	AppName        string `json:"app_name"`
	ArchiveURL     string `json:"archive_url"`
	PushRef        string `json:"push_ref"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}

// Router config wire types (Track B phase B1). Fetched when the heartbeat's
// router_config_version differs from what the router last applied.
type RouterConfig struct {
	Version      string      `json:"version"`
	ListenMode   string      `json:"listen_mode"` // "shadow" (8080/8443) | "live" (80/443)
	WildcardCert *RouterCert `json:"wildcard_cert"`
	Apps         []RouterApp `json:"apps"`
}

type RouterCert struct {
	FullchainPEM string   `json:"fullchain_pem"`
	KeyPEM       string   `json:"key_pem"`
	SANs         []string `json:"sans"`
}

type RouterApp struct {
	Name          string           `json:"name"`
	ContainerPort int              `json:"container_port"`
	Domains       []RouterDomain   `json:"domains"`
	Upstreams     []RouterUpstream `json:"upstreams"`
	// Maintenance renders the app's vhosts as a static 503 page instead of
	// reverse_proxy (W7). The control plane emits the key only when true;
	// absent decodes to false, and agents older than this field ignore it
	// (plain json.Unmarshal — unknown fields are dropped). Safe both ways.
	Maintenance bool `json:"maintenance,omitempty"`
	// Wake (2026-10-19): set only for a sleeping app — its vhosts proxy to
	// the control plane's wake endpoint instead of the stopped upstream.
	// Absent for every other app (and ignored by older agents).
	Wake *RouterWake `json:"wake,omitempty"`
}

type RouterWake struct {
	Upstream string `json:"upstream"` // control-plane host, e.g. "wokku.cloud"
	Path     string `json:"path"`     // "/__wake/<signed token>"
}

type RouterDomain struct {
	Hostname string `json:"hostname"`
	TLS      string `json:"tls"` // "wildcard" | "on_demand" | "none"
}

type RouterUpstream struct {
	Local  bool   `json:"local,omitempty"`
	Dial   string `json:"dial,omitempty"`    // wokkud-lifecycle apps: "127.0.0.1:<swarm_port>", rendered verbatim (Track B phase B5a)
	MeshIP string `json:"mesh_ip,omitempty"` // populated from B8; rendered verbatim
	Port   int    `json:"port,omitempty"`
}

func (c *Client) GetRouterConfig() (*RouterConfig, error) {
	body, err := c.get("/api/v1/agent/router/config")
	if err != nil {
		return nil, err
	}
	cfg := &RouterConfig{}
	if err := json.Unmarshal(body, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// PostHeartbeat ships vitals plus the live Swarm task states (B5a). tasks is
// omitted from the body when empty so pre-B5a control planes and hosts with
// the lifecycle duty dark see an unchanged request.
func (c *Client) PostHeartbeat(v vitals.Vitals, tasks []TaskState) (HeartbeatResponse, error) {
	var out HeartbeatResponse
	payload := map[string]any{
		"vitals":        v,
		"agent_version": c.version,
	}
	if len(tasks) > 0 {
		payload["tasks"] = tasks
	}
	body, err := c.post("/api/v1/agent/heartbeat", payload)
	if err != nil {
		return out, err
	}
	_ = json.Unmarshal(body, &out) // tolerate a pre-4c body — the beat still landed
	return out, nil
}

func (c *Client) PostEvents(events []Event) error {
	return c.postWithRetry("/api/v1/agent/events", map[string]any{"events": events})
}

// postWithRetry is the shared 3x/1s-2s retry loop used by any POST worth a
// little persistence (events, cron run reports — a crash report or a cron
// result is worth surviving a blip; heartbeats are not, the next one is
// seconds away).
func (c *Client) postWithRetry(path string, payload any) error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(c.backoffBase << (attempt - 1)) // 1s, 2s
		}
		if _, err = c.post(path, payload); err == nil {
			return nil
		}
	}
	return fmt.Errorf("%s dropped after retries: %w", path, err)
}

// GetCronConfig fetches the declarative cron payload (Track B B3).
func (c *Client) GetCronConfig() (*cronrun.Config, error) {
	body, err := c.get("/api/v1/agent/cron/config")
	if err != nil {
		return nil, err
	}
	cfg := &cronrun.Config{}
	if err := json.Unmarshal(body, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// PostCronRuns batch-reports run results; retried like events (3x, 1s/2s).
func (c *Client) PostCronRuns(runs []cronrun.Run) error {
	return c.postWithRetry("/api/v1/agent/cron_runs", map[string]any{"runs": runs})
}

// GetAppEnv fetches an app's env at fire time. Uses envHTTP (30s), not the
// shared 5s client — see the comment on envHTTP in New().
func (c *Client) GetAppEnv(app string) (map[string]string, error) {
	body, err := c.getWith(c.envHTTP, "/api/v1/agent/apps/"+app+"/env")
	if err != nil {
		return nil, err
	}
	var out struct {
		Env map[string]string `json:"env"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, err
	}
	return out.Env, nil
}

// ClaimBuild returns (nil, nil) when the control plane refuses the claim
// (404 not ours / 409 already claimed / 410 deploy finished) — the build
// is simply not ours to run. Anything else is a real error.
func (c *Client) ClaimBuild(id string) (*BuildJob, error) {
	body, err := c.post("/api/v1/agent/builds/"+id+"/claim", map[string]any{})
	if err != nil {
		var he *httpError
		if errors.As(err, &he) && (he.status == 404 || he.status == 409 || he.status == 410) {
			return nil, nil
		}
		return nil, err
	}
	job := &BuildJob{ID: id}
	if err := json.Unmarshal(body, job); err != nil {
		return nil, err
	}
	return job, nil
}

func (c *Client) PostBuildLog(id, chunk string) error {
	_, err := c.post("/api/v1/agent/builds/"+id+"/log", map[string]any{"chunk": chunk})
	return err
}

// buildReportPayload is the wire body for ReportBuild. Formation is omitted
// entirely when nil (no Procfile found) so old control planes see the same
// body as before this field existed.
type buildReportPayload struct {
	Status    string            `json:"status"`
	Error     string            `json:"error,omitempty"`
	Formation map[string]string `json:"formation,omitempty"`
}

// ReportBuild retries like PostEvents: TarballDeployJob is blocked waiting
// on this write — dropping it costs a 15-minute timeout, so it's worth a
// little persistence. formation is the Procfile's raw process-type ->
// command map (nil when there's no Procfile).
func (c *Client) ReportBuild(id, status, errMsg string, formation map[string]string) error {
	payload := buildReportPayload{Status: status, Error: errMsg, Formation: formation}
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(c.backoffBase << (attempt - 1))
		}
		if _, err = c.post("/api/v1/agent/builds/"+id+"/report", payload); err == nil {
			return nil
		}
	}
	return fmt.Errorf("build report dropped after retries: %w", err)
}

// ClaimServiceOp returns (nil, nil) when the control plane refuses the claim
// (404 not ours / 409 already claimed / 410 already settled) — mirrors
// ClaimBuild's refusal semantics.
func (c *Client) ClaimServiceOp(id string) (*ServiceOp, error) {
	body, err := c.post("/api/v1/agent/service_ops/"+id+"/claim", map[string]any{})
	if err != nil {
		var he *httpError
		if errors.As(err, &he) && (he.status == 404 || he.status == 409 || he.status == 410) {
			return nil, nil
		}
		return nil, err
	}
	op := &ServiceOp{ID: id}
	if err := json.Unmarshal(body, op); err != nil {
		return nil, err
	}
	return op, nil
}

func (c *Client) PostServiceOpLog(id, chunk string) error {
	_, err := c.post("/api/v1/agent/service_ops/"+id+"/log", map[string]any{"chunk": chunk})
	return err
}

// ReportServiceOp retries like ReportBuild. A 410 means the control plane
// already considers the op settled (e.g. a late duplicate report racing a
// terminal claim/report from elsewhere) — that's confirmation, not failure,
// so it's treated as success and not retried.
func (c *Client) ReportServiceOp(id, status string, result any, errMsg, errCode string) error {
	return c.reportOp("/api/v1/agent/service_ops/"+id+"/report", status, result, errMsg, errCode)
}

// ClaimLifecycleOp mirrors ClaimServiceOp's refusal semantics (404/409/410
// → nil, nil) for Swarm stack ops (Track B Phase B5a).
func (c *Client) ClaimLifecycleOp(id string) (*LifecycleOp, error) {
	body, err := c.post("/api/v1/agent/lifecycle_ops/"+id+"/claim", map[string]any{})
	if err != nil {
		var he *httpError
		if errors.As(err, &he) && (he.status == 404 || he.status == 409 || he.status == 410) {
			return nil, nil
		}
		return nil, err
	}
	op := &LifecycleOp{ID: id}
	if err := json.Unmarshal(body, op); err != nil {
		return nil, err
	}
	return op, nil
}

func (c *Client) PostLifecycleOpLog(id, chunk string) error {
	_, err := c.post("/api/v1/agent/lifecycle_ops/"+id+"/log", map[string]any{"chunk": chunk})
	return err
}

// ReportLifecycleOp: same retry/410 semantics as ReportServiceOp.
func (c *Client) ReportLifecycleOp(id, status string, result any, errMsg, errCode string) error {
	return c.reportOp("/api/v1/agent/lifecycle_ops/"+id+"/report", status, result, errMsg, errCode)
}

// reportOp is the shared op-report POST: 3x retry with backoff, 410 treated
// as already-settled success.
func (c *Client) reportOp(path, status string, result any, errMsg, errCode string) error {
	payload := map[string]any{"status": status}
	if result != nil {
		payload["result"] = result
	}
	if errMsg != "" {
		payload["error"] = errMsg
	}
	if errCode != "" {
		payload["error_code"] = errCode
	}
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(c.backoffBase << (attempt - 1))
		}
		_, err = c.post(path, payload)
		if err == nil {
			return nil
		}
		var he *httpError
		if errors.As(err, &he) && he.status == 410 {
			return nil
		}
	}
	return fmt.Errorf("op report dropped after retries: %w", err)
}

// ImageScanJob is a Trivy scan of an already-pushed image, claimed off the
// heartbeat's pending_image_scan_ids.
type ImageScanJob struct {
	ID             string `json:"-"`
	ImageRef       string `json:"image_ref"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}

// ImageScanFinding is one reported vulnerability (at most 50 per scan).
type ImageScanFinding struct {
	ID        string `json:"id"`
	Package   string `json:"package"`
	Installed string `json:"installed"`
	Fixed     string `json:"fixed"`
	Severity  string `json:"severity"`
	Title     string `json:"title"`
}

// ImageScanReport is the report body: counts + top findings only, never
// the raw scanner output.
type ImageScanReport struct {
	Status         string             `json:"status"` // "succeeded" | "failed"
	Counts         map[string]int     `json:"counts,omitempty"`
	Findings       []ImageScanFinding `json:"findings,omitempty"`
	ScannerVersion string             `json:"scanner_version,omitempty"`
	DBUpdatedAt    string             `json:"db_updated_at,omitempty"`
	ErrorCode      string             `json:"error_code,omitempty"`
	Error          string             `json:"error,omitempty"`
}

// ClaimImageScan mirrors ClaimBuild: 404 (not this server) / 409 (not
// pending) / 410 → (nil, nil).
func (c *Client) ClaimImageScan(id string) (*ImageScanJob, error) {
	body, err := c.post("/api/v1/agent/image_scans/"+id+"/claim", map[string]any{})
	if err != nil {
		var he *httpError
		if errors.As(err, &he) && (he.status == 404 || he.status == 409 || he.status == 410) {
			return nil, nil
		}
		return nil, err
	}
	job := &ImageScanJob{ID: id}
	if err := json.Unmarshal(body, job); err != nil {
		return nil, err
	}
	return job, nil
}

// ReportImageScan retries 3x like ReportBuild. A 409 (no longer claimed)
// is final — retrying can't change it.
func (c *Client) ReportImageScan(id string, r ImageScanReport) error {
	var err error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(c.backoffBase << (attempt - 1))
		}
		_, err = c.post("/api/v1/agent/image_scans/"+id+"/report", r)
		var he *httpError
		if err == nil || (errors.As(err, &he) && he.status == 409) {
			return err
		}
	}
	return fmt.Errorf("image scan report dropped after retries: %w", err)
}

type httpError struct {
	path   string
	status int
}

func (e *httpError) Error() string { return fmt.Sprintf("%s: HTTP %d", e.path, e.status) }

func (c *Client) get(path string) ([]byte, error) {
	return c.getWith(c.http, path)
}

func (c *Client) getWith(client *http.Client, path string) ([]byte, error) {
	req, err := http.NewRequest(http.MethodGet, c.baseURL+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode >= 300 {
		return nil, &httpError{path: path, status: resp.StatusCode}
	}
	return data, nil
}

func (c *Client) post(path string, payload any) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return nil, &httpError{path: path, status: resp.StatusCode}
	}
	return data, nil
}
