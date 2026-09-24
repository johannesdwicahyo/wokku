package vitals

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

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

func TestUsageCacheRefreshesHourly(t *testing.T) {
	calls := 0
	c := &UsageCache{TTL: time.Hour, collect: func() map[string]int64 { calls++; return map[string]int64{"x": int64(calls)} }}
	now := time.Now()
	c.Get(now)
	c.Get(now.Add(30 * time.Minute))
	if calls != 1 {
		t.Fatalf("want 1 collection inside TTL, got %d", calls)
	}
	if c.Get(now.Add(61 * time.Minute))["x"] != 2 {
		t.Fatal("want refresh after TTL")
	}
}
