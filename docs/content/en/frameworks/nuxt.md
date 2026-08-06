# Deploy Nuxt

Deploy a Nuxt 3 app to Wokku. `nuxt build` produces a self-contained Nitro
server you run with Node.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Nuxt 3 app (`npx nuxi init my-app` if starting fresh)

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-nuxt-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-nuxt-app --server my-server
```
:::

## 2. Prepare your Nuxt app

The Node buildpack runs `nuxt build`, which outputs `.output/`. Start the Nitro
server and point it at `$PORT`:

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

:::callout note
Nitro reads `PORT` (and `HOST`) from the environment automatically, so
`node .output/server/index.mjs` binds to Wokku's assigned port with no extra flags.
:::

## 3. Environment variables

:::tabs
::web-ui
App → **Config** → add `NODE_ENV=production` plus your runtime config. Public
values (`NUXT_PUBLIC_*`) are read at runtime by Nitro; private ones stay server-side.

::cli
```bash
wokku config:set my-nuxt-app NODE_ENV=production
```
:::

## 4. Add a database (optional)

```bash
wokku addons:create postgres my-nuxt-app
```

Read `process.env.DATABASE_URL` in your server routes / ORM. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-nuxt-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-nuxt-app
git push wokku main
```
:::

Live at `https://my-nuxt-app.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **Crashes on boot** — confirm you start `.output/server/index.mjs` (not `nuxt dev`/`preview`).
- **Out-of-memory build** — pick a larger box size for the build step.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)
