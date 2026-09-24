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
// never walks disks more than hourly — and Get NEVER blocks on the walk
// itself. It returns the last known snapshot immediately (nil until the
// first background collect ever completes); when that snapshot is missing
// or older than TTL, and no refresh is already running, it kicks off
// exactly one background goroutine to collect (single-flight via
// `refreshing`, guarded by mu). The mutex is held only around the map/time
// fields, never while collect() runs.
type UsageCache struct {
	TTL     time.Duration
	collect func() map[string]int64

	mu         sync.Mutex
	at         time.Time
	last       map[string]int64
	refreshing bool
}

func NewUsageCache() *UsageCache {
	return &UsageCache{TTL: time.Hour, collect: func() map[string]int64 { return DirUsage(DataGlobs) }}
}

// Get returns the cached snapshot without ever blocking on a disk walk.
func (c *UsageCache) Get(now time.Time) map[string]int64 {
	c.mu.Lock()
	last := c.last
	stale := c.last == nil || now.Sub(c.at) >= c.TTL
	if stale && !c.refreshing {
		c.refreshing = true
		go c.refresh(now)
	}
	c.mu.Unlock()
	return last
}

// refresh runs collect() with the lock released — a disk walk can take a
// while — then stores the result under the lock.
func (c *UsageCache) refresh(now time.Time) {
	result := c.collect()
	c.mu.Lock()
	c.last, c.at, c.refreshing = result, now, false
	c.mu.Unlock()
}
