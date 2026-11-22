package builder

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, body := range files {
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func TestRelayScanFlagsRelayTools(t *testing.T) {
	cases := map[string]map[string]string{
		"xray binary":       {"bin/xray": "\x7fELF"},
		"sing-box binary":   {"sing-box": "\x7fELF"},
		"download script":   {"start.sh": "curl -L https://github.com/XTLS/Xray-core/releases/download/v1/Xray-linux-64.zip"},
		"vless config":      {"config.json": `{"inbounds":[{"port":8080,"protocol": "vless"}]}`},
		"vmess share link":  {"index.js": "const link = 'vmess://' + btoa(cfg)"},
		"nezha agent":       {"run.sh": "wget https://github.com/nezhahq/agent/releases/latest"},
		"hysteria download": {"Dockerfile": "RUN wget github.com/apernet/hysteria/releases/x"},
	}
	for name, files := range cases {
		t.Run(name, func(t *testing.T) {
			if got := relayScan(writeFiles(t, files)); got == "" {
				t.Fatalf("expected a relay hit for %v", files)
			}
		})
	}
}

func TestRelayScanIgnoresNormalApps(t *testing.T) {
	dir := writeFiles(t, map[string]string{
		"app.rb":            "get('/') { 'hello' }",
		"package.json":      `{"name":"blog","dependencies":{"express":"4"}}`,
		"README.md":         "We compared xray, v2ray and vless:// links in this blog post.",
		"docs/notes.txt":    "XTLS/Xray-core is mentioned in prose only",
		"node_modules/x.js": "vmess://",
	})
	if got := relayScan(dir); got != "" {
		t.Fatalf("normal app flagged: %q", got)
	}
}

func TestRelayScanSkipsGitDirAndBigFiles(t *testing.T) {
	dir := writeFiles(t, map[string]string{
		".git/config": `"protocol": "vless"`,
		"big.js":      strings.Repeat("a", relayScanMaxFile) + "vmess://",
	})
	if got := relayScan(dir); got != "" {
		t.Fatalf("expected no hit, got %q", got)
	}
}
