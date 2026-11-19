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

// Security F-03: the ingest token and op specs travel over this channel,
// so it must be TLS unless it never leaves the box.
func TestLoadURLScheme(t *testing.T) {
	cases := map[string]bool{
		"https://wokku.cloud":       true,
		"http://127.0.0.1:3000":     true,
		"http://localhost:3000":     true,
		"http://[::1]:3000":         true,
		"http://wokku.example.com":  false,
		"http://10.0.0.5:3000":      false,
		"http://127.0.0.1.evil.com": false,
		"ftp://wokku.cloud":         false,
		"wokku.cloud":               false,
	}
	for url, ok := range cases {
		t.Setenv("WOKKUD_URL", url)
		t.Setenv("WOKKUD_TOKEN", "tok")
		t.Setenv("WOKKUD_ALLOW_INSECURE_URL", "")
		if _, err := Load(); (err == nil) != ok {
			t.Errorf("%s: err=%v, want ok=%v", url, err, ok)
		}
	}
}

func TestLoadInsecureOptIn(t *testing.T) {
	t.Setenv("WOKKUD_URL", "http://10.0.0.5:3000")
	t.Setenv("WOKKUD_TOKEN", "tok")
	t.Setenv("WOKKUD_ALLOW_INSECURE_URL", "1")
	if _, err := Load(); err != nil {
		t.Fatalf("explicit opt-in must allow plain http: %v", err)
	}
}
