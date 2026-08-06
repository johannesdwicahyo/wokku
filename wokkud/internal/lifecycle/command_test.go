package lifecycle

import (
	"reflect"
	"testing"
)

func TestSplitCommand(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"node bin/www", []string{"node", "bin/www"}},
		{`bash -c "echo hi"`, []string{"bash", "-c", "echo hi"}},
		{`sh -c 'echo hi'`, []string{"sh", "-c", "echo hi"}},
		{"  spaced   out  ", []string{"spaced", "out"}},
		{"", nil},
		{"   ", nil},
		{`ruby -e "puts 'nested'"`, []string{"ruby", "-e", "puts 'nested'"}},
	}
	for _, c := range cases {
		got := splitCommand(c.in)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("splitCommand(%q) = %#v, want %#v", c.in, got, c.want)
		}
	}
}
