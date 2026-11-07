---
title: One-Click Apps
summary: Find a ready-made app, such as a CMS, an automation tool, an AI agent, or a framework starter, and deploy it in one click.
last_updated: 2026-11-07
---

You'll find a template, deploy it under your own app name, and open it at `https://my-app.wokku.app`.

## Find a template

:::tabs
::web-ui
Go to **Templates** in the sidebar. The page shows featured apps, then a row for each category. Type in the search box to filter by name, description, or tag.

::cli
```bash
wokku templates                 # every template: slug and description
wokku templates:info ghost      # details for one template
```

::api
```bash
curl "https://wokku.cloud/api/v1/templates?q=analytics" \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Use `?q=` to search or `?category=<slug>` to filter, for example `?category=cms`. Leave both off to list everything. The response also includes the category list.

::mcp
Ask Claude: *"Which Wokku templates are there for analytics?"*
:::

### Featured

| Template | What it is |
|---|---|
| Hermes Agent | Self-hosted AI agent with persistent memory: a Telegram bot plus a web dashboard |
| n8n | Workflow automation, like Zapier |
| Ghost | Publishing and blogging platform |
| Dify | Platform for building AI workflows and LLM apps |
| Directus | Instant REST and GraphQL API for a SQL database |
| Listmonk | Newsletter and mailing-list manager |
| Nextcloud | File sync, calendar, and collaboration |
| Umami | Simple, fast website analytics |

### Categories

Frameworks · Automation · Communication · Analytics · CMS & Content · Productivity · E-Commerce · Developer Tools · AI · Databases & Admin · Media · Monitoring · Security · File Storage · Links & URL · Email · RSS & Reading · Platform

The **Frameworks** category holds starter apps, for example Astro, Next.js, Rails, Django, and Laravel. Deploy one to get a working project you can clone and change. For the full, current list, use **Templates** or `wokku templates`.

## Deploy a template

:::tabs
::web-ui
1. Open a template from **Templates**.
2. Keep the suggested app name or type your own, for example `my-app`.
3. Check **what this uses**, which shows the size and any add-ons the template needs.
4. Click **Deploy &lt;template name&gt;**.

::cli
```bash
wokku deploy ghost --name my-app
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/templates/deploy \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "name": "my-app", "server_id": "<server-id>"}'
```

::mcp
Ask Claude: *"Deploy the Ghost template as my-app."*
:::

Wokku creates the app, sets the template's default environment variables, and creates and connects any database the template needs. Most templates are live in 30–90 seconds.

## After it's deployed

- Open `https://my-app.wokku.app`. Many apps ask you to create an admin account on first visit.
- [Change environment variables](/docs/apps/config) to configure the app.
- [Add a custom domain](/docs/domains-ssl/custom-domains). HTTPS is set up automatically.
- [Check the logs](/docs/monitoring/logs) if it doesn't come up.
