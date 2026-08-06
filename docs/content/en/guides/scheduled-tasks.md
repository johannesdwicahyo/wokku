# Schedule Tasks (Cron)

Run a command on a schedule — nightly cleanups, report emails, cache warmers,
data syncs — without a long-running worker.

:::callout note
Scheduled tasks are a **Pro** feature. See [Plans](/docs/billing/plans).
:::

## How it works

A scheduled task runs a one-off command inside a fresh copy of your app's
container on a cron schedule, then exits. It shares your app's config vars and
linked add-ons, so it can reach your database and Redis.

## Create a scheduled task

:::tabs
::web-ui
1. Open your app → **Scheduled Tasks**
2. **New Task** → enter a cron expression and the command
3. Save — it runs on schedule from now on

::cli
```bash
# every day at 02:00
wokku scheduled-tasks:create my-app \
  --schedule "0 2 * * *" \
  --command "bin/rails runner 'Cleanup.run'"
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"schedule": "0 2 * * *", "command": "bin/rails runner Cleanup.run"}'
```

::mcp
Ask Claude: *"Schedule `bin/rails runner Cleanup.run` to run daily at 2am on my-app"*
:::

## Cron expression quick reference

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
| `0 * * * *` | hourly, on the hour |
| `0 2 * * *` | daily at 02:00 |
| `0 0 * * 1` | every Monday at midnight |

:::callout warn
Schedules run in **UTC**. Convert your local time (WIB is UTC+7) — e.g. 09:00
WIB = `0 2 * * *`.
:::

## List & remove

:::tabs
::cli
```bash
wokku scheduled-tasks my-app            # list
wokku scheduled-tasks:remove my-app ID  # remove
```
:::

## Troubleshooting

- **Task didn't run** — confirm the cron is UTC and the app is Pro.
- **Command not found** — use the same path you'd use in `wokku run` (e.g. `bin/rails`, `python manage.py`).
- **Needs the DB** — it inherits config vars + add-ons automatically; no extra wiring.

## Next steps

- [Run background workers](/docs/guides/background-workers) · [Logs](/docs/apps/logs)
