---
title: Nuxt
summary: Run a Nuxt app on Wokku as a Nitro Node server.
last_updated: 2026-11-07
---

`nuxt build` produces a self-contained Nitro server in `.output/`. Start it, push, and the app is live.

## Build and start

```json
{
  "scripts": {
    "build": "nuxt build",
    "start": "node .output/server/index.mjs"
  }
}
```

```procfile
web: npm start
```

Nitro reads `PORT` and `HOST` from the environment, so no flags are needed.

## Environment variables

Nuxt overrides `runtimeConfig` from `NUXT_*` variables at runtime (`NUXT_PUBLIC_*` for public values), so set them as [config vars](/docs/apps/config):

```bash
wokku config:set my-app NODE_ENV=production NUXT_PUBLIC_API_BASE=https://api.example.com
```

## Database (optional)

```bash
wokku addons:shared:enable my-app postgres
```

Read `process.env.DATABASE_URL` in your server routes or ORM. See [Create & Link a Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crashes on boot** — start `.output/server/index.mjs`, not `nuxt dev` or `nuxt preview`.
- **Fully static site** — run `nuxt generate` and serve `.output/public` as a [static site](/docs/frameworks/static).
