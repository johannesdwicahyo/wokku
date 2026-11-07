---
title: Deploy with a Dockerfile
summary: Commit a Dockerfile and Wokku builds your app from it instead of auto-detecting.
last_updated: 2026-11-07
---

You'll add a `Dockerfile` at the root of your repo and push. Wokku builds from it automatically. Without one, Wokku auto-detects your language with Nixpacks.

## 1. Add a Dockerfile

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "server.js"]
```

`server.js` should listen on `process.env.PORT`.

:::callout warning
**Listen on `$PORT`.** Wokku sets `PORT` and sends traffic to it. `EXPOSE` doesn't change the port, and a hardcoded port is the most common reason a Docker deploy builds but serves nothing.
:::

## 2. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Follow the build on the app's **Deploy** tab.

## 3. More process types

A `Procfile` still works. Each line runs from the built image:

```procfile
web: node server.js
worker: node worker.js
```

Scale extra process types with `wokku ps:scale my-app worker=1`. See [Background Workers](/docs/guides/background-workers).

## Migrations

There's no release phase. Run migrations after the deploy:

```bash
wokku run my-app -- node migrate.js
```

Don't put a `release:` line in your Procfile. It becomes a process type, not a one-time step.

## Tips

- Slim bases and multi-stage builds make smaller images that deploy faster.
- Copy lockfiles and install dependencies before copying source, so that layer is cached.
- Don't bake secrets into the image. Set them as [environment variables](/docs/apps/config).

## Troubleshooting

- **Builds but no response**: the app isn't listening on `$PORT`.
- **Dockerfile ignored**: it must be named `Dockerfile` and sit at the repo root.

## Next steps

- [Environment Variables](/docs/apps/config)
- [Logs](/docs/monitoring/logs)
