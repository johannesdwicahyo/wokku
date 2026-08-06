# Migrate from Netlify

Netlify is great for static sites + a sprinkle of functions. On Wokku, the
static build deploys via the static buildpack, and Netlify Functions become
routes in a small server.

## Concept map

| Netlify | Wokku |
|---|---|
| Static publish dir | [Static Site](/docs/frameworks/static) (`Staticfile` / serve `dist`) |
| Netlify Functions | Routes in a Node server ([Node guide](/docs/frameworks/nodejs)) |
| Build command | `build` script (Node buildpack) |
| Environment variables | Config vars ([config](/docs/apps/config)) |
| `_redirects` / `_headers` | App-level routing / server config |
| Custom domains + SSL | [Custom Domains](/docs/domains-ssl/custom-domains) |

## Pure static site

If you have no functions, this is the whole migration:

1. Make sure your build outputs a folder (e.g. `dist`).
2. Serve it — either commit a `Staticfile` (`root: dist`) or add a `start`
   script that serves the folder. See the [Static Site guide](/docs/frameworks/static).
3. Deploy:

```bash
wokku apps:create my-site --server my-server
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```

## Site + functions

Netlify Functions are small HTTP handlers. Move them into a single server (e.g.
Express) that serves both the static build and the `/api/*` routes:

```procfile
web: node server.js
```

Inside `server.js`, serve the static folder and mount each former function as a
route. Set any secrets the functions used as [config vars](/docs/apps/config).

## Redirects & headers

Translate `_redirects` / `_headers` rules into your server's routing/middleware
(or your framework's config). SPA fallback (`/* /index.html 200`) becomes a
catch-all route returning `index.html`.

## Domain

Add your domain (automatic SSL), verify on `my-site.wokku.app`, then cut over
DNS — see [Custom Domains](/docs/domains-ssl/custom-domains).

## Gotchas

- **Build env** — set `NODE_ENV` and any `*_PUBLIC`/build-time vars before deploying.
- **Form handling / identity** — Netlify-specific features (Forms, Identity) need an app-level replacement.
- **Large media** — front the static app with a CDN for high traffic.

## Next steps

- [Static Site guide](/docs/frameworks/static) · [Node.js guide](/docs/frameworks/nodejs)
