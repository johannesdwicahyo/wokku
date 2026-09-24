package vitals

import (
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// waitFor polls cond until it's true or the deadline passes, failing the
// test on timeout. Portable, no fixed sleeps beyond a short poll interval.
func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for condition")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestDirUsageSumsFiles(t *testing.T) {
	root := t.TempDir()
	a := filepath.Join(root, "wokku-app-data", "_data")
	os.MkdirAll(filepath.Join(a, "sub"), 0o755)
	os.WriteFile(filepath.Join(a, "f1"), make([]byte, 1000), 0o644)
	os.WriteFile(filepath.Join(a, "sub", "f2"), make([]byte, 500), 0o644)

	got := DirUsage([]string{filepath.Join(root, "wokku-*", "_data")})
	if got[a] != 1500 {
		t.Fatalf("want 1500 bytes for %s, got %v", a, got)
	}
}

// (a) Get never blocks: it returns nil while the first collect is still
// running, and calling Get again while that collect is in flight doesn't
// start a second one (single-flight).
func TestUsageCacheGetDoesNotBlockAndSingleFlights(t *testing.T) {
	var calls int32
	block := make(chan struct{})
	c := &UsageCache{TTL: time.Hour, collect: func() map[string]int64 {
		atomic.AddInt32(&calls, 1)
		<-block
		return map[string]int64{"x": 1}
	}}
	now := time.Now()

	if got := c.Get(now); got != nil {
		t.Fatalf("want nil before first collect completes, got %v", got)
	}
	waitFor(t, func() bool { return atomic.LoadInt32(&calls) == 1 }) // let the goroutine actually start
	if got := c.Get(now); got != nil {
		t.Fatalf("want nil on second call while collect still in flight, got %v", got)
	}
	if n := atomic.LoadInt32(&calls); n != 1 {
		t.Fatalf("want exactly 1 collect started, got %d", n)
	}
	close(block)
	waitFor(t, func() bool { return c.Get(now) != nil })
	if n := atomic.LoadInt32(&calls); n != 1 {
		t.Fatalf("want still exactly 1 collect after it finished, got %d", n)
	}
}

// (b) once the background collect finishes, Get returns the collected map.
func TestUsageCacheGetReturnsCollectedMapOnceReady(t *testing.T) {
	c := &UsageCache{TTL: time.Hour, collect: func() map[string]int64 { return map[string]int64{"x": 42} }}
	now := time.Now()
	c.Get(now)
	waitFor(t, func() bool { return c.Get(now) != nil })
	if got := c.Get(now)["x"]; got != 42 {
		t.Fatalf("want 42, got %v", got)
	}
}

// (c) inside TTL, Get triggers no new collect; past TTL it starts exactly
// one background refresh and keeps returning the OLD map until it finishes.
func TestUsageCacheBackgroundRefreshAfterTTL(t *testing.T) {
	var calls int32
	block := make(chan struct{})
	c := &UsageCache{TTL: time.Hour, collect: func() map[string]int64 {
		n := atomic.AddInt32(&calls, 1)
		if n == 1 {
			return map[string]int64{"x": 1}
		}
		<-block
		return map[string]int64{"x": 2}
	}}
	now := time.Now()

	c.Get(now)
	waitFor(t, func() bool { return c.Get(now) != nil })
	if n := atomic.LoadInt32(&calls); n != 1 {
		t.Fatalf("want 1 collect after first refresh, got %d", n)
	}

	if got := c.Get(now.Add(30 * time.Minute)); got["x"] != 1 {
		t.Fatalf("want cached value inside TTL, got %v", got)
	}
	if n := atomic.LoadInt32(&calls); n != 1 {
		t.Fatalf("want no new collect inside TTL, got %d", n)
	}

	// Past TTL: triggers a second (blocked) collect but keeps serving the
	// old map until that one finishes.
	if got := c.Get(now.Add(61 * time.Minute)); got["x"] != 1 {
		t.Fatalf("want OLD map while second collect still running, got %v", got)
	}
	close(block)
	waitFor(t, func() bool { return c.Get(now.Add(61 * time.Minute))["x"] == 2 })
	if n := atomic.LoadInt32(&calls); n != 2 {
		t.Fatalf("want exactly 2 collects total, got %d", n)
	}
}
