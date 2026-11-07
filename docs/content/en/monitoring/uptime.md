---
title: Uptime & Incidents
summary: Wokku checks your app every minute, opens an incident when it goes down, and tells you — mute push alerts when you need quiet.
last_updated: 2026-11-07
---

You'll see how uptime checks work, look up incidents, and mute alerts on your phone. Uptime checks are on for every running app that has a domain — nothing to enable.

## How uptime checks work

- Every minute Wokku requests `https://<your-domain>/` (your app's first domain, e.g. `my-app.wokku.app`).
- **Up** = any answer below HTTP 500. A 404 still means your app is alive.
- **Down** = 3 failed checks in a row. Wokku opens an **incident** and sends an `app_down` [notification](/docs/monitoring/notifications).
- The first successful check closes the incident and sends `app_recovered`.
- Free apps that [sleep when idle](/docs/scaling/resources) are not checked, so checks don't keep them awake.

Each incident records a reason:

| Reason | Meaning |
|---|---|
| `host_down` | Our host is unreachable — not your code; we're on it |
| `app_stopped` | The app is stopped |
| `app_crashed` | The container crashed — check `wokku logs my-app` |
| `http_5xx` | The app answers with server errors |
| `timeout` | The app doesn't answer in time |
| `connection_refused` | Nothing is listening on the app's port |
| `dns_error` | The domain doesn't resolve |
| `ssl_error` | The SSL certificate fails the handshake |

Platform-wide status is public at [status.wokku.cloud](https://status.wokku.cloud).

## List incidents

:::tabs
::cli
```bash
wokku incidents                  # open incidents
wokku incidents --all            # recent ones, resolved too
wokku incidents --app my-app     # one app
wokku incidents:info INCIDENT_ID # reason, start, end, duration
```

::api
```bash
curl -G https://wokku.cloud/api/v1/incidents \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "state=all" \
  --data-urlencode "app_id=my-app"

curl https://wokku.cloud/api/v1/incidents/INCIDENT_ID \
  -H "Authorization: Bearer $TOKEN"
```

`state` is `open` (default) or `all`. Also takes `limit` (1–200, default 50) and `before` (ISO 8601).

::mcp
Ask Claude: *"Is anything down?"*
:::

## Mute push alerts

Mutes silence **push alerts on your phone only**, for you only. Email, Slack, Discord, Telegram and webhook alerts keep going to the whole team.

Mute an app, an event, or both — optionally for a while. Without a time limit, the mute lasts until you remove it.

:::tabs
::cli
```bash
wokku alerts:mute --app my-app --for 8h       # all events for my-app, 8 hours
wokku alerts:mute --event deploy_succeeded    # one event, every app
wokku alerts:mutes                            # list active mutes
wokku alerts:unmute MUTE_ID
```

`--for` takes minutes, hours or days: `30m`, `8h`, `1d`.

::api
```bash
curl -X POST https://wokku.cloud/api/v1/alert_mutes \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"app_id": "my-app", "event": "app_down", "until": "2026-11-08T09:00:00Z"}'

curl https://wokku.cloud/api/v1/alert_mutes -H "Authorization: Bearer $TOKEN"
curl -X DELETE https://wokku.cloud/api/v1/alert_mutes/MUTE_ID -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Mute alerts for my-app until tomorrow morning."*
:::

Events you can mute: `deploy_succeeded`, `deploy_failed`, `app_crashed`, `backup_completed`, `backup_failed`, `resource_high_cpu`, `resource_high_memory`, `app_down`, `app_recovered`.

:::callout note
Push alerts need the Wokku iOS & Mac app, which is coming soon. See [iOS & Mac App](/docs/mobile/download).
:::

## See also

- [Notifications](/docs/monitoring/notifications) — choose where `app_down` alerts go
- [Health checks](/docs/monitoring/health-checks) — safety during deploys
