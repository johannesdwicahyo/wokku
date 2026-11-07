---
title: Metrics
summary: See your app's CPU and memory, HTTP traffic, real-user Web Vitals, and database health.
last_updated: 2026-11-07
---

You'll check how your app and databases are performing. All of it is built in — nothing to install, except one script tag for Web Vitals.

## What you can see

| View | Shows | Dashboard | CLI |
|---|---|---|---|
| **Metrics** | CPU % and memory per app, at 1-minute resolution | App → **Performance** → **Metrics** | `wokku metrics my-app` |
| **Requests** | Requests per minute, p50 / p95 latency, error rate, slowest URLs | App → **Performance** → **Requests** | `wokku monitor my-app` |
| **Vitals** | p75 of LCP, INP, CLS, FCP and TTFB from real visitors | App → **Performance** → **Vitals** | `wokku vitals my-app` |
| **Database monitor** | Connections, size or memory, cache hit ratio, slow queries (Postgres and Redis) | Database → **Monitor** | `wokku db:monitor my-db` |

Requests only count traffic that reaches your app through its Wokku domains (`my-app.wokku.app` or a [custom domain](/docs/domains-ssl/custom-domains)).

## Turn on Web Vitals

1. Open your app → **Performance** → **Vitals**.
2. Copy the **Install snippet** — one `<script defer …>` tag.
3. Paste it into your site's HTML `<head>` and deploy.

Data appears a few minutes after the next visit. If the snippet leaks or you want to revoke it, rotate the token — the old script tag stops working, so update your site with the new one:

:::tabs
::web-ui
**Performance** → **Vitals** → **Rotate token**.

::cli
```bash
wokku vitals:rotate-token my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/vitals/rotate_token \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Rotate the vitals token for my-app."*
:::

## API and Claude

:::tabs
::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/metrics -H "Authorization: Bearer $TOKEN"   # CPU + memory
curl https://wokku.cloud/api/v1/apps/my-app/monitor -H "Authorization: Bearer $TOKEN"   # requests
curl https://wokku.cloud/api/v1/apps/my-app/vitals  -H "Authorization: Bearer $TOKEN"   # Web Vitals
curl https://wokku.cloud/api/v1/databases/my-db/monitor -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"How is my-app doing? Check CPU, memory and p95 latency."*
:::

Metrics are kept for a limited window.

## See also

- [Logs](/docs/monitoring/logs)
- [Uptime & incidents](/docs/monitoring/uptime) — get told when your app goes down
- [Resources](/docs/scaling/resources) — give your app more CPU or memory
