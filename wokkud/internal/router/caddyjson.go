// Renders a control.RouterConfig into a full Caddy JSON config.
// Built as map[string]any (json.Marshal sorts map keys → deterministic
// output; the manager compares rendered bytes to decide whether to apply).
package router

import (
	"encoding/json"
	"fmt"
	"sort"

	"wokku.cloud/wokkud/internal/control"
)

// maintenanceBody is the static page served for apps in maintenance mode.
const maintenanceBody = `<!doctype html><html><head><meta charset="utf-8"><title>Down for maintenance</title><style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#fafafa;color:#111}main{text-align:center;padding:2rem}h1{font-size:1.5rem}p{color:#555}</style></head><body><main><h1>Down for maintenance</h1><p>This app is temporarily offline. Please check back soon.</p></main></body></html>`

// Render builds the complete Caddy config. upstreams maps app name → dial
// addrs; remote (mesh) upstreams from the config are appended verbatim.
// An app renders if anything can back it — locally resolved or mesh; only
// a fully backless app is skipped, avoiding advertising a route nothing serves.
func Render(cfg *control.RouterConfig, upstreams map[string][]string, askURL, certDir string) ([]byte, error) {
	httpsPort, httpPort := 8443, 8080
	if cfg.ListenMode == "live" {
		httpsPort, httpPort = 443, 80
	}

	routes := []any{}
	for _, app := range cfg.Apps {
		hosts := make([]string, len(app.Domains))
		for i, d := range app.Domains {
			hosts[i] = d.Hostname
		}
		// Maintenance (W7): the app's vhosts answer a static 503 page instead
		// of reverse_proxy. Checked before upstream resolution — a down-for-
		// maintenance app must render even when nothing backs it.
		if app.Maintenance {
			routes = append(routes, map[string]any{
				"match": []any{map[string]any{"host": hosts}},
				"handle": []any{map[string]any{
					"handler":     "static_response",
					"status_code": 503,
					"headers":     map[string]any{"Content-Type": []any{"text/html; charset=utf-8"}},
					"body":        maintenanceBody,
				}},
			})
			continue
		}
		// Wake (2026-10-19): a sleeping app's vhosts proxy to the control
		// plane's wake endpoint (URI rewritten to the signed path), which
		// starts the app and answers a self-refreshing 503. Checked before
		// upstream resolution — the app's own upstream is stopped.
		if app.Wake != nil && app.Wake.Upstream != "" && app.Wake.Path != "" {
			routes = append(routes, map[string]any{
				"match": []any{map[string]any{"host": hosts}},
				"handle": []any{
					map[string]any{"handler": "rewrite", "uri": app.Wake.Path},
					map[string]any{
						"handler":   "reverse_proxy",
						"upstreams": []any{map[string]any{"dial": app.Wake.Upstream + ":443"}},
						"transport": map[string]any{
							"protocol": "http",
							"tls":      map[string]any{"server_name": app.Wake.Upstream},
						},
						// Host + X-Forwarded-Host name the control plane so its
						// HostAuthorization accepts the request. Its HSTS
						// (includeSubDomains) and cookies must never be served
						// under the customer's domain — strip them.
						"headers": map[string]any{
							"request": map[string]any{
								"set": map[string]any{
									"Host":             []any{app.Wake.Upstream},
									"X-Forwarded-Host": []any{app.Wake.Upstream},
								},
							},
							"response": map[string]any{
								"delete": []any{"Strict-Transport-Security", "Set-Cookie"},
							},
						},
					},
				},
			})
			continue
		}
		var dials []string
		hasLocal := false
		for _, u := range app.Upstreams {
			switch {
			case u.Dial != "":
				// Dial upstreams (B5a swarm port) pass through verbatim —
				// no docker resolution involved for these apps at all.
				dials = append(dials, u.Dial)
			case u.Local:
				hasLocal = true
			case u.MeshIP != "":
				dials = append(dials, fmt.Sprintf("%s:%d", u.MeshIP, u.Port))
			}
		}
		// Only apps carrying a `local` upstream entry pick up docker-resolved
		// dials — a stray/leftover resolver entry for a dial-only app (e.g.
		// mid-cutover) must never leak into its route.
		if hasLocal {
			dials = append(dials, upstreams[app.Name]...)
		}
		if len(dials) == 0 {
			continue
		}
		// Deterministic dial order — the manager compares rendered bytes to
		// decide whether to apply, so upstream ordering (docker resolution
		// order isn't guaranteed) must not cause spurious re-applies.
		sort.Strings(dials)
		ups := make([]any, len(dials))
		for i, d := range dials {
			ups[i] = map[string]any{"dial": d}
		}
		routes = append(routes, map[string]any{
			"match":  []any{map[string]any{"host": hosts}},
			"handle": []any{map[string]any{"handler": "reverse_proxy", "upstreams": ups}},
		})
	}

	onDemandPolicy := map[string]any{"on_demand": true}
	if cfg.ListenMode == "shadow" {
		// Shadow never owns :80/:443 (nginx does) so HTTP-01 can never
		// complete — point at LE's staging CA to avoid burning the
		// production rate limit on certs that can never issue anyway.
		onDemandPolicy["issuers"] = []any{map[string]any{
			"module": "acme",
			"ca":     "https://acme-staging-v02.api.letsencrypt.org/directory",
		}}
	}
	tlsApp := map[string]any{
		"automation": map[string]any{
			// A single on-demand policy: names covered by the loaded
			// wildcard cert never reach automation; unverified customs
			// fail the ask (403) and get no cert — correct by design.
			"policies": []any{onDemandPolicy},
			"on_demand": map[string]any{
				"permission": map[string]any{"module": "http", "endpoint": askURL},
			},
		},
	}
	if cfg.WildcardCert != nil {
		tlsApp["certificates"] = map[string]any{
			"load_pem": []any{map[string]any{
				"certificate": cfg.WildcardCert.FullchainPEM,
				"key":         cfg.WildcardCert.KeyPEM,
				"tags":        []any{"wildcard"},
			}},
		}
	}

	full := map[string]any{
		"admin": map[string]any{"listen": "127.0.0.1:2019"},
		"apps": map[string]any{
			"http": map[string]any{
				// Per-host request counters (wake-on-request idle detection).
				// Unconfigured Host headers aggregate under "_other", so a
				// junk Host can't grow cardinality.
				"metrics":    map[string]any{"per_host": true},
				"https_port": httpsPort,
				"http_port":  httpPort,
				"servers": map[string]any{
					"wokku": map[string]any{
						"listen": []any{fmt.Sprintf(":%d", httpsPort)},
						// No h3: QUIC over UDP 443 stalls mid-flow on some
						// client ISPs/middleboxes (2026-07-17 tenant outage);
						// h1+h2 over TCP matches the pre-B1 nginx transport.
						"protocols": []any{"h1", "h2"},
						"routes":    routes,
					},
				},
			},
			"tls": tlsApp,
		},
	}
	_ = certDir // reserved: file-based certs if PEM-in-config ever bloats
	return json.MarshalIndent(full, "", "  ")
}
