# Logs

View application logs to debug issues and monitor behavior.

## View Logs

:::tabs
::web-ui
Go to your app → **Logs** tab. Logs stream in real-time.

::cli
```bash
wokku logs my-app
wokku logs my-app --num 200
wokku logs my-app --tail
```

::api
```bash
curl https://wokku.dev/api/v1/apps/my-app/logs?lines=100 \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show me the logs for my-app"*

::mobile
Tap your app → **Logs** tab.
:::

## Log Drains

Forward logs to external services. See [Monitoring → Logs](/docs/monitoring/logs) for log drain setup.
