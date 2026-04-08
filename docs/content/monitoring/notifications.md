# Notifications

Get notified about deploys, failures, and server events.

## Supported Channels

| Channel | Setup |
|---------|-------|
| **Email** | Email address |
| **Slack** | Webhook URL |
| **Discord** | Webhook URL |
| **Telegram** | Bot token + chat ID |
| **Webhook** | Any HTTPS endpoint |

## Create a Notification

:::tabs
::web-ui
Go to **Notifications → Add Channel**. Select channel type, event type, and configure.

::cli
```bash
wokku notifications:add --channel slack --event deploy \
  --url https://hooks.slack.com/services/...
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"channel": "slack", "event": "deploy", "config": {"url": "https://hooks.slack.com/..."}}'
```

::mcp
Ask Claude: *"Set up a Slack notification for deploy failures"*

::mobile
Tap **Notifications → +** to add a channel.
:::

## Event Types

| Event | Description |
|-------|-------------|
| **deploy** | Triggered on successful deploy |
| **failure** | Triggered on deploy failure |
| **all** | All events (deploy, failure, server status changes) |

## Remove

:::tabs
::web-ui
Go to **Notifications** → click delete next to the channel.

::cli
```bash
wokku notifications:remove NOTIFICATION_ID
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/notifications/ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Delete notification channel ID"*

::mobile
Tap Notifications → swipe to delete.
:::
