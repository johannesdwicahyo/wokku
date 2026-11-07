---
title: Static Site
summary: Serve plain HTML/CSS/JS or a build tool's output (Vite, Hugo, Eleventy) on Wokku.
last_updated: 2026-11-07
---

Tell Nixpacks the site is static, or serve the build output with a small Node server, then push.

## Plain files (no build step)

Add a `Staticfile` to the repo root. Nixpacks then serves the files with nginx. If the files live in a subfolder, name it:

```yaml
# Staticfile
root: public    # omit if the files are at the repo root
```

This only applies when the repo has no `package.json`. With one, Nixpacks builds it as a Node app.

## With a build step (Vite, etc.)

Build, then serve the output folder on `$PORT`:

```bash
npm install serve
```

```json
"scripts": { "build": "vite build", "start": "serve -s dist -l $PORT" }
```

```procfile
web: npm start
```

`-s` returns `index.html` for unknown paths, which single-page apps need for deep links. Leave it out for multi-page sites.

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **404 everywhere** — `root:` in `Staticfile` must point at the folder with `index.html`. With a build step, serve the output folder (`dist`, `build`), not the source.
- **SPA deep links 404** — add `-s` to `serve`.
