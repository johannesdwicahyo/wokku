---
title: Migrate from Heroku
summary: Move a Heroku app to Wokku with its config vars, Postgres data and domain.
last_updated: 2026-11-07
---

Most Heroku apps already listen on `$PORT` and have a Procfile, so the move is config, data and DNS. Two differences matter: Wokku builds with your Dockerfile or Nixpacks (not buildpacks), and there's no release phase.

## Concept map

| Heroku | Wokku |
|---|---|
| `heroku` CLI | `wokku` CLI ([install](/docs/cli/install)) |
| Buildpacks | Your `Dockerfile`, or Nixpacks auto-detect |
| `Procfile` | `Procfile` (`web:` and other process types) |
| `release:` phase | None. Run `wokku run my-app -- <migrate>` after deploys |
| Dyno formation | [Scaling Processes](/docs/scaling/dynos) (`wokku ps:scale`) |
| Dyno size | [Resources](/docs/scaling/resources) (CPU and RAM) |
| Config vars | [Environment Variables](/docs/apps/config) |
| Heroku Postgres / Redis | [Database add-ons](/docs/databases/create-link) |
| Heroku Scheduler | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Review Apps | [Preview Deploys](/docs/guides/preview-deploys) |
| `heroku rollback` | [Rollback](/docs/guides/rollback) |
| `heroku run` | `wokku run my-app -- <command>` |

## 1. Create the app and copy config

```bash
wokku apps:create my-app
heroku config --json -a my-heroku-app \
  | jq -r 'to_entries[] | select(.key != "DATABASE_URL" and .key != "REDIS_URL") | "\(.key)=\(.value)"' \
  | while IFS= read -r pair; do wokku config:set my-app "$pair"; done
```

This skips `DATABASE_URL` and `REDIS_URL`, which Wokku's add-ons set. Also drop vars for Heroku add-ons you won't use.

## 2. Move the database

```bash
heroku pg:backups:capture -a my-heroku-app
heroku pg:backups:download -a my-heroku-app        # writes latest.dump

wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                                # note the database name
wokku databases:import <database-name> latest.dump
```

Used Heroku Redis? `wokku addons:shared:enable my-app redis` sets `REDIS_URL`. More in [Move a database](/docs/migrate/index).

## 3. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

If your Procfile has a `release:` line, remove it and run that command after each deploy instead, for example `wokku run my-app -- bin/rails db:migrate`.

## 4. Switch the domain

Check the app on `https://my-app.wokku.app`, then add your domain (HTTPS is automatic) and update DNS. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Buildpack-specific commands** — Procfile lines such as `heroku-php-apache2` don't exist here. See your [framework guide](/docs/frameworks/index).
- **Temporary disk** — same as Heroku. Keep uploads in [object storage](/docs/databases/object-storage).
- **Add-on variable names** — point your app at `DATABASE_URL` / `REDIS_URL`, not Heroku add-on names like `HEROKU_POSTGRESQL_*`.
