package vitals

import (
	"io/fs"
	"path/filepath"
	"sync"
	"time"
)

// DataGlobs are the per-resource data dirs the control plane bills disk for:
// app named volumes (AppRecord#mounts_for_converge → wokku-<app>-<slug>) and
// dedicated datastore bind dirs (DatabaseProvisioner volume_path).
var DataGlobs = []string{
	"/var/lib/docker/volumes/wokku-*/_data",
	"/var/lib/dokku/services/*/*/data",
}

// DirUsage returns apparent size in bytes per matched directory.
// ponytail: a full walk per dir, hourly — fine for GB-scale volumes; switch
// to XFS project quotas if volumes reach TB scale.
func DirUsage(globs []string) map[string]int64 {
	out := map[string]int64{}
	for _, g := range globs {
		dirs, _ := filepath.Glob(g)
		for _, d := range dirs {
			var total int64
			filepath.WalkDir(d, func(_ string, e fs.DirEntry, err error) error {
				if err == nil && e.Type().IsRegular() {
					if info, ierr := e.Info(); ierr == nil {
						total += info.Size()
					}
				}
				return nil
			})
			out[d] = total
		}
	}
	return out
}

// UsageCache keeps the last DirUsage result for TTL so the 15s heartbeat
// never walks disks more than hourly.
type UsageCache struct {
	TTL     time.Duration
	collect func() map[string]int64
	mu      sync.Mutex
	at      time.Time
	last    map[string]int64
}

func NewUsageCache() *UsageCache {
	return &UsageCache{TTL: time.Hour, collect: func() map[string]int64 { return DirUsage(DataGlobs) }}
}

func (c *UsageCache) Get(now time.Time) map[string]int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.last == nil || now.Sub(c.at) >= c.TTL {
		c.last, c.at = c.collect(), now
	}
	return c.last
}
