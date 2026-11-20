---
title: Claude Code Setup
summary: Install the Wokku plugin so Claude Code can deploy and manage your apps.
eyebrow: claude code
last_updated: 2026-11-07
---

Install the Wokku plugin in Claude Code, give it an API token, and ask it to work on your apps in plain language.

## Before you start

- A Wokku account
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Ruby 3.0 or newer (the plugin uses only the standard library, no gems)
- An API token from **Profile → API Tokens** in the dashboard

## Install

In Claude Code, run:

```text
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

Or from your terminal:

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
claude plugin install wokku@wokku
```

When asked for **Wokku API Token**, paste your token. Then restart Claude Code.

:::callout tip
Create the token at **Profile → API tokens**. Choose **Read-only** if Claude should only look (status, logs, config keys) or **Full access** to let it deploy and change things. The plugin only uses this token, never your [CLI](/docs/cli/install) login.
:::

## Try it

Open Claude Code in your project and ask:

- *"List my Wokku apps"*
- *"Deploy this project to Wokku as my-app"*
- *"Add a free Postgres to my-app"*
- *"Show the logs for my-app"*
- *"Why did my last deploy of my-app fail?"*
- *"Add blog.example.com to my-app and enable SSL"*
- *"Scale my-app to 2 web processes"*
- *"Roll back my-app to the previous release"*
- *"Is anything down right now?"*

Claude asks you to confirm before anything destructive, such as deleting an app or restoring a backup.

## What's included

- **109 tools** covering apps, deploys, config, domains, databases, backups, scaling, monitoring, incidents, teams and billing. See [Available tools](/docs/mcp/tools).
- **4 guided skills** for common workflows:

| Skill | What it does |
|---|---|
| `/wokku:deploy-new-app` | Create an app, set config, add a database and walk you through `git push` |
| `/wokku:troubleshoot` | Check status, logs, health and deploys, then suggest fixes |
| `/wokku:setup-github-deploy` | Connect a GitHub repo for deploys on every push |
| `/wokku:add-database` | Add a database to an app and set its URL variable |

## Troubleshooting

| Problem | Fix |
|---|---|
| "Plugin not found" | Run the `marketplace add` command first. |
| "Invalid or expired token" | Create a new token under **Profile → API Tokens** and reinstall the plugin. |
| Tools don't show up | Restart Claude Code, then check `claude plugin list` shows `wokku@wokku` enabled. |
| A skill isn't used | Name it: *"Use the wokku deploy-new-app skill"*. |
| Something else is wrong | Ask *"Run wokku doctor"* — it checks your token, plugin version and app health. |
