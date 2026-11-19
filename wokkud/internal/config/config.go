package config

import (
	"fmt"
	"log"
	"net"
	"net/url"
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
	if err := checkURL(cfg.URL); err != nil {
		if os.Getenv("WOKKUD_ALLOW_INSECURE_URL") != "1" {
			return cfg, err
		}
		log.Printf("wokkud: WARNING %v — continuing because WOKKUD_ALLOW_INSECURE_URL=1; the ingest token is sent in cleartext", err)
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

// checkURL: the ingest token and every op spec (which wokkud executes)
// travel over this channel, so it must be https unless it is plain http to
// this same box (self-host default http://127.0.0.1:3000). Security F-03.
func checkURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return fmt.Errorf("WOKKUD_URL %q is not an absolute URL", raw)
	}
	if u.Scheme == "https" {
		return nil
	}
	host := u.Hostname()
	if ip := net.ParseIP(host); u.Scheme == "http" && (host == "localhost" || (ip != nil && ip.IsLoopback())) {
		return nil
	}
	return fmt.Errorf("WOKKUD_URL %q must use https (plain http is only allowed to localhost)", raw)
}
