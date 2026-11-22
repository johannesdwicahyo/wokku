---
title: Migrate from a VPS
summary: Replace nginx, systemd, certbot and manual deploys on a VPS with git push to Wokku.
last_updated: 2026-11-07
---

Wokku is managed: you push code, and Wokku runs the server, routing and HTTPS. Make the app listen on `$PORT`, move config and data, then switch DNS.

## What replaces what

| On your VPS | On Wokku |
|---|---|
| systemd unit / pm2 | The `web:` line of a `Procfile` |
| nginx reverse proxy | Built-in routing to `$PORT` |
| certbot renewals | Automatic HTTPS ([Custom Domains](/docs/domains-ssl/custom-domains)) |
| `git pull` + restart script | `git push wokku main` (build, then restart) |
| Hand-installed runtimes | Your `Dockerfile`, or Nixpacks auto-detect |
| `crontab` | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| `.env` on the box | [Environment Variables](/docs/apps/config) |
| Local Postgres/MySQL | [Database add-ons](/docs/databases/create-link) |

## 1. Make the app buildable

- Standard stack: follow your [framework guide](/docs/frameworks/index). Nixpacks detects the language.
- Unusual system packages: commit a [Dockerfile](/docs/guides/dockerfile).

Either way, the app must **listen on `$PORT`** on `0.0.0.0`. nginx isn't in front any more.

## 2. Create the app and copy config

```bash
wokku apps:create my-app
wokku config:set my-app KEY1=value1 KEY2=value2
```

Copy values from your `.env` file or systemd `Environment=` lines.

## 3. Move the database

```bash
# on the VPS
pg_dump "postgres://user:pass@localhost/dbname" --no-owner --no-acl -Fc -f dump.bin

# on your machine (after copying dump.bin down)
wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                          # note the database name
wokku databases:import <database-name> dump.bin
```

For MySQL/MariaDB, import a `mysqldump` file the same way. See [Move a database](/docs/migrate/index).

## 4. Deploy and switch DNS

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Check `https://my-app.wokku.app`, add your domain, point DNS at Wokku, and shut down the VPS once traffic has moved.

## Gotchas

- **Local files** — uploads and SQLite files on disk must move to [object storage](/docs/databases/object-storage) or a database. The app's disk is temporary.
- **Cron scripts** — turn them into [scheduled tasks](/docs/guides/scheduled-tasks) or a `worker` process.
- **Hardcoded ports and paths** — listen on `$PORT`, and don't assume nginx or a fixed directory layout.
