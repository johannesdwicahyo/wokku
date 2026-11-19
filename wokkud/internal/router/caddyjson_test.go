package router

import (
	"encoding/json"
	"strings"
	"testing"

	"wokku.cloud/wokkud/internal/control"
)

func renderToMap(t *testing.T, cfg *control.RouterConfig, ups map[string][]string) map[string]any {
	t.Helper()
	b, err := Render(cfg, ups, "https://wokku.cloud/api/v1/agent/router/tls_allowed?token=tok", "/etc/wokku/caddy/certs")
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func dig(t *testing.T, m map[string]any, path ...string) any {
	t.Helper()
	var cur any = m
	for _, p := range path {
		mm, ok := cur.(map[string]any)
		if !ok {
			t.Fatalf("dig %v: not a map at %q", path, p)
		}
		cur = mm[p]
	}
	return cur
}

func baseCfg() *control.RouterConfig {
	return &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		WildcardCert: &control.RouterCert{
			FullchainPEM: "CERT", KeyPEM: "KEY", SANs: []string{"*.wokku.app"},
		},
		Apps: []control.RouterApp{
			{
				Name: "alpha", ContainerPort: 5000,
				Domains: []control.RouterDomain{
					{Hostname: "alpha.wokku.app", TLS: "wildcard"},
					{Hostname: "www.example.com", TLS: "on_demand"},
				},
				Upstreams: []control.RouterUpstream{{Local: true}},
			},
			{
				Name: "bravo", ContainerPort: 3000,
				Domains:   []control.RouterDomain{{Hostname: "bravo.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Local: true}, {MeshIP: "10.77.0.9", Port: 3000}},
			},
		},
	}
}

func TestRenderShadowPortsAndRoutes(t *testing.T) {
	m := renderToMap(t, baseCfg(), map[string][]string{
		"alpha": {"172.17.0.3:5000"},
		"bravo": {"172.17.0.4:3000"},
	})
	if got := dig(t, m, "apps", "http", "https_port"); got != float64(8443) {
		t.Errorf("https_port = %v", got)
	}
	if got := dig(t, m, "apps", "http", "http_port"); got != float64(8080) {
		t.Errorf("http_port = %v", got)
	}
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 2 {
		t.Fatalf("routes = %d, want 2", len(routes))
	}
	blob, _ := json.Marshal(routes)
	for _, want := range []string{
		`"alpha.wokku.app"`, `"www.example.com"`, `"172.17.0.3:5000"`,
		`"bravo.wokku.app"`, `"172.17.0.4:3000"`, `"10.77.0.9:3000"`,
	} {
		if !strings.Contains(string(blob), want) {
			t.Errorf("routes missing %s", want)
		}
	}
}

func TestRenderLiveMode(t *testing.T) {
	cfg := baseCfg()
	cfg.ListenMode = "live"
	m := renderToMap(t, cfg, map[string][]string{"alpha": {"a:1"}, "bravo": {"b:2"}})
	if got := dig(t, m, "apps", "http", "https_port"); got != float64(443) {
		t.Errorf("https_port = %v", got)
	}
}

func TestRenderTLSBlocks(t *testing.T) {
	m := renderToMap(t, baseCfg(), map[string][]string{"alpha": {"a:1"}, "bravo": {"b:2"}})
	pems := dig(t, m, "apps", "tls", "certificates", "load_pem").([]any)
	first := pems[0].(map[string]any)
	if first["certificate"] != "CERT" || first["key"] != "KEY" {
		t.Errorf("load_pem = %v", first)
	}
	ask := dig(t, m, "apps", "tls", "automation", "on_demand", "permission").(map[string]any)
	if ask["module"] != "http" || !strings.Contains(ask["endpoint"].(string), "tls_allowed") {
		t.Errorf("ask = %v", ask)
	}
}

func TestRenderSkipsAppsWithoutUpstreamsAndNilCert(t *testing.T) {
	cfg := baseCfg()
	cfg.WildcardCert = nil
	m := renderToMap(t, cfg, map[string][]string{"alpha": {"a:1"}}) // bravo unresolved locally, has mesh
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 2 {
		t.Errorf("routes = %d, want 2 (bravo renders via mesh)", len(routes))
	}
	var bravoRoute map[string]any
	for _, r := range routes {
		route := r.(map[string]any)
		match := dig(t, route, "match").([]any)[0].(map[string]any)
		hosts := match["host"].([]any)
		if len(hosts) == 1 && hosts[0] == "bravo.wokku.app" {
			bravoRoute = route
		}
	}
	if bravoRoute == nil {
		t.Fatalf("no bravo route found: %v", routes)
	}
	handle := dig(t, bravoRoute, "handle").([]any)[0].(map[string]any)
	ups := handle["upstreams"].([]any)
	if len(ups) != 1 || ups[0].(map[string]any)["dial"] != "10.77.0.9:3000" {
		t.Errorf("bravo upstreams = %v, want exactly [{dial: 10.77.0.9:3000}]", ups)
	}
	if tls := dig(t, m, "apps", "tls", "certificates"); tls != nil {
		t.Errorf("certificates should be absent with nil cert, got %v", tls)
	}
}

func TestRenderSkipsAppWithNoDials(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "delta", ContainerPort: 6000,
				Domains:   []control.RouterDomain{{Hostname: "delta.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Local: true}},
			},
		},
	}
	m := renderToMap(t, cfg, map[string][]string{}) // no resolution, no mesh entry
	routes, _ := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 0 {
		t.Errorf("routes = %d, want 0 (delta has no dials)", len(routes))
	}
}

// TestRenderNoneTLSDomain covers the "none" TLS shape: the render function
// doesn't branch on RouterDomain.TLS (automation is a single global on_demand
// policy), so a "none" domain still gets a route — routing and cert
// automation are orthogonal concerns in this design.
// TestRenderDialsSortedForDeterminism guards the bytes.Equal no-op check in
// Manager.Sync: docker resolution order isn't guaranteed, so if dials aren't
// sorted before rendering, the same real-world state can render two
// different byte strings and force a spurious re-apply every beat.
func TestRenderDialsSortedForDeterminism(t *testing.T) {
	cfg := baseCfg()
	b1, err := Render(cfg, map[string][]string{
		"alpha": {"172.17.0.3:5000", "172.17.0.1:5000"},
		"bravo": {"172.17.0.4:3000"},
	}, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	b2, err := Render(cfg, map[string][]string{
		"alpha": {"172.17.0.1:5000", "172.17.0.3:5000"},
		"bravo": {"172.17.0.4:3000"},
	}, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	if string(b1) != string(b2) {
		t.Errorf("render output differs for shuffled upstream order:\n--- b1 ---\n%s\n--- b2 ---\n%s", b1, b2)
	}
}

// TestRenderLEStagingCAInShadow guards the LE rate-limit protection: shadow
// mode can never complete HTTP-01 (nginx owns :80/:443), so on-demand certs
// must issue against staging, never production.
func TestRenderLEStagingCAInShadow(t *testing.T) {
	const stagingCA = "https://acme-staging-v02.api.letsencrypt.org/directory"

	shadowBlob, err := Render(baseCfg(), map[string][]string{"alpha": {"a:1"}, "bravo": {"b:2"}}, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(shadowBlob), stagingCA) {
		t.Errorf("shadow render missing staging CA: %s", shadowBlob)
	}

	liveCfg := baseCfg()
	liveCfg.ListenMode = "live"
	liveBlob, err := Render(liveCfg, map[string][]string{"alpha": {"a:1"}, "bravo": {"b:2"}}, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(liveBlob), stagingCA) {
		t.Errorf("live render must not use staging CA: %s", liveBlob)
	}
}

// TestRenderAllBacklessRoutesEmptyArray guards against `var routes []any`
// marshaling a fully backless config's routes as JSON `null` instead of `[]`
// — a nil slice is valid Go but a surprising wire shape for agents expecting
// an array.
func TestRenderAllBacklessRoutesEmptyArray(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "delta", ContainerPort: 6000,
				Domains:   []control.RouterDomain{{Hostname: "delta.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Local: true}},
			},
		},
	}
	blob, err := Render(cfg, map[string][]string{}, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(blob), `"routes": null`) {
		t.Errorf("routes rendered as null, want []: %s", blob)
	}
	if !strings.Contains(string(blob), `"routes": []`) {
		t.Errorf("routes not rendered as empty array: %s", blob)
	}
}

// TestRenderDialUpstreamPassesThroughVerbatim guards the B5a swarm-port
// path: a wokkud-lifecycle app's dial upstream must land in the rendered
// Caddy JSON exactly as given, ignoring any stray docker-resolved entry
// for the same app name (there shouldn't be one — the app has no `local`
// upstream — but a leftover/misrouted resolver entry must never leak in).
func TestRenderDialUpstreamPassesThroughVerbatim(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "gamma", ContainerPort: 9000,
				Domains:   []control.RouterDomain{{Hostname: "gamma.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Dial: "127.0.0.1:31005"}},
			},
		},
	}
	// Stray docker resolution for "gamma" must be ignored: no `local` entry.
	m := renderToMap(t, cfg, map[string][]string{"gamma": {"172.17.0.9:9999"}})
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 1 {
		t.Fatalf("routes = %d, want 1", len(routes))
	}
	handle := dig(t, routes[0].(map[string]any), "handle").([]any)[0].(map[string]any)
	ups := handle["upstreams"].([]any)
	if len(ups) != 1 || ups[0].(map[string]any)["dial"] != "127.0.0.1:31005" {
		t.Errorf("gamma upstreams = %v, want exactly [{dial: 127.0.0.1:31005}]", ups)
	}
}

// TestRenderMixedLocalAndDialUpstreamsResolveIndependently covers a mixed
// config: one app flagged wokkud_lifecycle (dial upstream) alongside one
// still on docker resolution (local upstream). Each must resolve from its
// own path only — the dial app must never pick up docker-resolved dials.
func TestRenderMixedLocalAndDialUpstreamsResolveIndependently(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "alpha", ContainerPort: 5000,
				Domains:   []control.RouterDomain{{Hostname: "alpha.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Local: true}},
			},
			{
				Name: "beta", ContainerPort: 6000,
				Domains:   []control.RouterDomain{{Hostname: "beta.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Dial: "127.0.0.1:31010"}},
			},
		},
	}
	m := renderToMap(t, cfg, map[string][]string{
		"alpha": {"172.17.0.3:5000"},
		"beta":  {"172.17.0.4:6000"}, // must be ignored: beta has no `local` upstream
	})
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 2 {
		t.Fatalf("routes = %d, want 2", len(routes))
	}
	byHost := map[string][]any{}
	for _, r := range routes {
		route := r.(map[string]any)
		hosts := dig(t, route, "match").([]any)[0].(map[string]any)["host"].([]any)
		handle := dig(t, route, "handle").([]any)[0].(map[string]any)
		byHost[hosts[0].(string)] = handle["upstreams"].([]any)
	}
	if ups := byHost["alpha.wokku.app"]; len(ups) != 1 || ups[0].(map[string]any)["dial"] != "172.17.0.3:5000" {
		t.Errorf("alpha upstreams = %v, want [{dial: 172.17.0.3:5000}]", ups)
	}
	if ups := byHost["beta.wokku.app"]; len(ups) != 1 || ups[0].(map[string]any)["dial"] != "127.0.0.1:31010" {
		t.Errorf("beta upstreams = %v, want [{dial: 127.0.0.1:31010}]", ups)
	}
}

func TestRenderNoneTLSDomain(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "charlie", ContainerPort: 4000,
				Domains:   []control.RouterDomain{{Hostname: "charlie.internal", TLS: "none"}},
				Upstreams: []control.RouterUpstream{{Local: true}},
			},
		},
	}
	m := renderToMap(t, cfg, map[string][]string{"charlie": {"172.17.0.5:4000"}})
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	blob, _ := json.Marshal(routes)
	if !strings.Contains(string(blob), `"charlie.internal"`) {
		t.Errorf("routes missing charlie.internal: %s", blob)
	}
}

// TestRenderMaintenanceServes503 guards the W7 maintenance flag: a flagged
// app's vhosts must answer a static 503 page INSTEAD of reverse_proxy — even
// with zero resolvable upstreams (down-for-maintenance must not depend on a
// live backend) — while sibling apps render exactly as before.
func TestRenderMaintenanceServes503(t *testing.T) {
	cfg := baseCfg()
	cfg.Apps[0].Maintenance = true
	cfg.Apps[0].Upstreams = nil // no backend at all — must still render
	m := renderToMap(t, cfg, map[string][]string{"bravo": {"172.17.0.4:3000"}})
	routes := dig(t, m, "apps", "http", "servers", "wokku", "routes").([]any)
	if len(routes) != 2 {
		t.Fatalf("routes = %d, want 2 (maintenance alpha + live bravo)", len(routes))
	}
	byHost := map[string]map[string]any{}
	for _, r := range routes {
		route := r.(map[string]any)
		hosts := dig(t, route, "match").([]any)[0].(map[string]any)["host"].([]any)
		byHost[hosts[0].(string)] = dig(t, route, "handle").([]any)[0].(map[string]any)
	}
	alpha := byHost["alpha.wokku.app"]
	if alpha == nil {
		t.Fatalf("no alpha route: %v", routes)
	}
	if alpha["handler"] != "static_response" {
		t.Errorf("alpha handler = %v, want static_response", alpha["handler"])
	}
	if alpha["status_code"] != float64(503) {
		t.Errorf("alpha status_code = %v, want 503", alpha["status_code"])
	}
	if body, _ := alpha["body"].(string); !strings.Contains(body, "maintenance") {
		t.Errorf("alpha body missing maintenance page: %q", body)
	}
	if _, has := alpha["upstreams"]; has {
		t.Errorf("alpha must not carry upstreams in maintenance: %v", alpha)
	}
	if bravo := byHost["bravo.wokku.app"]; bravo == nil || bravo["handler"] != "reverse_proxy" {
		t.Errorf("bravo must stay reverse_proxy: %v", bravo)
	}
}

// renderGolden is the byte-for-byte Render output for a minimal
// non-maintenance config, captured BEFORE the maintenance field existed.
// Pins that Maintenance=false (the decoded value for every config an
// unflagged control plane emits) changes nothing — same JSON, so the
// manager's bytes.Equal no-op check and on-disk config stay untouched
// across the agent rollout.
const renderGolden = `{
  "admin": {
    "listen": "127.0.0.1:2019"
  },
  "apps": {
    "http": {
      "http_port": 8080,
      "https_port": 8443,
      "metrics": {
        "per_host": true
      },
      "servers": {
        "wokku": {
          "listen": [
            ":8443"
          ],
          "protocols": [
            "h1",
            "h2"
          ],
          "routes": [
            {
              "handle": [
                {
                  "handler": "reverse_proxy",
                  "headers": {
                    "response": {
                      "delete": [
                        "Via"
                      ]
                    }
                  },
                  "upstreams": [
                    {
                      "dial": "127.0.0.1:20001"
                    }
                  ]
                }
              ],
              "match": [
                {
                  "host": [
                    "golden.wokku.app"
                  ]
                }
              ]
            }
          ]
        }
      }
    },
    "tls": {
      "automation": {
        "on_demand": {
          "permission": {
            "endpoint": "https://wokku.cloud/ask",
            "module": "http"
          }
        },
        "policies": [
          {
            "issuers": [
              {
                "ca": "https://acme-staging-v02.api.letsencrypt.org/directory",
                "module": "acme"
              }
            ],
            "on_demand": true
          }
        ]
      }
    }
  }
}`

func TestRenderNonMaintenanceUnchangedByteForByte(t *testing.T) {
	cfg := &control.RouterConfig{
		Version:    "v1",
		ListenMode: "shadow",
		Apps: []control.RouterApp{
			{
				Name: "golden", ContainerPort: 5000,
				Domains:   []control.RouterDomain{{Hostname: "golden.wokku.app", TLS: "wildcard"}},
				Upstreams: []control.RouterUpstream{{Dial: "127.0.0.1:20001"}},
			},
		},
	}
	b, err := Render(cfg, nil, "https://wokku.cloud/ask", "/certs")
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != renderGolden {
		t.Errorf("non-maintenance render drifted from pre-maintenance golden:\n--- got ---\n%s\n--- want ---\n%s", b, renderGolden)
	}
}

// HTTP/3 is deliberately disabled: QUIC over UDP 443 stalls mid-flow on some
// client ISPs/middleboxes (batumasmekaragung.com outage, 2026-07-17 — Caddy
// "aborting with incomplete response" while dokku-era nginx/h2 was fine).
// h1+h2 over TCP restores the pre-B1 transport for every tenant.
func TestRenderDisablesHTTP3(t *testing.T) {
	m := renderToMap(t, baseCfg(), map[string][]string{"alpha": {"a:1"}})
	protos, ok := dig(t, m, "apps", "http", "servers", "wokku", "protocols").([]any)
	if !ok {
		t.Fatal("servers.wokku.protocols missing")
	}
	if len(protos) != 2 || protos[0] != "h1" || protos[1] != "h2" {
		t.Fatalf("protocols = %v, want [h1 h2]", protos)
	}
}

func TestRenderWakeRouteProxiesToControlPlane(t *testing.T) {
	cfg := &control.RouterConfig{ListenMode: "live", Apps: []control.RouterApp{{
		Name:      "sleepy",
		Domains:   []control.RouterDomain{{Hostname: "sleepy.wokku.app", TLS: "wildcard"}},
		Upstreams: []control.RouterUpstream{{Dial: "127.0.0.1:30001"}},
		Wake:      &control.RouterWake{Upstream: "wokku.cloud", Path: "/__wake/tok"},
	}}}
	out, err := Render(cfg, nil, "https://cp/ask", "")
	if err != nil {
		t.Fatal(err)
	}
	s := string(out)
	for _, want := range []string{
		`"uri": "/__wake/tok"`,
		`"dial": "wokku.cloud:443"`,
		`"server_name": "wokku.cloud"`,
		`"Host": [`,
		`"X-Forwarded-Host": [`,
		`"Strict-Transport-Security"`,
		`"Set-Cookie"`,
	} {
		if !strings.Contains(s, want) {
			t.Errorf("missing %s in:\n%s", want, s)
		}
	}
	if strings.Contains(s, "127.0.0.1:30001") {
		t.Error("sleeping app must not proxy to its (stopped) upstream")
	}
	// The control plane's HSTS (includeSubDomains) and cookies must never
	// be served under a customer's domain.
	var doc any
	if err := json.Unmarshal(out, &doc); err != nil {
		t.Fatal(err)
	}
	h := findWakeProxyHeaders(doc)
	if h == nil {
		t.Fatal("wake reverse_proxy headers not found")
	}
	resp, _ := h["response"].(map[string]any)
	del, _ := resp["delete"].([]any)
	if len(del) != 3 || del[0] != "Strict-Transport-Security" || del[1] != "Set-Cookie" || del[2] != "Via" {
		t.Errorf("wake proxy response.delete = %v", resp["delete"])
	}
	req, _ := h["request"].(map[string]any)
	set, _ := req["set"].(map[string]any)
	if xfh, _ := set["X-Forwarded-Host"].([]any); len(xfh) != 1 || xfh[0] != "wokku.cloud" {
		t.Errorf("wake proxy X-Forwarded-Host = %v", set["X-Forwarded-Host"])
	}
}

// findWakeProxyHeaders returns the headers block of the first reverse_proxy
// handler whose request rewrites Host (only the wake proxy does).
func findWakeProxyHeaders(n any) map[string]any {
	switch v := n.(type) {
	case map[string]any:
		if v["handler"] == "reverse_proxy" {
			if h, ok := v["headers"].(map[string]any); ok {
				return h
			}
		}
		for _, c := range v {
			if h := findWakeProxyHeaders(c); h != nil {
				return h
			}
		}
	case []any:
		for _, c := range v {
			if h := findWakeProxyHeaders(c); h != nil {
				return h
			}
		}
	}
	return nil
}

func TestRenderMaintenanceBeatsWake(t *testing.T) {
	cfg := &control.RouterConfig{Apps: []control.RouterApp{{
		Name: "m", Maintenance: true,
		Domains: []control.RouterDomain{{Hostname: "m.wokku.app"}},
		Wake:    &control.RouterWake{Upstream: "wokku.cloud", Path: "/__wake/t"},
	}}}
	out, _ := Render(cfg, nil, "https://cp/ask", "")
	if strings.Contains(string(out), "/__wake/") {
		t.Error("maintenance must win over wake")
	}
}

func TestRenderEnablesPerHostMetrics(t *testing.T) {
	out, _ := Render(&control.RouterConfig{}, nil, "https://cp/ask", "")
	if !strings.Contains(string(out), `"per_host": true`) {
		t.Errorf("per-host metrics not enabled:\n%s", out)
	}
}
