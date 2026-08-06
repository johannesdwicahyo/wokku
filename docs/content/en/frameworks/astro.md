# Deploy Astro

Deploy an Astro site to Wokku — static output or server-rendered (SSR).

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- An Astro project (`npm create astro@latest` if starting fresh)

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-astro-site`, box size, **Create**.

::cli
```bash
wokku apps:create my-astro-site --server my-server
```
:::

## 2a. Server-rendered (SSR)

Add the Node adapter so Astro builds a server you can run:

```bash
npx astro add node
```

```js
// astro.config.mjs
import node from "@astrojs/node";
export default defineConfig({ output: "server", adapter: node({ mode: "standalone" }) });
```

`Procfile`:

```procfile
web: HOST=0.0.0.0 PORT=$PORT node ./dist/server/entry.mjs
```

## 2b. Static output

For a fully static site (`output: "static"`, the default), `astro build`
produces `dist/`. Serve it with a tiny static server:

```text
# package.json
"scripts": { "build": "astro build", "start": "npx serve dist -l $PORT" }
```

```procfile
web: npm start
```

:::callout note
For high-traffic static sites, a CDN/static-hosting path is coming as a
dedicated recipe. The `serve` approach above works today on any box.
:::

## 3. Environment variables

```bash
wokku config:set my-astro-site NODE_ENV=production
```

`PUBLIC_*` env vars are inlined at build time — set them before deploying.

## 4. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-astro-site
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-astro-site
git push wokku main
```
:::

Live at `https://my-astro-site.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **Blank page / crash** — for SSR, bind to `HOST=0.0.0.0 PORT=$PORT`.
- **`PUBLIC_*` not applied** — build-time; redeploy after changing it.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)
