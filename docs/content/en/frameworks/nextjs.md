---
title: Next.js
summary: Run a server-rendered Next.js app on Wokku with next start.
last_updated: 2026-11-07
---

Keep the standard `build` and `start` scripts, push, and the app is live. Want a working repo first? Deploy the `nextjs` starter from [Templates](/docs/templates/browse).

## Build and start

Nixpacks detects Next.js from `package.json`, runs `npm run build`, then `npm start`. `create-next-app` already includes both scripts:

```json
{
  "scripts": {
    "build": "next build",
    "start": "next start"
  }
}
```

`next start` reads `PORT` from the environment, so you don't need `-p`. A Procfile is optional (`web: npm start`).

## Environment variables

`NEXT_PUBLIC_*` values are inlined by `next build`, and Wokku config vars aren't available during the build. Commit public values in `.env.production`. Server-only secrets go in [config vars](/docs/apps/config) and are read at runtime:

```bash
wokku config:set my-app NODE_ENV=production
```

## Database (optional)

```bash
wokku addons:shared:enable my-app postgres
```

Read `process.env.DATABASE_URL` in Prisma, Drizzle or `pg`. For Prisma migrations, run `wokku run my-app -- npx prisma migrate deploy` after deploys. See [Create & Link a Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Static export

A site with no server code (`output: "export"`) builds to `out/`. Serve it as described in [Static Site](/docs/frameworks/static).

## Troubleshooting

- **Crashes on boot** — a hardcoded `-p 3000`. Remove it, or use `-p $PORT`.
- **A `NEXT_PUBLIC_*` value is missing** — it's build-time; commit it and redeploy.
