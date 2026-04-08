# Logs

View app logs and forward them to external services via log drains.

## View Logs

See [Apps → Logs](/docs/apps/logs) for viewing application logs.

## Log Drains

Forward logs to external logging services.

### Add a Log Drain

:::tabs
::web-ui
Go to your app → **Settings → Log Drains → Add Drain**. Enter the drain URL.

::cli
```bash
wokku drains:add my-app syslog://logs.example.com:514
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/log_drains \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"url": "syslog://logs.example.com:514"}'
```

::mcp
Ask Claude: *"Add a log drain to my-app pointing to syslog://logs.example.com:514"*

::mobile
Not available on mobile. Use Web UI or CLI.
:::

### Remove a Log Drain

:::tabs
::web-ui
Go to **Settings → Log Drains** → click delete next to the drain.

::cli
```bash
wokku drains:remove my-app DRAIN_ID
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/apps/my-app/log_drains/DRAIN_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Remove the log drain from my-app"*

::mobile
Not available on mobile.
:::

### Compatible Services

- Papertrail (`syslog+tls://logsN.papertrailapp.com:PORT`)
- Logtail (`https://in.logtail.com/...`)
- Datadog (`https://http-intake.logs.datadoghq.com/...`)
- Any syslog or HTTPS endpoint
