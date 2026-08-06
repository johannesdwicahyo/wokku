# Deploy Ruby on Rails

Deploy a Rails app to Wokku with Postgres, migrations on release, and asset
precompilation handled automatically.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) for `git push`
- A Rails app with a `Gemfile`

## 1. Create the app

:::tabs
::web-ui
**Apps → New App** → server, name `my-rails-app`, box size, **Create**.

::cli
```bash
wokku apps:create my-rails-app --server my-server
```
:::

## 2. Prepare your Rails app

The Ruby buildpack detects Rails from your `Gemfile` and precompiles assets
automatically. Add a `Procfile`:

```procfile
web: bin/rails server -p $PORT -e $RAILS_ENV
release: bin/rails db:migrate
```

The `release` process runs migrations after a successful build, before traffic
shifts — zero-downtime deploys.

## 3. Set environment variables

:::tabs
::web-ui
App → **Config**:

| Key | Value |
|---|---|
| `RAILS_MASTER_KEY` | contents of `config/master.key` |
| `RAILS_ENV` | `production` |
| `RAILS_SERVE_STATIC_FILES` | `true` |
| `RAILS_LOG_TO_STDOUT` | `true` |

::cli
```bash
wokku config:set my-rails-app \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  RAILS_ENV=production RAILS_SERVE_STATIC_FILES=true RAILS_LOG_TO_STDOUT=true
```
:::

:::callout warn
Never commit `config/master.key`. Set it as a config var (above) — Wokku stores
it encrypted.
:::

## 4. Add a database

```bash
wokku addons:create postgres my-rails-app
```

Wokku injects `DATABASE_URL`, which Rails reads natively in production. See
[Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-rails-app
git push wokku main
```

::github
Connect under **Apps → Connect GitHub** for push-to-deploy —
see [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-rails-app
git push wokku main
```
:::

Live at `https://my-rails-app.wokku.app`.

## Background jobs

Run Sidekiq/Solid Queue as a second process — add `worker:` to your `Procfile`
and scale it. See [Bundled Processes](/docs/scaling/bundled-processes).

## Custom domain

[Custom Domains](/docs/domains-ssl/custom-domains) — SSL is automatic.

## Troubleshooting

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — wrong/missing `RAILS_MASTER_KEY`.
- **Assets 404** — set `RAILS_SERVE_STATIC_FILES=true` (or use a CDN).
- **Migrations didn't run** — confirm the `release:` line and check deploy logs.

## Next steps

- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)
