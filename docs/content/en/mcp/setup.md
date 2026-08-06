---
title: Claude Code Setup
summary: "Wire Claude Code into your Wokku account. Cloud-only — the OSS edition ships the web UI only."
eyebrow: claude code
last_updated: 2026-05-29
---

# Claude Code (Plugin) Setup

Manage your Wokku apps directly from [Claude Code](https://docs.anthropic.com/en/docs/claude-code) using natural language. **57 tools + 4 guided skills** for common workflows.

:::callout warn
The MCP server is a **Wokku Cloud** feature. The open-source edition is web UI only — see [Open Source Edition](/docs/oss/overview).
:::

## Prerequisites

- A Wokku account with an API token
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- Ruby 3.0+ (no gems required)

## Install (Recommended: Plugin)

### 1. Add the marketplace

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
```

### 2. Install the plugin

```bash
claude plugin install wokku@wokku
```

You'll be prompted for two values:

- **Wokku API URL** — press Enter to use `https://wokku.cloud/api/v1` (or enter your self-hosted URL)
- **Wokku API Token** — paste your token (create one at [wokku.cloud/dashboard/profile](https://wokku.cloud/dashboard/profile))

### 3. Restart Claude Code

The plugin loads on next startup. Verify with:

```bash
claude plugin list | grep wokku
```

You should see `wokku@wokku` listed as enabled.

### 4. Start using it

Open Claude Code in any project and try:

```
List my Wokku apps
```

## What's Included

### 57 Tools
Full coverage of the Wokku API — apps, servers, databases, domains, SSL, backups, releases, scaling, teams, notifications, and more. See [Available Tools](/docs/mcp/tools) for the full list.

### 4 Guided Skills
Pre-built workflows that Claude can invoke for common tasks:

| Skill | What it does |
|-------|-------------|
| `/wokku:deploy-new-app` | Complete walkthrough — create app, set config, link database, git push |
| `/wokku:troubleshoot` | Systematic debugging — check status, logs, health, deploys, suggest fixes |
| `/wokku:setup-github-deploy` | Connect a GitHub repo for automatic deploys on push |
| `/wokku:add-database` | Create a database and link it to an app with proper env vars |

## Example Prompts

- *"Deploy this project to Wokku as my-app"*
- *"List my servers and their status"*
- *"Show me the logs for my-app"*
- *"Troubleshoot why my-app is crashing"*
- *"Set DATABASE_URL on my-app to postgres://..."*
- *"Add the domain blog.example.com to my-app and enable SSL"*
- *"Scale my-app to 2 web dynos"*
- *"Rollback my-app to the previous release"*
- *"Create a backup of my production database"*
- *"Invite alice@example.com to the engineering team"*

## Self-Hosted Wokku

When installing, set the API URL to your instance:

```
Wokku API URL: https://paas.mycompany.com/api/v1
```

Everything else works the same.

## Alternative: Manual MCP Setup

If you prefer not to use the plugin system, you can install the MCP server manually:

### 1. Download the server

```bash
curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/mcp/server.rb -o wokku-mcp.rb
```

### 2. Add to Claude Code

```bash
claude mcp add wokku \
  -e WOKKU_API_URL=https://wokku.cloud/api/v1 \
  -e WOKKU_API_TOKEN=your-token-here \
  -- ruby wokku-mcp.rb
```

Note: This method gives you the 57 MCP tools but **not** the guided skills. Use the plugin install for the full experience.

## Troubleshooting

**"Plugin not found"** — Make sure you ran `claude plugin marketplace add johannesdwicahyo/wokku-plugin` first.

**"Cannot connect"** — Check that `WOKKU_API_URL` is correct and reachable. For self-hosted, make sure it includes `/api/v1`.

**"Invalid or expired token"** — Generate a new API token at [wokku.cloud/dashboard/profile](https://wokku.cloud/dashboard/profile).

**Tools not showing up** — Restart Claude Code. Run `claude plugin list` to verify the plugin is enabled.

**Skills not invoked** — Ask Claude directly: *"Use the wokku deploy-new-app skill to deploy this project"*.

See [Available Tools](/docs/mcp/tools) for the full tool reference.
