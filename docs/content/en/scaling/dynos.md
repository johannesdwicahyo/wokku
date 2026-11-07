---
title: Scaling Processes
summary: Run more instances of your web or worker processes, or change how big each one is.
last_updated: 2026-11-07
---

You'll set how many instances of each process type run.

## Process types

Process types come from your `Procfile`:

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
```

| Type | Purpose |
|------|---------|
| `web` | Serves HTTP requests |
| any other name | Runs in the background (jobs, queues) |

## See what's running

:::tabs
::web-ui
Open your app → **Runtime** → **Scaling**.

::cli
```bash
wokku ps my-app
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Show the processes for my-app"*
:::

## Change the instance count

:::tabs
::web-ui
On **Runtime** → **Scaling**, set **Instances** for each process, then click **Save resources**.

::cli
```bash
wokku ps:scale my-app web=2 worker=1
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scaling": {"web": 2, "worker": 1}}'
```

::mcp
Ask Claude: *"Scale my-app to 2 web and 1 worker"*
:::

## Rules

- 0–10 instances per process.
- `web` can't be scaled to 0. To stop the app, use **Stop** (`wokku ps:stop my-app`).
- A free sleeping app runs one `web` instance only.
- Each instance is billed at its process's size: 2 instances cost twice as much as 1.

## Change the size

To give a process more CPU or RAM instead of more instances:

```bash
wokku ps:resize my-app worker --cpu 0.5 --memory 1024
```

See [Resources & Sizing](/docs/scaling/resources).
