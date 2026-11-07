---
title: Node.js
summary: Run any Node HTTP server (Express, Fastify, Koa, Hono) on Wokku.
last_updated: 2026-11-07
---

Add a `start` script, listen on `process.env.PORT`, push, and the app is live. Want a working repo first? Deploy the `express` starter from [Templates](/docs/templates/browse).

## Start script and port

Nixpacks installs dependencies from your lockfile, runs `build` if you have one, then `npm start`:

```json
{
  "scripts": { "start": "node server.js" },
  "engines": { "node": "22.x" }
}
```

```js
const port = process.env.PORT || 3000;
app.listen(port, "0.0.0.0", () => console.log(`listening on ${port}`));
```

Pin the Node version with `engines.node` (or a `.node-version` file). A Procfile is optional (`web: npm start`).

## Database (optional)

```bash
wokku addons:shared:enable my-app postgres
```

Read `process.env.DATABASE_URL` in `pg`, Prisma or Drizzle. See [Create & Link a Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crashes or never responds** — a hardcoded port. Use `process.env.PORT`.
- **Install fails** — commit your lockfile (`package-lock.json`, `pnpm-lock.yaml` or `yarn.lock`).
- **Background jobs** — add `worker: node worker.js` to a Procfile and scale it. See [Background Workers](/docs/guides/background-workers).
