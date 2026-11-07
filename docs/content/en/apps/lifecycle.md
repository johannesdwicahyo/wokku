---
title: Restart / Stop / Start
summary: Restart, stop, start, redeploy or delete an app.
last_updated: 2026-11-07
---

You'll control whether your app is running. The dashboard buttons are on the app's **Overview** tab.

## Restart

Restarts every process type. Do this after changing [environment variables](/docs/apps/config).

:::tabs
::web-ui
App → **restart**.

::cli
```bash
wokku ps:restart my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/restart \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Restart my-app."*
:::

## Stop

Stops every process. The app stops serving traffic until you start it.

:::tabs
::web-ui
App → **stop**.

::cli
```bash
wokku ps:stop my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/stop \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Stop my-app."*
:::

## Start

:::tabs
::web-ui
App → **start**.

::cli
```bash
wokku ps:start my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/start \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Start my-app."*
:::

## Redeploy

Rebuilds and deploys the latest source without a new push.

:::tabs
::cli
```bash
wokku redeploy my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/deploy \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Redeploy my-app."*
:::

## Delete

Removes the app and its containers. Databases linked only to this app are deleted too; shared ones are kept. This can't be undone.

:::tabs
::web-ui
App → **Settings** tab → **Danger**.

::cli
```bash
wokku apps:destroy my-app
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app \
  -H "Authorization: Bearer $TOKEN"
```
:::

Free apps also sleep on their own after 30 minutes without traffic and wake on the next request (about 30 seconds). See [Resources](/docs/scaling/resources).
