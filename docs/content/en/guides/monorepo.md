---
title: Deploy from a Monorepo
summary: Deploy one subdirectory of a larger repo as its own Wokku app with git subtree.
last_updated: 2026-11-07
---

You'll push just one subdirectory (for example `apps/api`) to a Wokku app.

## Push a subtree

`git subtree` pushes a subdirectory as if it were the repo root.

```bash
# from the repo root
git subtree push --prefix apps/api wokku main
```

If that's slow or rejected as a non-fast-forward, split first and force-push:

```bash
git subtree split --prefix apps/api -b deploy-api
git push wokku deploy-api:main --force
```

Your `Procfile`, `Dockerfile` and dependency manifest (`package.json`, `Gemfile`, …) must sit in that subdirectory, because it becomes the root Wokku builds.

## Several apps from one repo

Create one app per deployable, each with its own remote:

```bash
wokku apps:create my-api
wokku apps:create my-web
git remote add wokku-api git@git.wokku.cloud:my-api
git remote add wokku-web git@git.wokku.cloud:my-web
git subtree push --prefix apps/api wokku-api main
git subtree push --prefix apps/web wokku-web main
```

:::callout note
GitHub auto-deploy builds from the repo root. For a monorepo, use subtree pushes (from your machine or CI).
:::

## Troubleshooting

- **"Updates were rejected"**: use the split and `--force` form above.
- **Wrong language detected**: the manifest must be at the subdirectory root.
- **Shared packages missing**: a subtree push only carries that folder. Copy shared code into it, or use a [Dockerfile](/docs/guides/dockerfile) at the subdirectory root.

## Next steps

- [Deploy with a Dockerfile](/docs/guides/dockerfile)
- [Create & Deploy](/docs/apps/deploy)
