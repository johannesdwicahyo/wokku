package vitals

import (
	"context"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ContainerStat is live usage for one Swarm service (all its replicas).
type ContainerStat struct {
	CPUPct     float64 `json:"cpu_pct"`
	MemMB      int     `json:"mem_mb"`
	MemLimitMB int     `json:"mem_limit_mb"`
}

// ParseDockerStats reads `docker stats --no-stream --format
// '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'` and keys app tasks by Swarm
// service name ("wokku-<app>-<process>.<slot>.<id>" → "wokku-<app>-<process>").
// The control plane maps service names to apps; this side stays dumb.
func ParseDockerStats(out string) map[string]ContainerStat {
	stats := map[string]ContainerStat{}
	for _, line := range strings.Split(out, "\n") {
		f := strings.Split(line, "\t")
		if len(f) != 3 || !strings.HasPrefix(f[0], "wokku-") {
			continue
		}
		name := f[0]
		if i := strings.Index(name, "."); i > 0 {
			name = name[:i]
		}
		cpu, _ := strconv.ParseFloat(strings.TrimSuffix(strings.TrimSpace(f[1]), "%"), 64)
		used, limit, ok := strings.Cut(f[2], "/")
		if !ok {
			continue
		}
		s := stats[name]
		s.CPUPct += cpu
		s.MemMB += toMB(used)
		s.MemLimitMB = toMB(limit)
		stats[name] = s
	}
	return stats
}

// toMB parses docker's human sizes ("45.2MiB", "1.5GiB", "800KiB", "12B").
func toMB(s string) int {
	s = strings.TrimSpace(s)
	units := []struct {
		suffix string
		mb     float64
	}{{"GiB", 1024}, {"MiB", 1}, {"KiB", 1.0 / 1024}, {"GB", 1000}, {"MB", 1}, {"kB", 1.0 / 1000}, {"B", 1.0 / (1 << 20)}}
	for _, u := range units {
		if strings.HasSuffix(s, u.suffix) {
			n, err := strconv.ParseFloat(strings.TrimSuffix(s, u.suffix), 64)
			if err != nil {
				return 0
			}
			return int(n * u.mb)
		}
	}
	return 0
}

// AppStatsCache samples `docker stats` at most once per TTL (it blocks ~2s
// while docker samples) and never on the heartbeat's critical path: Get
// returns the last snapshot and refreshes in the background, like UsageCache.
type AppStatsCache struct {
	TTL time.Duration

	mu         sync.Mutex
	at         time.Time
	last       map[string]ContainerStat
	refreshing bool
}

func (c *AppStatsCache) Get(now time.Time) map[string]ContainerStat {
	c.mu.Lock()
	defer c.mu.Unlock()
	if (c.last == nil || now.Sub(c.at) >= c.TTL) && !c.refreshing {
		c.refreshing = true
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			out, err := exec.CommandContext(ctx, "docker", "stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}").Output()
			c.mu.Lock()
			if err == nil {
				c.last = ParseDockerStats(string(out))
			}
			c.at, c.refreshing = now, false
			c.mu.Unlock()
		}()
	}
	return c.last
}
