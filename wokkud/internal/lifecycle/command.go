package lifecycle

import "strings"

// splitCommand turns a Procfile-style command line into an exec array,
// honouring double AND single quotes so `bash -c "echo hi"` becomes
// ["bash","-c","echo hi"] — strings.Fields is wrong (it would split "echo hi"
// into two args and strip nothing). An empty/blank command returns nil so the
// caller falls back to the image's own CMD.
//
// ponytail: minimal POSIX-ish splitter — no backslash escapes, no $VAR
// expansion, no nested quote types inside one word beyond simple open/close.
// Procfile commands are simple; add escape handling only if a real Procfile
// needs it.
func splitCommand(s string) []string {
	var args []string
	var cur strings.Builder
	inArg := false
	var quote rune // 0 = none, else the open quote char (' or ")

	for _, r := range s {
		switch {
		case quote != 0:
			if r == quote {
				quote = 0
			} else {
				cur.WriteRune(r)
			}
			inArg = true
		case r == '\'' || r == '"':
			quote = r
			inArg = true
		case r == ' ' || r == '\t' || r == '\n' || r == '\r':
			if inArg {
				args = append(args, cur.String())
				cur.Reset()
				inArg = false
			}
		default:
			cur.WriteRune(r)
			inArg = true
		}
	}
	if inArg {
		args = append(args, cur.String())
	}
	return args
}
