---
cloud_prices: true
title: Schedule Tasks (Cron)
summary: Run a command on a cron schedule, such as nightly cleanups or report emails, without a long-running worker.
last_updated: 2026-11-07
---

You'll add a cron entry that runs a command with your app's config vars and add-ons.

:::callout note
Scheduled tasks are included once your team pays for any resource. Free-only teams see an upgrade prompt. See [Pricing](/docs/billing/pricing).
:::

## Create a task

:::tabs
::web-ui
1. App → **Settings** tab → **Scheduled Tasks**.
2. Add a task: cron schedule, command, optional description.
3. Save.

::cli
```bash
wokku cron:add my-app \
  --schedule "0 2 * * *" \
  --command "bin/rails runner 'Cleanup.run'" \
  --description "Nightly cleanup"
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"schedule": "0 2 * * *", "command": "bin/rails runner Cleanup.run", "description": "Nightly cleanup"}'
```

::mcp
Ask Claude: *"Schedule `bin/rails runner Cleanup.run` daily at 02:00 on my-app."*
:::

## Cron quick reference

```text
┌─ minute (0-59)
│ ┌─ hour (0-23)
│ │ ┌─ day of month (1-31)
│ │ │ ┌─ month (1-12)
│ │ │ │ ┌─ day of week (0-6, Sun=0)
* * * * *
```

| Schedule | Meaning |
|---|---|
| `*/15 * * * *` | every 15 minutes |
| `0 * * * *` | every hour |
| `0 2 * * *` | daily at 02:00 |
| `0 0 * * 1` | Mondays at midnight |

## List and remove

:::tabs
::web-ui
**Settings** tab → **Scheduled Tasks** shows each task. Delete it from the list.

::cli
```bash
wokku cron my-app                  # list, with task IDs
wokku cron:remove my-app TASK_ID   # remove
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks -H "Authorization: Bearer $TOKEN"
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks/TASK_ID -H "Authorization: Bearer $TOKEN"
```
:::

## Troubleshooting

- **Command not found**: use the same command that works with `wokku run my-app -- <command>`.
- **"Upgrade" error**: your team has no paid resources yet.

## Next steps

- [Run background workers](/docs/guides/background-workers)
- [Logs](/docs/monitoring/logs)
