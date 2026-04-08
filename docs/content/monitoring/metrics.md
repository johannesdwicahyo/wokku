# Metrics

Real-time CPU and memory monitoring for your apps and servers.

## App Metrics

:::tabs
::web-ui
Go to your app → **Metrics** tab. View real-time CPU and memory usage with 24-hour history charts.

::api
Metrics are available through the dashboard. The API provides server-level status.

::mcp
Ask Claude: *"What's the server status?"* for server-level metrics.

::mobile
Tap your app to see live status indicators.
:::

## Server Metrics

:::tabs
::web-ui
Go to **Servers** → click your server to see CPU, memory, and disk usage.

::api
```bash
curl https://wokku.dev/api/v1/servers/1/status \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show server health for server 1"*

::mobile
Tap **Servers** to see health indicators.
:::

## Collected Metrics

| Metric | Frequency | History |
|--------|-----------|---------|
| CPU usage | Every 30s | 24 hours |
| Memory usage | Every 30s | 24 hours |
| Disk usage | Every 5 min | 24 hours |
| Container stats | Every 30s | 24 hours |
