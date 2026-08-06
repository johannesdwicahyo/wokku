# Migrate from Heroku

Wokku is the closest thing to Heroku you can run on your own servers — same
`Procfile`, same buildpacks, same `git push` deploy, same config vars and
add-ons. Most apps move with **zero code changes**.

## Concept map

| Heroku | Wokku |
|---|---|
| Dyno | Box |
| `heroku` CLI | `wokku` CLI |
| Config vars | Config vars ([config](/docs/apps/config)) |
| `Procfile` | `Procfile` (identical) |
| Buildpacks | Buildpacks (auto-detected) |
| Heroku Postgres | Postgres add-on ([guide](/docs/guides/postgres-redis)) |
| Heroku Data for Redis | Redis add-on |
| Heroku Scheduler | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Review Apps | [PR Previews](/docs/guides/preview-deploys) |
| `heroku releases` / rollback | [Releases / rollback](/docs/guides/rollback) |
| `heroku run` | `wokku run` |

## 1. Export your Heroku config

```bash
heroku config -s -a my-heroku-app > heroku.env
```

## 2. Create the Wokku app + import config

```bash
wokku apps:create my-app --server my-server
# import each KEY=VALUE line:
while IFS= read -r line; do wokku config:set my-app "$line"; done < heroku.env
```

Drop Heroku-internal vars you don't need (e.g. the old `DATABASE_URL` — Wokku
sets its own when you add the database below).

## 3. Move the database

```bash
# pull a dump from Heroku
heroku pg:backups:capture -a my-heroku-app
heroku pg:backups:download -a my-heroku-app   # -> latest.dump

# create Wokku Postgres + restore
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" latest.dump
```

## 4. Deploy

Your `Procfile` already works. Just add the remote and push:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

If you used a `release:` phase on Heroku for migrations, it runs the same way on
Wokku.

## 5. Cut over the domain

Add your domain on Wokku (SSL is automatic), verify the app on
`my-app.wokku.app`, then repoint DNS. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Ephemeral filesystem** — same as Heroku; don't store uploads on disk. Use object storage.
- **`DATABASE_URL`** — let the Wokku add-on set it; remove the imported Heroku one.
- **Add-on env var names** — Heroku add-ons inject their own var names; point your app at Wokku's `DATABASE_URL` / `REDIS_URL`.

## Next steps

- [Background Workers](/docs/guides/background-workers) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
