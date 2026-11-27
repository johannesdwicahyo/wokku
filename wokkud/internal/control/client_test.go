package control

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"wokku.cloud/wokkud/internal/cronrun"
	"wokku.cloud/wokkud/internal/vitals"
)

func TestPostHeartbeat(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/heartbeat" {
			t.Errorf("path: %s", r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer tok123" {
			t.Errorf("auth: %s", r.Header.Get("Authorization"))
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	c := New(srv.URL, "tok123", "0.1.0")
	_, err := c.PostHeartbeat(vitals.Vitals{Docker: "ok", DiskUsedPct: 41.5}, nil)
	if err != nil {
		t.Fatalf("PostHeartbeat: %v", err)
	}
	v := got["vitals"].(map[string]any)
	if v["docker"] != "ok" || v["disk_used_pct"].(float64) != 41.5 {
		t.Fatalf("payload: %+v", got)
	}
	if got["agent_version"] != "0.1.0" {
		t.Fatalf("agent_version: %+v", got)
	}
}

func TestPostEventsRetries(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) < 3 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	c := New(srv.URL, "tok123", "0.1.0")
	c.backoffBase = time.Millisecond // keep the test fast
	err := c.PostEvents([]Event{{Type: "container.died", Container: "myapp.web.1", ExitCode: 137}})
	if err != nil {
		t.Fatalf("PostEvents: %v", err)
	}
	if calls.Load() != 3 {
		t.Fatalf("calls: %d", calls.Load())
	}
}

func TestPostEventsGivesUp(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()

	c := New(srv.URL, "tok123", "0.1.0")
	c.backoffBase = time.Millisecond
	if err := c.PostEvents([]Event{{Type: "container.died"}}); err == nil {
		t.Fatal("expected error after retries exhausted")
	}
}

func TestPostHeartbeatParsesPendingBuildIDs(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok","pending_build_ids":["id-1","id-2"]}`))
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.2.0")
	resp, err := c.PostHeartbeat(vitals.Vitals{}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if resp.Status != "ok" || len(resp.PendingBuildIDs) != 2 {
		t.Fatalf("got %+v", resp)
	}
}

func TestPostHeartbeatToleratesLegacyBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.2.0")
	resp, err := c.PostHeartbeat(vitals.Vitals{}, nil)
	if err != nil || len(resp.PendingBuildIDs) != 0 {
		t.Fatalf("resp=%+v err=%v", resp, err)
	}
}

func TestClaimBuild(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/builds/id-1/claim" {
			t.Fatalf("path %s", r.URL.Path)
		}
		w.Write([]byte(`{"app_name":"blog","archive_url":"https://r2/x","push_ref":"127.0.0.1:5000/wokku/blog:id-1","timeout_seconds":600}`))
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.2.0")
	job, err := c.ClaimBuild("id-1")
	if err != nil || job == nil {
		t.Fatalf("job=%v err=%v", job, err)
	}
	if job.ID != "id-1" || job.AppName != "blog" || job.PushRef == "" || job.TimeoutSeconds != 600 {
		t.Fatalf("got %+v", job)
	}
}

func TestClaimBuildRefusalsAreNotErrors(t *testing.T) {
	for _, code := range []int{404, 409, 410} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(code)
		}))
		c := New(srv.URL, "tok", "0.2.0")
		job, err := c.ClaimBuild("id-1")
		srv.Close()
		if job != nil || err != nil {
			t.Fatalf("code %d: job=%v err=%v", code, job, err)
		}
	}
}

func TestClaimBuildServerErrorIsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(500)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.2.0")
	if _, err := c.ClaimBuild("id-1"); err == nil {
		t.Fatal("want error on 500")
	}
}

func TestGetRouterConfig(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/api/v1/agent/router/config" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer tok" {
			t.Errorf("auth header = %q", got)
		}
		// "future_field" pins unknown-field tolerance: an agent at this
		// version must decode configs from a NEWER control plane (the
		// maintenance rollout relies on old agents dropping the new key).
		fmt.Fprint(w, `{"version":"abc","listen_mode":"shadow",
			"wildcard_cert":{"fullchain_pem":"CERT","key_pem":"KEY","sans":["*.wokku.app"]},
			"apps":[{"name":"alpha","container_port":5000,
				"domains":[{"hostname":"alpha.wokku.app","tls":"wildcard"}],
				"upstreams":[{"local":true}],"future_field":true},
				{"name":"beta","container_port":5000,
				"domains":[{"hostname":"beta.wokku.app","tls":"wildcard"}],
				"upstreams":[{"local":true}],"maintenance":true}]}`)
	}))
	defer srv.Close()

	c := New(srv.URL, "tok", "0.3.0")
	cfg, err := c.GetRouterConfig()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Version != "abc" || cfg.ListenMode != "shadow" {
		t.Errorf("cfg = %+v", cfg)
	}
	if len(cfg.Apps) != 2 || cfg.Apps[0].ContainerPort != 5000 || !cfg.Apps[0].Upstreams[0].Local {
		t.Errorf("apps = %+v", cfg.Apps)
	}
	// Missing field decodes false; present field decodes true (W7).
	if cfg.Apps[0].Maintenance || !cfg.Apps[1].Maintenance {
		t.Errorf("maintenance decode: alpha=%v beta=%v, want false/true",
			cfg.Apps[0].Maintenance, cfg.Apps[1].Maintenance)
	}
	if cfg.WildcardCert == nil || cfg.WildcardCert.KeyPEM != "KEY" {
		t.Errorf("cert = %+v", cfg.WildcardCert)
	}
}

func TestHeartbeatResponseRouterVersion(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"status":"ok","router_config_version":"abc"}`)
	}))
	defer srv.Close()

	resp, err := New(srv.URL, "tok", "0.3.0").PostHeartbeat(vitals.Vitals{Docker: "ok"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if resp.RouterConfigVersion != "abc" {
		t.Errorf("RouterConfigVersion = %q", resp.RouterConfigVersion)
	}
}

func TestClaimServiceOpRefusals(t *testing.T) {
	for _, code := range []int{404, 409, 410} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(code)
		}))
		c := New(srv.URL, "tok", "0.5.0")
		op, err := c.ClaimServiceOp("abc")
		if op != nil || err != nil {
			t.Fatalf("code %d: want nil,nil got %v,%v", code, op, err)
		}
		srv.Close()
	}
}

func TestClaimServiceOpSuccess(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/service_ops/abc/claim" {
			t.Errorf("path %s", r.URL.Path)
		}
		fmt.Fprint(w, `{"id":"abc","kind":"service.restart","service":"mydb","params":{},"timeout_seconds":300}`)
	}))
	defer srv.Close()
	op, err := New(srv.URL, "tok", "0.5.0").ClaimServiceOp("abc")
	if err != nil || op == nil || op.Kind != "service.restart" || op.Service != "mydb" {
		t.Fatalf("got %+v, %v", op, err)
	}
	if op.ID != "abc" {
		t.Fatalf("ID not set client-side: %+v", op)
	}
}

func TestHeartbeatParsesServiceOpIDs(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"status":"ok","pending_service_op_ids":["x","y"]}`)
	}))
	defer srv.Close()
	resp, err := New(srv.URL, "tok", "0.5.0").PostHeartbeat(vitals.Vitals{}, nil)
	if err != nil || len(resp.PendingServiceOpIDs) != 2 {
		t.Fatalf("got %+v, %v", resp, err)
	}
}

func TestPostServiceOpLog(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/service_ops/abc/log" {
			t.Errorf("path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	err := New(srv.URL, "tok", "0.5.0").PostServiceOpLog("abc", "some log chunk")
	if err != nil {
		t.Fatalf("PostServiceOpLog: %v", err)
	}
	if got["chunk"] != "some log chunk" {
		t.Fatalf("payload: %+v", got)
	}
}

func TestPostServiceOpLogSingleTry(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.5.0")
	if err := c.PostServiceOpLog("abc", "chunk"); err == nil {
		t.Fatal("expected error on 502")
	}
	if calls.Load() != 1 {
		t.Fatalf("expected single try (fire-and-forget), got %d calls", calls.Load())
	}
}

func TestReportServiceOpRetries(t *testing.T) {
	var calls atomic.Int32
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) < 3 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	c := New(srv.URL, "tok", "0.5.0")
	c.backoffBase = time.Millisecond
	err := c.ReportServiceOp("abc", "succeeded", map[string]any{"ok": true}, "", "")
	if err != nil {
		t.Fatalf("ReportServiceOp: %v", err)
	}
	if calls.Load() != 3 {
		t.Fatalf("calls: %d", calls.Load())
	}
	if got["status"] != "succeeded" {
		t.Fatalf("payload: %+v", got)
	}
	if _, ok := got["error"]; ok {
		t.Fatalf("error key should be omitted when empty: %+v", got)
	}
	if _, ok := got["error_code"]; ok {
		t.Fatalf("error_code key should be omitted when empty: %+v", got)
	}
}

func TestReportServiceOpGivesUp(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.5.0")
	c.backoffBase = time.Millisecond
	if err := c.ReportServiceOp("abc", "failed", nil, "boom", "E_BOOM"); err == nil {
		t.Fatal("expected error after retries exhausted")
	}
}

// A late duplicate report can race a terminal claim/report from elsewhere;
// the control plane answers 410 Gone once the op is already settled. That's
// not a transport failure — it's confirmation the op is done — so it must
// not retry and must return nil.
func TestReportServiceOp410IsTerminalSuccess(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusGone)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.5.0")
	c.backoffBase = time.Millisecond
	err := c.ReportServiceOp("abc", "succeeded", nil, "", "")
	if err != nil {
		t.Fatalf("410 should be treated as already-settled success, got err: %v", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("410 must not be retried, got %d calls", calls.Load())
	}
}

// Track B B3 (cron): heartbeat carries cron_config_version so the agent
// knows to (re)fetch the schedule.
func TestHeartbeatCarriesCronVersion(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"ok","cron_config_version":"abc"}`))
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.6.0")
	resp, err := c.PostHeartbeat(vitals.Vitals{}, nil)
	if err != nil || resp.CronConfigVersion != "abc" {
		t.Fatalf("got %+v err %v", resp, err)
	}
}

func TestGetCronConfig(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/cron/config" {
			t.Fatalf("path %s", r.URL.Path)
		}
		w.Write([]byte(`{"version":"v1","entries":[{"id":"t1","app":"a","schedule":"* * * * *","command":"true","timeout_seconds":5,"image_ref":"dokku/a:latest","networks":["n1"]}]}`))
	}))
	defer srv.Close()
	cfg, err := New(srv.URL, "tok", "0.6.0").GetCronConfig()
	if err != nil || cfg.Version != "v1" || len(cfg.Entries) != 1 || cfg.Entries[0].Networks[0] != "n1" {
		t.Fatalf("cfg %+v err %v", cfg, err)
	}
}

func TestPostCronRuns(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/cron_runs" {
			t.Fatalf("path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	code := 0
	run := cronrun.Run{TaskID: "t1", ExitCode: &code}
	if err := New(srv.URL, "tok", "0.6.0").PostCronRuns([]cronrun.Run{run}); err != nil {
		t.Fatalf("PostCronRuns: %v", err)
	}
	runs, ok := got["runs"].([]any)
	if !ok || len(runs) != 1 {
		t.Fatalf("payload: %+v", got)
	}
}

func TestPostCronRunsRetries(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) < 3 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.6.0")
	c.backoffBase = time.Millisecond
	if err := c.PostCronRuns([]cronrun.Run{{TaskID: "t1"}}); err != nil {
		t.Fatalf("PostCronRuns: %v", err)
	}
	if calls.Load() != 3 {
		t.Fatalf("calls: %d", calls.Load())
	}
}

// GetAppEnv's request does a host SSH round-trip on the Rails side
// (config:show), unlike every other fast in-process GET on this client —
// it needs a longer budget than the shared 5s http.Client or tail latency
// gets misread as env_fetch_failed (a silently missed cron fire).
func TestGetAppEnvUsesDedicatedLongerTimeout(t *testing.T) {
	c := New("http://example.invalid", "tok", "0.6.0")
	if c.envHTTP.Timeout != 30*time.Second {
		t.Fatalf("envHTTP.Timeout = %v, want 30s", c.envHTTP.Timeout)
	}
	if c.envHTTP == c.http {
		t.Fatal("envHTTP must be a distinct client from the shared 5s http client")
	}
}

func TestGetAppEnv(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/apps/myapp/env" {
			t.Fatalf("path %s", r.URL.Path)
		}
		w.Write([]byte(`{"env":{"DATABASE_URL":"postgres://x"}}`))
	}))
	defer srv.Close()
	env, err := New(srv.URL, "tok", "0.6.0").GetAppEnv("myapp")
	if err != nil || env["DATABASE_URL"] != "postgres://x" {
		t.Fatalf("env %+v err %v", env, err)
	}
}

// --- Track B Phase B5a: lifecycle ops + task-state heartbeat ---------------

func TestPostHeartbeatCarriesTasksAndParsesLifecycleOpIDs(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.Write([]byte(`{"status":"ok","pending_lifecycle_op_ids":["l1","l2"]}`))
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.7.0")
	resp, err := c.PostHeartbeat(vitals.Vitals{Docker: "ok"}, []TaskState{
		{App: "blog", Process: "web", State: "running", DesiredState: "running"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.PendingLifecycleOpIDs) != 2 || resp.PendingLifecycleOpIDs[0] != "l1" {
		t.Fatalf("resp %+v", resp)
	}
	tasks, ok := got["tasks"].([]any)
	if !ok || len(tasks) != 1 {
		t.Fatalf("tasks payload: %+v", got)
	}
	task := tasks[0].(map[string]any)
	if task["app"] != "blog" || task["process"] != "web" || task["state"] != "running" || task["desired_state"] != "running" {
		t.Fatalf("task: %+v", task)
	}
}

func TestPostHeartbeatOmitsTasksWhenEmpty(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer srv.Close()
	if _, err := New(srv.URL, "tok", "0.7.0").PostHeartbeat(vitals.Vitals{}, nil); err != nil {
		t.Fatal(err)
	}
	if _, ok := got["tasks"]; ok {
		t.Fatalf("tasks key must be omitted when empty: %+v", got)
	}
}

func TestClaimLifecycleOp(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/lifecycle_ops/abc/claim" {
			t.Fatalf("path %s", r.URL.Path)
		}
		w.Write([]byte(`{"id":"abc","kind":"stack.converge","app_name":"blog","params":{"image_ref":"img:1"},"timeout_seconds":600}`))
	}))
	defer srv.Close()
	op, err := New(srv.URL, "tok", "0.7.0").ClaimLifecycleOp("abc")
	if err != nil || op == nil {
		t.Fatalf("op=%v err=%v", op, err)
	}
	if op.ID != "abc" || op.Kind != "stack.converge" || op.AppName != "blog" || op.TimeoutSeconds != 600 {
		t.Fatalf("got %+v", op)
	}
}

func TestClaimLifecycleOpRefusals(t *testing.T) {
	for _, code := range []int{404, 409, 410} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(code)
		}))
		op, err := New(srv.URL, "tok", "0.7.0").ClaimLifecycleOp("abc")
		if op != nil || err != nil {
			t.Fatalf("code %d: want nil,nil got %v,%v", code, op, err)
		}
		srv.Close()
	}
}

func TestReportLifecycleOp(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/lifecycle_ops/abc/report" {
			t.Fatalf("path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	err := New(srv.URL, "tok", "0.7.0").ReportLifecycleOp("abc", "failed", nil, "boom", "formation_would_empty")
	if err != nil {
		t.Fatal(err)
	}
	if got["status"] != "failed" || got["error"] != "boom" || got["error_code"] != "formation_would_empty" {
		t.Fatalf("payload %+v", got)
	}
}

func TestReportLifecycleOp410IsTerminalSuccess(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusGone)
	}))
	defer srv.Close()
	c := New(srv.URL, "tok", "0.7.0")
	c.backoffBase = time.Millisecond
	if err := c.ReportLifecycleOp("abc", "succeeded", nil, "", ""); err != nil {
		t.Fatalf("410 should be already-settled success, got %v", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("410 must not be retried, got %d calls", calls.Load())
	}
}

func TestPostLifecycleOpLog(t *testing.T) {
	var got map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/agent/lifecycle_ops/abc/log" {
			t.Fatalf("path %s", r.URL.Path)
		}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	if err := New(srv.URL, "tok", "0.7.0").PostLifecycleOpLog("abc", "chunk"); err != nil {
		t.Fatal(err)
	}
	if got["chunk"] != "chunk" {
		t.Fatalf("payload %+v", got)
	}
}

func TestImageScanClaimRefusedAndReport409IsFinal(t *testing.T) {
	var reports atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/agent/heartbeat":
			w.Write([]byte(`{"pending_image_scan_ids":["s1"]}`))
		case "/api/v1/agent/image_scans/s1/report":
			reports.Add(1)
			w.WriteHeader(http.StatusConflict)
		default:
			w.WriteHeader(http.StatusConflict)
		}
	}))
	defer srv.Close()

	c := New(srv.URL, "tok", "0.1.0")
	c.backoffBase = time.Millisecond
	if resp, err := c.PostHeartbeat(vitals.Vitals{}, nil); err != nil || len(resp.PendingImageScanIDs) != 1 {
		t.Fatalf("heartbeat: %v %+v", err, resp)
	}
	if job, err := c.ClaimImageScan("s1"); job != nil || err != nil {
		t.Fatalf("409 claim: %v %v", job, err)
	}
	if err := c.ReportImageScan("s1", ImageScanReport{Status: "failed"}); err == nil || reports.Load() != 1 {
		t.Fatalf("409 report must fail once without retries: %v, %d calls", err, reports.Load())
	}
	for _, code := range []int{404, 410, 422} {
		var calls atomic.Int32
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			calls.Add(1)
			w.WriteHeader(code)
		}))
		c := New(srv.URL, "tok", "0.1.0")
		c.backoffBase = time.Millisecond
		if err := c.ReportImageScan("s1", ImageScanReport{Status: "failed"}); err == nil || calls.Load() != 1 {
			t.Errorf("%d must be final: %v, %d calls", code, err, calls.Load())
		}
		srv.Close()
	}
}
