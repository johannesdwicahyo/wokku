---
title: Migrate to Wokku
summary: Move an app from another platform to Wokku with its config, database and domain.
last_updated: 2026-11-07
---

Re-create the app, copy its config, move the database, then switch DNS. Pick your current platform for the specifics.

## Pick your source

- **[Heroku](/docs/migrate/heroku)** — Procfile apps, config vars, Heroku Postgres
- **[Vercel](/docs/migrate/vercel)** — Next.js and serverless functions
- **[Netlify](/docs/migrate/netlify)** — static sites and functions
- **[Render](/docs/migrate/render)** — web services, workers, managed Postgres
- **[A VPS](/docs/migrate/vps)** — nginx, systemd or pm2, certbot

## The four steps

1. **Make the app run on Wokku.** It must listen on `$PORT`. Follow your [framework guide](/docs/frameworks/index), then create the app ([Create & Deploy](/docs/apps/deploy)).
2. **Copy environment variables** with `wokku config:set my-app KEY=VALUE ...` ([Environment Variables](/docs/apps/config)).
3. **Move the database** (below).
4. **Point your domain.** Check everything on `https://my-app.wokku.app` first, then add your domain and switch DNS ([Custom Domains](/docs/domains-ssl/custom-domains)). Downtime is limited to DNS propagation.

## Move a database

Import works on **dedicated** databases (Postgres, MySQL, MariaDB, MongoDB). Shared add-ons can't import a dump, so add a dedicated database for the move:

```bash
# 1. Dump from your current provider (Postgres custom format)
pg_dump "$OLD_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

# 2. Add a dedicated Postgres to the app and find its name
wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app

# 3. Import (this overwrites the database)
wokku databases:import <database-name> dump.bin
```

The add-on sets `DATABASE_URL` on the app. Delete any `DATABASE_URL` you copied from the old platform. Import accepts plain SQL or `pg_dump -Fc` for Postgres, `mysqldump` output for MySQL/MariaDB, and `mongodump --archive` for MongoDB. See [Create & Link a Database](/docs/databases/create-link).

:::callout note
Stop writes to the old app (maintenance mode, or scale it to zero) before the final dump, so no data is lost between dump and cut-over.
:::
