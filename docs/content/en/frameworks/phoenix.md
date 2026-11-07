---
title: Phoenix
summary: Run a Phoenix (Elixir) app on Wokku as a Mix release built from a Dockerfile.
last_updated: 2026-11-07
---

Generate a release Dockerfile, set your secrets, push, then run migrations. Want a working repo first? Deploy the `phoenix` starter from [Templates](/docs/templates/browse).

## Build with a Dockerfile

Phoenix generates a production Dockerfile, a release, and `bin/server` / `bin/migrate` scripts:

```bash
mix phx.gen.release --docker
```

Commit the generated files. Wokku builds the `Dockerfile` and runs its `CMD` (`/app/bin/server`). You don't need a Procfile.

## Runtime config

The generated `config/runtime.exs` already reads `PORT`, `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST`. `bin/server` sets `PHX_SERVER=true`, so the endpoint starts.

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  PHX_HOST=my-app.wokku.app
```

The Postgres add-on sets `DATABASE_URL`. See [Create & Link a Database](/docs/databases/create-link).

## Deploy and migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- /app/bin/migrate
```

Run the migrate command after every deploy that adds migrations. Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Custom domain

After you add a [custom domain](/docs/domains-ssl/custom-domains), set `PHX_HOST` to it and restart: `wokku ps:restart my-app`.

## Troubleshooting

- **App boots but never responds** — check `runtime.exs` binds `PORT` on all interfaces and that `PHX_SERVER=true` is set (start with `bin/server`).
- **`SECRET_KEY_BASE` missing** — generate one with `mix phx.gen.secret` and set it.
- **WebSocket/LiveView origin errors** — `PHX_HOST` must match the hostname you're visiting.
