package builder

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// relayScan looks through a build context for VPN/proxy relay tooling
// (Terms of Service §3) and returns what it found, or "" if nothing.
// Free-tier relay abuse (2026-11) ran xray/sing-box/hysteria/Nezha either as
// vendored binaries or fetched by a start script, so both the file names and
// the download URLs / protocol configs are signals. Prose files are skipped so
// a blog post about these tools still builds.
//
// ponytail: plain-text only — a relay hidden behind base64 or a packed
// payload ("golp", "web-status") gets past this; the host traffic signal
// (roadmap item 5) is what catches those.
const (
	relayScanMaxFile   = 1 << 20 // content checks skip files above 1 MiB
	RelayBlockedPrefix = "blocked by relay scan: "
)

var (
	relayBinaries = map[string]bool{
		"xray": true, "v2ray": true, "sing-box": true, "hysteria": true,
		"hysteria2": true, "nezha-agent": true, "x-ui": true,
	}
	relayContent  = regexp.MustCompile(`(?i)xtls/xray-core|v2fly/v2ray-core|sagernet/sing-box|apernet/hysteria|nezhahq/|\b(?:vless|vmess|trojan)://|"protocol"\s*:\s*"(?:vless|vmess|trojan)"`)
	relaySkipDirs = map[string]bool{".git": true, "node_modules": true, "vendor": true}
	relayProse    = map[string]bool{".md": true, ".markdown": true, ".txt": true, ".rst": true}
)

func relayScan(root string) string {
	var hit string
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || hit != "" {
			return nil
		}
		if d.IsDir() {
			if relaySkipDirs[d.Name()] {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		if relayBinaries[strings.ToLower(d.Name())] {
			hit = rel + " (relay binary)"
			return filepath.SkipAll
		}
		if relayProse[strings.ToLower(filepath.Ext(path))] || !d.Type().IsRegular() {
			return nil
		}
		if info, err := d.Info(); err != nil || info.Size() > relayScanMaxFile {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		if m := relayContent.Find(b); m != nil {
			hit = rel + " (" + string(m) + ")"
			return filepath.SkipAll
		}
		return nil
	})
	return hit
}
