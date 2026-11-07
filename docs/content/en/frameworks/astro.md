---
title: Astro
summary: Run an Astro site on Wokku, server-rendered with the Node adapter or as static output.
last_updated: 2026-11-07
---

Set up the Node adapter (or a static server), push, and your site is live. Want a working repo first? Deploy the `astro` starter from [Templates](/docs/templates/browse).

## Server-rendered (SSR)

Add the Node adapter in standalone mode:

```bash
npx astro add node
```

```js
// astro.config.mjs
import { defineConfig } from "astro/config";
import node from "@astrojs/node";

export default defineConfig({ output: "server", adapter: node({ mode: "standalone" }) });
```

```procfile
web: env HOST=0.0.0.0 node ./dist/server/entry.mjs
```

The standalone server reads `PORT` itself. Use `env HOST=…`; a bare `HOST=… node …` prefix fails in a Procfile.

## Static output

With the default `output: "static"`, `astro build` writes `dist/`. Serve it with a small static server:

```bash
npm install serve
```

```json
"scripts": { "build": "astro build", "start": "serve dist -l $PORT" }
```

```procfile
web: npm start
```

## Environment variables

`PUBLIC_*` variables are inlined at build time, and Wokku config vars are not available during the build. Commit them in `.env.production`. Server-side secrets go in [config vars](/docs/apps/config):

```bash
wokku config:set my-app NODE_ENV=production
```

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **App crashes or never responds** — for SSR, start `dist/server/entry.mjs` with `HOST=0.0.0.0`; for static output, serve on `$PORT`.
- **A `PUBLIC_*` value is missing** — it's build-time; commit it and redeploy.
