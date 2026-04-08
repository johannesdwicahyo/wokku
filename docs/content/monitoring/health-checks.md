# Health Checks

Configure health checks for zero-downtime deploys.

## How It Works

During a deploy, Dokku starts the new container and runs health checks. If checks pass, traffic switches to the new container. If they fail, the deploy is rolled back.

## Configure

:::tabs
::web-ui
Go to your app → **Health Checks** tab. Set the path, timeout, and attempts.

::cli
```bash
wokku checks:set my-app --path /up --timeout 30 --attempts 5
```

::api
```bash
curl -X PUT https://wokku.dev/api/v1/apps/my-app/checks \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"path": "/up", "timeout": 30, "attempts": 5}'
```

::mcp
Ask Claude: *"Set health check path to /up with 30s timeout on my-app"*

::mobile
Tap your app → Health Checks → configure settings.
:::

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| **Path** | `/` | HTTP path to check |
| **Timeout** | `30` | Seconds to wait for each check |
| **Attempts** | `5` | Number of retries before failing |

## Disabling Checks

You can disable health checks for apps that take a long time to boot, but this removes zero-downtime deploy protection.
