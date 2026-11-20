package router

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"time"
)

// askAddr is where wokkud answers Caddy's on-demand TLS "ask". Loopback only;
// a var so tests can use a free port.
var askAddr = "127.0.0.1:2020"

// askHandler forwards Caddy's ask to the control plane with the ingest token
// in the Authorization header and mirrors the status (200 = issue the cert).
// Caddy's ask can't set headers, so without this hop the token rode in the
// URL and landed in proxy/Rails access logs (security F-10, 2026-11-19).
func askHandler(controlURL, token string, client *http.Client) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		domain := r.URL.Query().Get("domain")
		if domain == "" {
			http.Error(w, "domain required", http.StatusBadRequest)
			return
		}
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet,
			controlURL+"/api/v1/agent/router/tls_allowed?domain="+url.QueryEscape(domain), nil)
		if err != nil {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("router: tls ask for %s: %v", domain, err)
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		resp.Body.Close()
		w.WriteHeader(resp.StatusCode)
	})
}

// startAskServer serves askHandler on addr and returns the URL Caddy should
// ask. If addr can't be bound it falls back to asking the control plane
// directly (token in the query) so certificates keep issuing.
func startAskServer(addr, controlURL, token string) string {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Printf("router: tls ask listener on %s unavailable (%v), falling back to the direct ask URL", addr, err)
		return fmt.Sprintf("%s/api/v1/agent/router/tls_allowed?token=%s", controlURL, url.QueryEscape(token))
	}
	srv := &http.Server{
		Handler:           askHandler(controlURL, token, &http.Client{Timeout: 10 * time.Second}),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		if err := srv.Serve(ln); err != nil {
			log.Printf("router: tls ask server stopped: %v", err)
		}
	}()
	return fmt.Sprintf("http://%s/tls-ask", ln.Addr())
}
