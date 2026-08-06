# Deploy with a Dockerfile

When buildpacks aren't enough — a custom system dependency, a multi-stage build,
an exact base image — commit a `Dockerfile` and Wokku builds your app from it
instead.

## How it works

If a `Dockerfile` exists at the root of your repo, Wokku uses it automatically
on `git push` — no buildpack, no config. You own the whole build.

## 1. Add a Dockerfile

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

:::callout warn
**Listen on the port you `EXPOSE`, and read `$PORT` if your app supports it.**
Wokku maps inbound traffic to the exposed port. Hardcoding a different port is
the most common reason a Docker deploy builds but serves nothing.
:::

## 2. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Wokku detects the `Dockerfile`, builds the image on your server, and runs it.
Watch the build in your [logs](/docs/apps/logs).

## 3. Multiple processes

A `Procfile` still works with Dockerfile deploys — declare extra process types
and they run from the built image:

```procfile
web: node server.js
worker: node worker.js
```

## 4. Run migrations on release

```procfile
release: node migrate.js
web: node server.js
```

The `release` process runs after a successful build, before traffic shifts.

## Tips

- **Smaller images deploy faster** — use slim/alpine bases and multi-stage builds.
- **Cache dependencies** — copy lockfiles and install before copying source (as above).
- **Don't bake secrets** — set them as [config vars](/docs/apps/config), read at runtime.

## Troubleshooting

- **Builds but no response** — `EXPOSE` and listen on the same port; prefer `$PORT`.
- **Build is slow every time** — reorder layers so dependency install is cached.
- **Wokku used a buildpack instead** — make sure the `Dockerfile` is at the repo root.

## Next steps

- [Environment Variables](/docs/apps/config) · [Logs](/docs/apps/logs)
