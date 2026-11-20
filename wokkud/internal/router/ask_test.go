package router

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Security assessment 2026-11-19, F-10: Caddy's on-demand TLS "ask" can't
// send headers, so the token used to ride in its URL (and so in proxy and
// Rails access logs). Caddy now asks wokkud on loopback; wokkud forwards with
// the token in the Authorization header.
func TestAskHandlerForwardsWithHeaderAndMirrorsStatus(t *testing.T) {
	var gotAuth, gotQuery string
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotQuery = r.URL.RawQuery
		if r.URL.Path != "/api/v1/agent/router/tls_allowed" {
			t.Errorf("path = %s", r.URL.Path)
		}
		switch r.URL.Query().Get("domain") {
		case "ok.example.com":
			w.WriteHeader(http.StatusOK)
		case "busy.example.com":
			w.WriteHeader(http.StatusTooManyRequests)
		default:
			w.WriteHeader(http.StatusForbidden)
		}
	}))
	defer control.Close()

	h := askHandler(control.URL, "s3cret", control.Client())
	for domain, want := range map[string]int{"ok.example.com": 200, "busy.example.com": 429, "no.example.com": 403} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("GET", "/tls-ask?domain="+domain, nil))
		if rec.Code != want {
			t.Errorf("%s: status %d, want %d", domain, rec.Code, want)
		}
		if gotAuth != "Bearer s3cret" {
			t.Errorf("%s: Authorization = %q", domain, gotAuth)
		}
		if strings.Contains(gotQuery, "s3cret") || strings.Contains(gotQuery, "token") {
			t.Errorf("%s: token leaked into query %q", domain, gotQuery)
		}
	}
}

func TestAskHandlerRejectsMissingDomainAndUnreachableControl(t *testing.T) {
	rec := httptest.NewRecorder()
	askHandler("http://127.0.0.1:1", "t", http.DefaultClient).ServeHTTP(rec, httptest.NewRequest("GET", "/tls-ask", nil))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("no domain: status %d, want 400", rec.Code)
	}

	rec = httptest.NewRecorder()
	askHandler("http://127.0.0.1:1", "t", http.DefaultClient).ServeHTTP(rec, httptest.NewRequest("GET", "/tls-ask?domain=a.example.com", nil))
	if rec.Code != http.StatusBadGateway {
		t.Errorf("control down: status %d, want 502 (Caddy then refuses the cert)", rec.Code)
	}
}

func TestStartAskServerServesOnLoopbackAndFallsBackWhenBusy(t *testing.T) {
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }))
	defer control.Close()

	url := startAskServer("127.0.0.1:0", control.URL, "t")
	if !strings.HasPrefix(url, "http://127.0.0.1:") || !strings.HasSuffix(url, "/tls-ask") {
		t.Fatalf("ask URL = %q, want the loopback endpoint", url)
	}
	resp, err := http.Get(url + "?domain=a.example.com")
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("loopback ask: %v %v", resp, err)
	}

	busy := strings.TrimSuffix(strings.TrimPrefix(url, "http://"), "/tls-ask")
	if fb := startAskServer(busy, control.URL, "t"); !strings.Contains(fb, "/api/v1/agent/router/tls_allowed?token=t") {
		t.Errorf("port taken: got %q, want the legacy direct URL so certs keep working", fb)
	}
}
