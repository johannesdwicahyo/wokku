// Package vitals provides host vitals collection for the wokkud heartbeat.
// Parsers are split from the collectors so tests run with fixtures on any OS;
// Collect itself only works on Linux (the deploy target).
package vitals

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

type Vitals struct {
	DiskUsedPct         float64          `json:"disk_used_pct"`
	DiskFreeGB          float64          `json:"disk_free_gb"`
	MemUsedMB           int              `json:"mem_used_mb"`
	MemTotalMB          int              `json:"mem_total_mb"`
	Load1               float64          `json:"load1"`
	Docker              string           `json:"docker"`                          // "ok" | "down"
	Registry            string           `json:"registry,omitempty"`              // "ok" | "unreachable" — local registry probe (Phase 4c)
	Router              string           `json:"router,omitempty"`                // "ok" | "degraded" — set only when caddy is installed (Phase B1)
	RouterConfigApplied string           `json:"router_config_applied,omitempty"` // sha of the last successfully applied router config
	Swarm               string           `json:"swarm,omitempty"`                 // raw Docker Swarm.LocalNodeState, e.g. "active" — B5a adopt guard
	VolumeUsage         map[string]int64 `json:"volume_usage,omitempty"`          // per-resource data dir → bytes, hourly (Task 9)
}

// Collect gathers live vitals. dockerStatus is injected by the caller
// (main pings the Docker daemon) so this package needs no docker dep.
func Collect(dockerStatus string) (Vitals, error) {
	v := Vitals{Docker: dockerStatus}

	var st unix.Statfs_t
	if err := unix.Statfs("/", &st); err != nil {
		return v, fmt.Errorf("statfs /: %w", err)
	}
	total := float64(st.Blocks) * float64(st.Bsize)
	free := float64(st.Bavail) * float64(st.Bsize)
	if total > 0 {
		v.DiskUsedPct = (total - free) / total * 100
	}
	v.DiskFreeGB = free / (1 << 30)

	mem, err := os.Open("/proc/meminfo")
	if err != nil {
		return v, fmt.Errorf("meminfo: %w", err)
	}
	defer mem.Close()
	v.MemTotalMB, v.MemUsedMB, err = parseMeminfo(mem)
	if err != nil {
		return v, err
	}

	loadavg, err := os.Open("/proc/loadavg")
	if err != nil {
		return v, fmt.Errorf("loadavg: %w", err)
	}
	defer loadavg.Close()
	v.Load1, err = parseLoadavg(loadavg)
	return v, err
}

// parseMeminfo returns (totalMB, usedMB). used = MemTotal - MemAvailable,
// the same definition `free` uses for "used minus cache".
func parseMeminfo(r io.Reader) (totalMB, usedMB int, err error) {
	var totalKB, availKB int
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 2 {
			continue
		}
		kb, _ := strconv.Atoi(fields[1])
		switch fields[0] {
		case "MemTotal:":
			totalKB = kb
		case "MemAvailable:":
			availKB = kb
		}
	}
	if totalKB == 0 || availKB == 0 {
		return 0, 0, fmt.Errorf("meminfo: MemTotal/MemAvailable not found")
	}
	return totalKB / 1024, (totalKB - availKB) / 1024, sc.Err()
}

func parseLoadavg(r io.Reader) (float64, error) {
	var buf [64]byte
	n, err := r.Read(buf[:])
	if n == 0 && err != nil {
		return 0, err
	}
	fields := strings.Fields(string(buf[:n]))
	if len(fields) == 0 {
		return 0, fmt.Errorf("loadavg: empty")
	}
	return strconv.ParseFloat(fields[0], 64)
}
