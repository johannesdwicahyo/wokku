# Deploy Next.js

Deploy a server-rendered Next.js app to Wokku, with environment variables, a
database, and HTTPS.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Next.js app locally (`npx create-next-app@latest my-app` if starting fresh)

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → pick a server, name it `my-next-app`, choose a box size, **Create**.

::cli
```bash
wokku apps:create my-next-app --server my-server
```
:::

## 2. Prepare your Next.js app

The Node buildpack auto-detects Next.js from `package.json`. Make sure you have
`build` and `start` scripts (create-next-app adds these):

```json
{
  "scripts": {
    "build": "next build",
    "start": "next start -p $PORT"
  }
}
```

:::callout note
Bind to `$PORT`, not a hardcoded `3000` — Wokku assigns the port at runtime.
`next start -p $PORT` handles this.
:::

Add a `Procfile` (optional but explicit):

```procfile
web: npm run start
```

For a smaller image, enable standalone output in `next.config.js`
(`output: "standalone"`).

## 3. Set environment variables

:::tabs
::web-ui
App → **Config**. Add `NODE_ENV=production` and any `NEXT_PUBLIC_*` /
server-side secrets your app needs.

::cli
```bash
wokku config:set my-next-app NODE_ENV=production
```
:::

:::callout warn
`NEXT_PUBLIC_*` values are baked in **at build time**. Set them before you
deploy, and redeploy after changing them.
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-next-app
```

Wokku injects `DATABASE_URL`; read it from `process.env.DATABASE_URL` in your
Prisma/Drizzle/pg config. See [Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-next-app
git push wokku main
```

::github
Connect the repo under **Apps → Connect GitHub** for auto-deploy on push —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-next-app
git push wokku main
```
:::

Live at `https://my-next-app.wokku.app` when the build finishes.

## Static export?

If your site has no server code, build a static export (`output: "export"`) and
deploy it as a static site — that path is coming in a dedicated guide. For now,
`next start` (above) works for both SSR and static-with-server apps.

## Add a custom domain

See [Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **App crashes on boot** — almost always a hardcoded port. Use `-p $PORT`.
- **Env var not applied** — `NEXT_PUBLIC_*` is build-time; redeploy after changing it.
- **Build runs out of memory** — pick a larger box size for the build, or set `NODE_OPTIONS=--max-old-space-size`.

## Next steps

- [Logs](/docs/apps/logs) · [Environment Variables](/docs/apps/config) · [Production Readiness](/docs/apps/best-practices)
