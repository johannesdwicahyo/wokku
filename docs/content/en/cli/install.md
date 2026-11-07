---
title: Install the CLI
summary: Install the wokku command-line tool, sign in, and check it works.
eyebrow: cli
last_updated: 2026-11-07
---

Install the CLI with RubyGems, sign in through your browser, and run your first command.

## Install

The CLI is a Ruby gem. You need Ruby 3.2 or newer.

```bash
gem install wokku-cli
```

## Sign in

```bash
wokku auth:login
```

This opens your browser. Approve the code shown in your terminal and the CLI saves your session locally.

## Check it works

```bash
wokku version      # prints the CLI version
wokku auth:whoami  # shows who you are signed in as
wokku doctor       # checks your sign-in, CLI version and your apps
```

## Use it in CI

In CI there is no browser, so use an API token instead. Create one under **Profile → API Tokens** in the dashboard (or with `wokku tokens:create ci`) and set it as an environment variable:

```bash
export WOKKU_API_TOKEN=your-token
wokku apps
```

## Update and uninstall

```bash
gem update wokku-cli
gem uninstall wokku-cli
```

## Next

- [All commands](/docs/cli/commands) — or run `wokku help`
- [Claude Code setup](/docs/mcp/setup)
- Add `--json` to read commands for machine-readable output, or `--quiet` to hide status messages.
