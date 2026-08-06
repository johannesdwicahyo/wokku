package config

import (
	"testing"
	"time"
)

func TestLoad(t *testing.T) {
	t.Setenv("WOKKUD_URL", "https://wokku.cloud")
	t.Setenv("WOKKUD_TOKEN", "tok123")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.URL != "https://wokku.cloud" || cfg.Token != "tok123" {
		t.Fatalf("bad cfg: %+v", cfg)
	}
	if cfg.Interval != 15*time.Second {
		t.Fatalf("default interval: got %v", cfg.Interval)
	}
}

func TestLoadCustomInterval(t *testing.T) {
	t.Setenv("WOKKUD_URL", "https://wokku.cloud")
	t.Setenv("WOKKUD_TOKEN", "tok123")
	t.Setenv("WOKKUD_INTERVAL", "30s")
	cfg, _ := Load()
	if cfg.Interval != 30*time.Second {
		t.Fatalf("interval: got %v", cfg.Interval)
	}
}

func TestLoadMissingToken(t *testing.T) {
	t.Setenv("WOKKUD_URL", "https://wokku.cloud")
	t.Setenv("WOKKUD_TOKEN", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected error for missing token")
	}
}
