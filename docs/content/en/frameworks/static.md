# Deploy a Static Site

Deploy plain HTML/CSS/JS or any build-tool output (Vite, plain SPA, Hugo,
Eleventy) to Wokku.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A folder of static files (or a build that produces one)

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-site`, box size, **Create**.

::cli
```bash
wokku apps:create my-site --server my-server
```
:::

## 2. Tell Wokku it's static

Add an empty `Staticfile` to the root of what you want served. By default the
repo root is served; set `root:` if your files live in a subfolder:

```yaml
# Staticfile
root: public        # omit if files are at the repo root
```

That's it — the static buildpack serves your files over HTTP, with clean URLs
and gzip.

## 3. With a build step (Vite, etc.)

If you build first, use the Node buildpack and serve the output instead:

```text
# package.json
"scripts": { "build": "vite build", "start": "npx serve dist -l $PORT" }
```

```procfile
web: npm start
```

## 4. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```
:::

Live at `https://my-site.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **404s everywhere** — check `root:` in `Staticfile` points at your files.
- **SPA deep links 404** — add a fallback so unknown routes serve `index.html` (SPA mode).
- **Build output not served** — with a build step, serve the output dir (`dist`/`build`), not the source.

## Next steps

- [Custom Domains](/docs/domains-ssl/custom-domains) · [Logs](/docs/apps/logs)
