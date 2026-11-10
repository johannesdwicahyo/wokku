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

// shellSyntax marks a command that needs a shell: env expansion ($PORT),
// chaining (&&, ;), pipes, redirects, subshells.
const shellSyntax = "$&|;<>`\n"

// processCommand turns a Procfile command into the service's
// (Command, Args) — Swarm's ENTRYPOINT and CMD overrides. Procfile lines
// are shell lines (Heroku runs them via bash -c), so exec-splitting alone
// left $PORT literal and && as an argument.
//   - Image ENTRYPOINT is a shell's "-c" (nixpacks: bash -l -c): keep it
//     and pass the whole line as CMD. The login shell also loads the PATH
//     nixpacks writes to ~/.profile (Python's venv lives only there).
//   - Shell syntax otherwise: /bin/sh -c.
//   - Plain command: exec form, as before (no shell needed in the image).
func processCommand(entrypoint []string, cmd string) (command, args []string) {
	if strings.TrimSpace(cmd) == "" {
		return nil, nil
	}
	if n := len(entrypoint); n >= 2 && entrypoint[n-1] == "-c" && isShell(entrypoint[0]) {
		return nil, []string{cmd}
	}
	if strings.ContainsAny(cmd, shellSyntax) {
		return []string{"/bin/sh", "-c", cmd}, nil
	}
	return splitCommand(cmd), nil
}

func isShell(path string) bool {
	switch path[strings.LastIndex(path, "/")+1:] {
	case "sh", "bash", "ash", "dash":
		return true
	}
	return false
}
