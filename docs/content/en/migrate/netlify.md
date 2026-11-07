---
title: Migrate from Netlify
summary: Move a Netlify static site, and any functions, to Wokku.
last_updated: 2026-11-07
---

A pure static site moves in a few minutes. Netlify Functions become routes in a small Node server.

## Concept map

| Netlify | Wokku |
|---|---|
| Publish directory | [Static Site](/docs/frameworks/static) (`Staticfile`, or serve `dist`) |
| Build command | `build` script in `package.json` |
| Netlify Functions | Routes in a [Node server](/docs/frameworks/nodejs) |
| Environment variables | [Environment Variables](/docs/apps/config) (runtime only) |
| `_redirects` / `_headers` | Your server's routing and middleware |
| Domains and HTTPS | [Custom Domains](/docs/domains-ssl/custom-domains) |

## Static site

1. No build step: add a `Staticfile`. With a build step: serve the output folder with `serve`. See [Static Site](/docs/frameworks/static).
2. Deploy:

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## Site with functions

Move each function into one server (Express, Hono, etc.) that serves the built site and mounts each function under `/api/...`:

```procfile
web: node server.js
```

Set the secrets the functions used as [config vars](/docs/apps/config).

## Redirects and headers

Re-create `_redirects` and `_headers` rules as routes and middleware in your server. The SPA rule `/* /index.html 200` becomes a catch-all route, or `serve -s` for a static site.

## Switch the domain

Check `https://my-app.wokku.app`, then add your domain (HTTPS is automatic) and update DNS. See [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Build-time variables** — Wokku config vars aren't available during the build. Commit public build values (for example in `.env.production`).
- **Netlify Forms and Identity** — these have no Wokku equivalent; replace them in your app.
