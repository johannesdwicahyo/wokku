package config

import (
	"fmt"
	"os"
	"time"
)

type Config struct {
	URL      string        // control-plane base URL, e.g. https://wokku.cloud
	Token    string        // Server#ingest_token — same token Vector uses
	Interval time.Duration // heartbeat cadence
}

func Load() (Config, error) {
	cfg := Config{
		URL:      os.Getenv("WOKKUD_URL"),
		Token:    os.Getenv("WOKKUD_TOKEN"),
		Interval: 15 * time.Second,
	}
	if cfg.URL == "" {
		return cfg, fmt.Errorf("WOKKUD_URL is required")
	}
	if cfg.Token == "" {
		return cfg, fmt.Errorf("WOKKUD_TOKEN is required")
	}
	if raw := os.Getenv("WOKKUD_INTERVAL"); raw != "" {
		d, err := time.ParseDuration(raw)
		if err != nil {
			return cfg, fmt.Errorf("WOKKUD_INTERVAL: %w", err)
		}
		cfg.Interval = d
	}
	return cfg, nil
}
