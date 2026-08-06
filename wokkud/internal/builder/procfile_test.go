package builder

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParseProcfile(t *testing.T) {
	cases := []struct {
		name    string
		content string // "" means no Procfile file is written at all
		want    map[string]string
	}{
		{
			name:    "web and worker",
			content: "web: node bin/www\nworker: bundle exec sidekiq\n",
			want:    map[string]string{"web": "node bin/www", "worker": "bundle exec sidekiq"},
		},
		{
			name:    "skips comments and blank lines",
			content: "# a comment\n\nweb: node bin/www\n\n# another\nworker: bundle exec sidekiq\n",
			want:    map[string]string{"web": "node bin/www", "worker": "bundle exec sidekiq"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, "Procfile"), []byte(tc.content), 0o644); err != nil {
				t.Fatal(err)
			}
			got := parseProcfile(dir)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %#v, want %#v", got, tc.want)
			}
		})
	}
}

func TestParseProcfileMissing(t *testing.T) {
	dir := t.TempDir() // no Procfile written
	if got := parseProcfile(dir); got != nil {
		t.Fatalf("got %#v, want nil", got)
	}
}

func TestParseProcfileOversized(t *testing.T) {
	dir := t.TempDir()
	oversized := "web: " + strings.Repeat("x", maxProcfileSize) + "\n" // > 16KB
	if err := os.WriteFile(filepath.Join(dir, "Procfile"), []byte(oversized), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := parseProcfile(dir); got != nil {
		t.Fatalf("got %#v, want nil", got)
	}
}
