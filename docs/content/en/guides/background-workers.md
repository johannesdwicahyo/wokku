# Run Background Workers

Run queues, job consumers, or any long-running non-web process alongside your
web app — Sidekiq, Celery, BullMQ, a custom consumer, anything.

## How it works

Wokku runs each line in your `Procfile` as its own process type. The `web`
process gets HTTP traffic; any other process type (commonly `worker`) runs in
the background. You scale each independently.

## 1. Declare the worker in your Procfile

```procfile
web: bin/rails server -p $PORT
worker: bundle exec sidekiq
```

Other examples:

```procfile
worker: celery -A myproject worker --loglevel=info   # Celery (Python)
worker: node worker.js                                # BullMQ / custom (Node)
```

## 2. Deploy

```bash
git push wokku main
```

On deploy, Wokku starts your `web` process. Background processes start at **zero
instances** by default — you scale them up explicitly.

## 3. Scale the worker

:::tabs
::web-ui
Open your app → **Resources** → set the instance count for `worker`.

::cli
```bash
wokku scale my-app worker=1
# scale both at once:
wokku scale my-app web=2 worker=2
```
:::

See [Bundled Processes](/docs/scaling/bundled-processes) for how process scaling
and box sizing interact.

## 4. Share a queue backend

Workers usually need Redis (or your DB) as the broker. Add it once and both the
web and worker processes read the same `REDIS_URL` / `DATABASE_URL`:

```bash
wokku addons:create redis my-app
```

See [Add Postgres + Redis](/docs/guides/postgres-redis).

:::callout note
All process types of an app share the same config vars and linked add-ons —
set `REDIS_URL` once and the worker sees it too.
:::

## Troubleshooting

- **Worker not running** — it defaults to 0 instances; scale it to ≥1.
- **Jobs not picked up** — confirm web and worker point at the same broker URL.
- **Worker killed on deploy** — long jobs receive `SIGTERM`; handle graceful shutdown and keep jobs idempotent.

## Next steps

- [Schedule tasks (cron)](/docs/guides/scheduled-tasks) · [Logs](/docs/apps/logs)
