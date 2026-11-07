---
title: Migrate from Vercel
summary: Move a Next.js app from Vercel to a long-running Wokku app.
last_updated: 2026-11-07
---

On Wokku your app runs as one long-running server, so it has no cold starts or function timeouts. For Next.js the move is mostly config and DNS.

## Concept map

| Vercel | Wokku |
|---|---|
| Serverless / Edge Functions | Routes inside one `next start` server |
| Environment Variables | [Environment Variables](/docs/apps/config) |
| Vercel Postgres / Neon | [Postgres add-on](/docs/databases/create-link) |
| Vercel KV / Upstash Redis | Redis add-on |
| Cron Jobs | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Preview Deployments | [Preview Deploys](/docs/guides/preview-deploys) |
| Domains | [Custom Domains](/docs/domains-ssl/custom-domains) |

## 1. Run it as a server

Follow the [Next.js guide](/docs/frameworks/nextjs): keep `"build": "next build"` and `"start": "next start"`. API routes and server actions keep working inside that server. Code pinned to the Edge runtime may need `export const runtime = "nodejs"`.

## 2. Copy environment variables

```bash
wokku apps:create my-app
vercel env pull .env.vercel --environment=production
grep -v '^#' .env.vercel | grep -v '^NEXT_PUBLIC_' | grep '=' \
  | sed 's/="\(.*\)"$/=\1/' \
  | while IFS= read -r pair; do wokku config:set my-app "$pair"; done
```

`NEXT_PUBLIC_*` values are inlined at build time, and Wokku config vars aren't available during the build. Commit them in `.env.production` instead.

## 3. Move data

- **Postgres** — dump it and import into a dedicated Wokku database. See [Move a database](/docs/migrate/index).
- **Redis/KV** — `wokku addons:shared:enable my-app redis` sets `REDIS_URL`. Copy data across only if it isn't a cache.

## 4. Deploy and switch the domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Check `https://my-app.wokku.app`, then move your domain. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Edge middleware and `@vercel/*` packages** — Vercel-only APIs need a Node equivalent.
- **Scaling** — you scale processes and [resources](/docs/scaling/resources), not per-request functions.
- **Vercel Cron** — re-create each `vercel.json` cron as a [scheduled task](/docs/guides/scheduled-tasks).
