---
title: Deploy with Claude (MCP)
summary: Let Claude create, deploy and run your Wokku apps from plain-language requests.
last_updated: 2026-11-07
---

You'll connect Claude Code to Wokku, then ask it to deploy in plain language.

## 1. Connect Claude Code

Pick one:

**With the Wokku CLI** (uses your logged-in CLI token):

```bash
gem install wokku-cli
wokku auth:login
wokku mcp:install
```

**With the Claude Code plugin marketplace:**

```text
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

You'll be asked for a `WOKKU_API_TOKEN`. Restart Claude Code after either method. Details in [MCP Setup](/docs/mcp/setup).

## 2. Ask Claude to deploy

> *"Create an app called my-app with a shared Postgres, set `RAILS_ENV=production`, and deploy this project."*

Claude calls the Wokku tools one by one and reports each result.

## What you can ask

| Task | Example |
|---|---|
| Create and deploy | *"Deploy the Ghost template as my-blog"* |
| Databases | *"Add a shared Redis to my-app"* |
| Config | *"Set `LOG_LEVEL=debug` on my-app"* |
| Observe | *"Show the last 100 log lines for my-app"* |
| Scale | *"Scale my-app to 2 web and 1 worker"* |
| Operate | *"Roll back my-app to the previous release"* |
| Domains | *"Add api.example.com to my-app"* |

The full list is in [MCP Tools](/docs/mcp/tools).

## Switch or remove

```bash
wokku mcp:switch     # push your current CLI token after a new auth:login
wokku mcp:logout     # remove the Wokku MCP server from Claude Code
```

## Troubleshooting

- **"install Claude Code first"**: the `claude` command must be on your PATH.
- **Auth errors**: run `wokku auth:login`, then `wokku mcp:switch`, then restart Claude Code.
- **Tool not found**: update the plugin (`/plugin` in Claude Code), or re-run `wokku mcp:install`.

## Next steps

- [MCP Setup](/docs/mcp/setup)
- [MCP Tools](/docs/mcp/tools)
- [CLI commands](/docs/cli/commands)
