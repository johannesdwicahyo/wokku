# Migrate from Render

Render and Wokku are close cousins — web services from a Git repo, managed
Postgres/Redis, background workers, and cron. The move is mostly re-creating the
service and pointing it at a Wokku database.

## Concept map

| Render | Wokku |
|---|---|
| Web Service | App / `web` process |
| Background Worker | `worker` process ([guide](/docs/guides/background-workers)) |
| Cron Job | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| `render.yaml` (blueprint) | `Procfile` + config vars |
| Render Postgres | Postgres add-on ([guide](/docs/guides/postgres-redis)) |
| Render Key Value (Redis) | Redis add-on |
| Environment Groups | Config vars ([config](/docs/apps/config)) |
| Start Command | `web:` line in `Procfile` |

## 1. Translate `render.yaml` → Procfile

Take your service's **start command** and put it in a `Procfile`; add `worker`
and `release` lines for any background workers or pre-deploy commands:

```procfile
web: <your render start command, binding to $PORT>
worker: <your worker command>
release: <your migrate command>
```

Render injects `PORT`; so does Wokku — keep binding to `$PORT`.

## 2. Re-create the app + env

```bash
wokku apps:create my-app --server my-server
```

Copy each variable from your Render **Environment** / Environment Group into
[config vars](/docs/apps/config) (`wokku config:set my-app KEY=VALUE`).

## 3. Move the database

```bash
# Render gives you an external connection string in the dashboard
pg_dump "$RENDER_EXTERNAL_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Add a Redis add-on if you used Render Key Value, and re-point `REDIS_URL`.

## 4. Deploy + domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Verify on `my-app.wokku.app`, then move your domain — see
[Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Disk** — Render persistent disks have no direct equivalent; use object storage or a dedicated DB.
- **Health checks** — Wokku checks the web process; see [Health Checks](/docs/monitoring/health-checks).
- **Cron timezone** — Wokku scheduled tasks run in UTC.

## Next steps

- [Background Workers](/docs/guides/background-workers) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
