package builder

import (
	"bufio"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// maxProcfileSize guards against a runaway/malicious Procfile — a real one
// is a handful of lines.
const maxProcfileSize = 16 * 1024

// parseProcfile reads dir/Procfile and returns process-type -> raw command
// string (e.g. "web" -> "node bin/www"). Comments (#...) and blank lines are
// skipped. The command is stored verbatim — splitting into an exec array
// happens wokkud-side at converge, not here. Returns nil when there's no
// Procfile, it's oversized, or it has no valid entries.
func parseProcfile(dir string) map[string]string {
	path := filepath.Join(dir, "Procfile")
	info, err := os.Stat(path)
	if err != nil {
		return nil
	}
	if info.Size() > maxProcfileSize {
		log.Printf("wokkud: Procfile %s is %d bytes, exceeds %d byte limit — ignoring", path, info.Size(), maxProcfileSize)
		return nil
	}

	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	formation := map[string]string{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, cmd, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		name = strings.TrimSpace(name)
		cmd = strings.TrimSpace(cmd)
		if name == "" || cmd == "" {
			continue
		}
		formation[name] = cmd
	}
	if len(formation) == 0 {
		return nil
	}
	return formation
}
