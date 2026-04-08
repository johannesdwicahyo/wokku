# Restart / Stop / Start

Manage your app's running state.

## Restart

Restarts all processes. Use after config changes or to recover from issues.

:::tabs
::web-ui
Go to your app and click **Restart**.

::cli
```bash
wokku ps:restart my-app
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/restart \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Restart my-app"*

::mobile
Tap your app → **Restart**.
:::

## Stop

Stops all processes. The app becomes inaccessible.

:::tabs
::web-ui
Go to your app → **Stop App**.

::cli
```bash
wokku ps:stop my-app
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/stop \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Stop my-app"*

::mobile
Tap your app → **Stop**.
:::

## Start

Starts a previously stopped app.

:::tabs
::web-ui
Go to your app and click **Start**.

::cli
```bash
wokku ps:start my-app
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/start \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Start my-app"*

::mobile
Tap your app → **Start**.
:::
