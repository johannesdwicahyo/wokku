# Migrate from Vercel

Vercel runs your app as serverless/edge functions. Wokku runs it as a normal
**long-running container** — which means no cold starts, no function timeouts,
and a real server you can put workers and cron next to. For Next.js, the move is
straightforward.

## Concept map

| Vercel | Wokku |
|---|---|
| Serverless / Edge Functions | One long-running server process (`web`) |
| `next start` (managed) | `next start -p $PORT` ([Next.js guide](/docs/frameworks/nextjs)) |
| Environment Variables | Config vars ([config](/docs/apps/config)) |
| Vercel Postgres | Postgres add-on ([guide](/docs/guides/postgres-redis)) |
| Vercel KV (Redis) | Redis add-on |
| Cron Jobs | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Preview Deployments | [PR Previews](/docs/guides/preview-deploys) |
| Custom Domains | [Custom Domains](/docs/domains-ssl/custom-domains) |

## 1. Make the app run as a server

Follow the [Next.js guide](/docs/frameworks/nextjs): ensure `build` + `start`
scripts and that `start` binds to `$PORT`:

```json
{ "scripts": { "build": "next build", "start": "next start -p $PORT" } }
```

API routes / server actions keep working — they run inside this server instead
of as isolated functions. Pure **Edge runtime** code may need to move to the
Node runtime (`export const runtime = "nodejs"`).

## 2. Copy environment variables

Export from the Vercel dashboard (or `vercel env pull .env`), then:

```bash
wokku apps:create my-app --server my-server
# from a .env file:
while IFS= read -r line; do [ -n "$line" ] && wokku config:set my-app "$line"; done < .env
```

:::callout warn
`NEXT_PUBLIC_*` values are baked in at **build time** — set them on Wokku before
your first deploy, and redeploy after changing them.
:::

## 3. Move data

- **Vercel Postgres** → `pg_dump` the connection string, restore into a Wokku
  Postgres add-on (see the [migration overview](/docs/migrate/index)).
- **Vercel KV** → add a Wokku Redis add-on and re-point `REDIS_URL`.

## 4. Deploy + domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Verify on `my-app.wokku.app`, then move your domain — see
[Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Edge-only APIs** — `@vercel/edge` / middleware on the edge runtime may need a Node equivalent.
- **`/api` as functions** — they become normal routes in one server; behaviour is the same, scaling is per-box not per-request.
- **Image optimization** — `next/image` works; for heavy traffic, front it with a CDN.

## Next steps

- [Next.js guide](/docs/frameworks/nextjs) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
