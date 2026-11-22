---
title: Migrate from Render
summary: Move Render web services, workers, cron jobs and Postgres to Wokku.
last_updated: 2026-11-07
---

Render and Wokku work alike: services from a Git repo, managed databases, workers and cron. Translate your `render.yaml` into a Procfile, then move config and data.

## Concept map

| Render | Wokku |
|---|---|
| Web Service | The `web` process |
| Background Worker | Another process type ([Background Workers](/docs/guides/background-workers)) |
| Cron Job | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Build / Start Command | Your `Dockerfile` or Nixpacks / Procfile `web:` line |
| Pre-Deploy Command | None. Run `wokku run my-app -- <command>` after deploys |
| Instance type | [Resources](/docs/scaling/resources) (CPU and RAM) |
| Render Postgres | [Postgres add-on](/docs/databases/create-link) |
| Render Key Value | Redis add-on |
| Environment Groups | [Environment Variables](/docs/apps/config) |

## 1. Write a Procfile

```procfile
web: <your start command, listening on $PORT>
worker: <your worker command>
```

Render sets `PORT` and so does Wokku, so keep listening on it. Run your pre-deploy command (usually migrations) after each deploy, for example `wokku run my-app -- npm run migrate`.

## 2. Create the app and copy config

```bash
wokku apps:create my-app
wokku config:set my-app KEY1=value1 KEY2=value2
```

Copy each variable from the service's **Environment** and any Environment Groups. Skip `DATABASE_URL` and `REDIS_URL`; Wokku's add-ons set them.

## 3. Move the database

```bash
# Use the External Database URL from the Render dashboard
pg_dump "$RENDER_EXTERNAL_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                          # note the database name
wokku databases:import <database-name> dump.bin
```

Used Key Value? `wokku addons:shared:enable my-app redis` sets `REDIS_URL`. More in [Move a database](/docs/migrate/index).

## 4. Deploy and switch the domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Check `https://my-app.wokku.app`, then move your domain. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Persistent disks** — there's no attached disk. Keep files in [object storage](/docs/databases/object-storage) or a database.
- **Health check path** — set it under [Health Checks](/docs/monitoring/health-checks).
