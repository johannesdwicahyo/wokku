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

func TestProcessCommand(t *testing.T) {
	nixpacks := []string{"/bin/bash", "-l", "-c"}
	cases := []struct {
		name       string
		entrypoint []string
		in         string
		cmd, args  []string
	}{
		{"blank keeps the image default", nixpacks, "  ", nil, nil},
		{"nixpacks gets the whole line through its login shell", nixpacks,
			"python manage.py migrate && exec gunicorn app.wsgi --bind 0.0.0.0:$PORT",
			nil, []string{"python manage.py migrate && exec gunicorn app.wsgi --bind 0.0.0.0:$PORT"}},
		{"shell syntax elsewhere runs under sh -c", nil, "rails s -p $PORT",
			[]string{"/bin/sh", "-c", "rails s -p $PORT"}, nil},
		{"&& under sh -c", []string{"docker-entrypoint.sh"}, "a && b",
			[]string{"/bin/sh", "-c", "a && b"}, nil},
		{"plain command is split as before", []string{"docker-entrypoint.sh"}, "bundle exec puma",
			[]string{"bundle", "exec", "puma"}, nil},
	}
	for _, c := range cases {
		cmd, args := processCommand(c.entrypoint, c.in)
		if !reflect.DeepEqual(cmd, c.cmd) || !reflect.DeepEqual(args, c.args) {
			t.Errorf("%s: processCommand = (%#v, %#v), want (%#v, %#v)", c.name, cmd, args, c.cmd, c.args)
		}
	}
}
