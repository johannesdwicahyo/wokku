# Migrate to Wokku

Moving from another platform? These guides map each platform's concepts to
Wokku and walk you through the move — app, environment, database, and domain —
with as little downtime as possible.

## Pick your source

- **[From Heroku](/docs/migrate/heroku)** — the closest match: Procfile, buildpacks, add-ons, `git push`
- **[From Vercel](/docs/migrate/vercel)** — Next.js and serverless → long-running container
- **[From Netlify](/docs/migrate/netlify)** — static sites + functions
- **[From Render](/docs/migrate/render)** — web services, managed DBs, cron jobs
- **[From a bare VPS](/docs/migrate/vps)** — replace nginx + systemd + manual deploys + certbot

## The general shape of a migration

Whatever you're coming from, the move is the same four steps:

1. **Re-create the app** on Wokku ([create an app](/docs/apps/create))
2. **Copy environment variables** ([config](/docs/apps/config))
3. **Move the database** — `pg_dump` from the old provider, restore into a Wokku
   [Postgres add-on](/docs/guides/postgres-redis)
4. **Point your domain** — add it with automatic SSL, then cut over DNS
   ([custom domains](/docs/domains-ssl/custom-domains))

:::callout note
Deploy to the temporary `*.wokku.app` URL first and verify everything works.
Only switch your real domain's DNS once you're happy — that keeps downtime to a
DNS-propagation window.
:::

## Database move, in brief

```bash
# 1. Dump from your current provider (custom format)
pg_dump "$OLD_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

# 2. Create the Wokku database and read its URL
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL

# 3. Restore into Wokku
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Each guide below repeats this with provider-specific notes.
