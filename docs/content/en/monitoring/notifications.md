---
title: Notifications
summary: Send deploy, crash, downtime, backup and billing alerts to email, Slack, Discord, Telegram or a webhook.
last_updated: 2026-11-07
---

You'll add a notification rule: pick a channel, optionally one app, and the events you care about. Rules belong to the workspace, so everyone gets the same alerts.

## Add a rule

:::tabs
::web-ui
1. Go to **Settings** → **Notifications** → **+ Add rule**.
2. Pick a **Channel** and fill in its setup (see the table below).
3. Optionally pick an **App** — leave it empty for all apps.
4. Tick the **Events** and click **Add rule**.
5. Click **Test** on the new rule to send a sample message.

::cli
The CLI adds **email** rules only — use the dashboard for other channels. Get your workspace ID with `wokku teams`.

```bash
wokku notifications:add --team TEAM_ID --channel email \
  --events deploy_failed,app_down,app_crashed
wokku notifications                     # list rules
wokku notifications:test NOTIFICATION_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "TEAM_ID", "channel": "slack",
       "events": ["deploy_failed", "app_down"],
       "config": {"url": "https://hooks.slack.com/services/..."}}'

curl -X POST https://wokku.cloud/api/v1/notifications/NOTIFICATION_ID/test \
  -H "Authorization: Bearer $TOKEN"
```

Get `team_id` from `GET /api/v1/teams`. Add `app_record_id` to limit the rule to one app.

::mcp
Ask Claude: *"Send deploy failures and downtime alerts for my-app to this Slack webhook: https://hooks.slack.com/…"*
:::

## Channels

| Channel | Setup |
|---|---|
| **Email** | Nothing — goes to the workspace owner's email |
| **Slack** | Incoming webhook URL (`config.url`) |
| **Discord** | Channel webhook URL (`config.url`) |
| **Telegram** | Bot token + chat ID (`config.bot_token`, `config.chat_id`) |
| **Webhook** | Any HTTPS URL (`config.url`). Wokku POSTs JSON: `{"event": "...", "app": "...", "timestamp": "..."}` |
| **Push** | Added for you when you sign in to the Wokku iOS & Mac app |

## Events

| Event | Sent when |
|---|---|
| `deploy_started` | A deploy begins |
| `deploy_succeeded` | A deploy goes live |
| `deploy_failed` | A deploy fails |
| `app_crashed` | A container crashes |
| `app_auto_stopped` | Wokku stops an app that keeps crashing |
| `app_down` | An [uptime check](/docs/monitoring/uptime) finds the app down |
| `app_recovered` | The app answers again |
| `backup_failed` | A database backup fails |
| `domain_added` | A domain is added |
| `app_created` / `app_deleted` | An app is created or deleted |
| `daily_debit_summary` | The daily billing summary |
| `scheduled_task_failing` | A [scheduled task](/docs/guides/scheduled-tasks) fails 3 times in a row |
| `scheduled_task_recovered` | That task succeeds again |

To silence push alerts on your phone without changing the team's rules, [mute them](/docs/monitoring/uptime#mute-push-alerts).

## Remove a rule

:::tabs
::web-ui
**Settings** → **Notifications** → delete the rule.

::cli
```bash
wokku notifications:remove NOTIFICATION_ID
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/notifications/NOTIFICATION_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Delete my Slack notification rule."*
:::
