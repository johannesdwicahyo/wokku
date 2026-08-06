# Deploy Phoenix (Elixir)

Deploy a Phoenix app to Wokku with Postgres and Ecto migrations on release.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Phoenix app with `mix.exs`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-phoenix-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-phoenix-app --server my-server
```
:::

## 2. Prepare your Phoenix app

The Elixir buildpack detects `mix.exs`, fetches deps, and builds assets. Add a
`Procfile`:

```procfile
web: mix phx.server
release: mix ecto.migrate
```

In `config/runtime.exs`, read the port and database from the environment:

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  server: true
config :my_app, MyApp.Repo, url: System.get_env("DATABASE_URL")
```

## 3. Set environment variables

:::tabs
::web-ui
App → **Config**:

| Key | Value |
|---|---|
| `SECRET_KEY_BASE` | `mix phx.gen.secret` output |
| `MIX_ENV` | `prod` |
| `PHX_HOST` | `my-phoenix-app.wokku.app` |

::cli
```bash
wokku config:set my-phoenix-app \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" MIX_ENV=prod \
  PHX_HOST=my-phoenix-app.wokku.app
```
:::

## 4. Add a database

```bash
wokku addons:create postgres my-phoenix-app
```

Wokku injects `DATABASE_URL`; wire it in `runtime.exs` (above). See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-phoenix-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-phoenix-app
git push wokku main
```
:::

Live at `https://my-phoenix-app.wokku.app`.

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — update `PHX_HOST` to match, then redeploy.

## Troubleshooting

- **Endpoint not serving** — set `server: true` in `runtime.exs` and bind to `{0,0,0,0}` + `$PORT`.
- **`SECRET_KEY_BASE` missing** — generate with `mix phx.gen.secret` and set it.
- **Migrations didn't run** — confirm the `release:` line; check deploy logs.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)
