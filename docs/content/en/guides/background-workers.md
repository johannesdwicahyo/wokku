---
title: Run Background Workers
summary: Run Sidekiq, Celery, BullMQ or any non-web process next to your web app.
last_updated: 2026-11-07
---

You'll declare a worker in your `Procfile`, deploy, and scale it to one or more instances.

## 1. Declare the worker

```procfile
web: bin/rails server -p $PORT
worker: bundle exec sidekiq
```

Other examples:

```procfile
worker: celery -A myproject worker --loglevel=info   # Celery
worker: node worker.js                                # BullMQ / custom
```

## 2. Deploy

```bash
git push wokku main
```

Only `web` starts by default. Other process types run once you scale them.

## 3. Scale the worker

:::tabs
::web-ui
App → **Runtime** tab → **Scaling** → set CPU, RAM and instances for `worker`.

::cli
```bash
wokku ps:scale my-app worker=1
wokku ps:scale my-app web=2 worker=2   # both at once
```

::mcp
Ask Claude: *"Scale my-app to 1 worker."*
:::

Each process type is sized and billed on its own. See [Scaling Processes](/docs/scaling/dynos).

## 4. Add a queue backend

Most workers need Redis. Add a free shared one:

```bash
wokku addons:shared:enable my-app redis
```

`REDIS_URL` is set on the app, and every process type sees it. See [Add a database](/docs/databases/create-link).

## Troubleshooting

- **Worker not running**: scale it to at least 1.
- **Jobs not picked up**: check that web and worker use the same `REDIS_URL`.
- **Jobs killed on deploy**: workers get `SIGTERM` when replaced. Keep jobs idempotent. See [Production Readiness](/docs/apps/best-practices).

## Next steps

- [Schedule tasks (cron)](/docs/guides/scheduled-tasks)
- [Logs](/docs/monitoring/logs)
