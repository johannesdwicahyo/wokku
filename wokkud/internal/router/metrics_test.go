package router

import (
	"strings"
	"testing"
)

func TestParseHostRequestsSumsPerHost(t *testing.T) {
	in := `# HELP caddy_http_requests_total Counter of HTTP(S) requests made.
# TYPE caddy_http_requests_total counter
caddy_http_requests_total{handler="reverse_proxy",host="a.wokku.app",server="wokku"} 7
caddy_http_requests_total{handler="rewrite",host="a.wokku.app",server="wokku"} 2
caddy_http_requests_total{handler="reverse_proxy",host="b.example.com",server="wokku"} 1.0
caddy_http_requests_total{handler="reverse_proxy",host="_other",server="wokku"} 99
caddy_http_request_duration_seconds_count{host="a.wokku.app"} 5
`
	got := parseHostRequests(strings.NewReader(in))
	if got["a.wokku.app"] != 9 || got["b.example.com"] != 1 {
		t.Fatalf("got %v", got)
	}
	if _, ok := got["_other"]; ok {
		t.Error("_other must be dropped")
	}
	if len(got) != 2 {
		t.Errorf("unexpected hosts: %v", got)
	}
}

func TestParseHostRequestsEmpty(t *testing.T) {
	if got := parseHostRequests(strings.NewReader("garbage\n")); len(got) != 0 {
		t.Errorf("got %v", got)
	}
}

func TestHostRequestsNilManager(t *testing.T) {
	var m *Manager
	if m.HostRequests(nil) != nil {
		t.Error("nil manager must return nil")
	}
}
