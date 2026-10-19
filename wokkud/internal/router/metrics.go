package router

import (
	"bufio"
	"context"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var hostLabel = regexp.MustCompile(`host="([^"]*)"`)

// HostRequests reads Caddy's per-host request counters from the admin API
// (wake-on-request idle detection). nil on any failure — the control plane
// treats a missing field as "no data" and never sleeps on it.
func (m *Manager) HostRequests(ctx context.Context) map[string]int64 {
	if m == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, m.adminURL+"/metrics", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	return parseHostRequests(resp.Body)
}

// parseHostRequests sums caddy_http_requests_total across handlers per host
// label, dropping Caddy's "_other" catch-all bucket.
func parseHostRequests(r io.Reader) map[string]int64 {
	out := map[string]int64{}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "caddy_http_requests_total{") {
			continue
		}
		mm := hostLabel.FindStringSubmatch(line)
		if mm == nil || mm[1] == "" || mm[1] == "_other" {
			continue
		}
		fields := strings.Fields(line)
		v, err := strconv.ParseFloat(fields[len(fields)-1], 64)
		if err != nil {
			continue
		}
		out[mm[1]] += int64(v)
	}
	return out
}
