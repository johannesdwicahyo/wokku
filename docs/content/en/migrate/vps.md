# Migrate from a Bare VPS

Running your app by hand on a VPS — nginx, systemd or pm2, manual `git pull`,
certbot renewals? Wokku keeps the control of your own server but replaces all
the glue with `git push`.

## What Wokku replaces

| On your VPS today | On Wokku |
|---|---|
| `systemd` unit / `pm2` process | A `web` process from your `Procfile` |
| nginx reverse proxy | Built-in routing to your app |
| certbot + cron renewal | Automatic SSL ([SSL](/docs/domains-ssl/ssl)) |
| `git pull` + restart script | `git push` (build + release + restart) |
| Manually installed runtime | Buildpack (auto) or your `Dockerfile` |
| `crontab` | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| `.env` file on the box | Config vars ([config](/docs/apps/config)) |
| `apt install postgresql` | Postgres add-on ([guide](/docs/guides/postgres-redis)) |

## 1. Make the app buildpack- or Docker-ready

- If it's a standard stack, add a `Procfile` and let the buildpack detect it —
  see your [framework guide](/docs/frameworks/index).
- If it has unusual system dependencies, commit a `Dockerfile` —
  see [Deploy with a Dockerfile](/docs/guides/dockerfile).

Make sure the app **listens on `$PORT`** instead of a fixed port behind nginx.

## 2. Move your environment

Copy values from your server's `.env` (or systemd `Environment=` lines) into
[config vars](/docs/apps/config).

## 3. Move the database

If Postgres runs on the VPS:

```bash
# on the VPS (or over SSH)
pg_dump "postgres://user:pass@localhost/dbname" --no-owner --no-acl -Fc -f dump.bin

# create Wokku Postgres + restore
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Move uploaded files to object storage — Wokku containers have an ephemeral disk.

## 4. Deploy

```bash
wokku apps:create my-app --server my-server
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## 5. Cut over DNS

Add your domain on Wokku (SSL provisions automatically), verify on
`my-app.wokku.app`, then point your DNS at Wokku and decommission the old box
once traffic has moved. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Local file writes** — anything you wrote to disk (uploads, SQLite) must move to a DB or object storage.
- **Background jobs from cron** — convert to a `worker` process or [Scheduled Tasks](/docs/guides/scheduled-tasks).
- **Hardcoded ports/paths** — bind to `$PORT`; don't assume nginx is in front.

## Next steps

- [Deploy with a Dockerfile](/docs/guides/dockerfile) · [Production Readiness](/docs/apps/best-practices)
