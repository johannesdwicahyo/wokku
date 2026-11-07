---
title: Health Checks
summary: How Wokku keeps your app healthy during deploys and restarts, and where configurable checks stand.
last_updated: 2026-11-07
---

You'll learn what Wokku does to keep your app up. There's nothing to set up — health is supervised by the platform.

## What happens on every deploy

- **New before old.** Wokku starts the new container first and only then stops the old one, so a deploy doesn't drop traffic.
- **Automatic restarts.** If a container exits, the platform restarts it.
- **Crash detection.** Crashes show up on the app and can [notify you](/docs/monitoring/notifications) (`app_crashed`).

Make sure your app listens on `$PORT` and answers HTTP quickly once it boots.

## Configurable checks

Custom check paths, timeouts and retry counts are **coming soon**. Until then, the dashboard's **Settings** → **Checks** form and `wokku checks:set` won't save changes — you'll get "configurable healthchecks are coming soon".

To see the current state:

:::tabs
::web-ui
Open your app → **Settings** → **Checks**.

::cli
```bash
wokku checks my-app
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/checks \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"What are the health check settings for my-app?"*
:::

## Know when your app is down

Health checks keep a deploy safe. To be told when a running app stops answering, use [uptime checks](/docs/monitoring/uptime).
