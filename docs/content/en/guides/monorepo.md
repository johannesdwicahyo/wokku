# Deploy from a Monorepo

Your app lives in a subdirectory (`apps/api`, `packages/web`) of a larger repo.
Here's how to deploy just that subtree to a Wokku app.

## Option A — push a subtree (works everywhere)

`git subtree` ships only a subdirectory as the repo root of your push. No
server config needed.

```bash
# from the repo root, push apps/api to the Wokku app's main branch
git subtree push --prefix apps/api wokku main
```

If the history makes `subtree push` slow or it rejects a non-fast-forward, split
first and force the branch:

```bash
git subtree split --prefix apps/api -b deploy-api
git push wokku deploy-api:main --force
```

Your `Procfile`, `Dockerfile`, and dependency manifest must sit at the root of
that subdirectory (`apps/api/Procfile`, etc.) — after the subtree split they
become the repo root Wokku sees.

## Option B — build from a subdirectory (GitHub auto-deploy)

When deploying via [GitHub Auto-Deploy](/docs/apps/github-autodeploy), set the
**build directory** so Wokku builds from your subfolder on each push:

:::tabs
::web-ui
App → **Settings** → set **Build directory** to `apps/api`.

::cli
```bash
wokku config:set my-api BUILD_DIR=apps/api
```
:::

Every push to the connected branch builds `apps/api` and deploys it — no subtree
gymnastics.

## Multiple apps from one repo

Create one Wokku app per deployable, each pointed at its own subdirectory:

```bash
wokku apps:create my-api --server my-server     # build dir apps/api
wokku apps:create my-web --server my-server     # build dir apps/web
```

## Troubleshooting

- **"Updates were rejected"** on subtree push — use the split + `--force` form above.
- **Buildpack detected the wrong language** — confirm the manifest (`package.json`, etc.) is at the subtree/build-dir root.
- **Shared packages not found** — a `git subtree` push only carries the subfolder; vendor shared code into the build dir or use a Dockerfile that copies what it needs.

## Next steps

- [Deploy with a Dockerfile](/docs/guides/dockerfile) · [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
