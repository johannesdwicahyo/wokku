# Deploy Laravel

Deploy a Laravel app to Wokku with Postgres, run migrations on every release,
and go live on HTTPS — in a few minutes.

## Prerequisites

- A [Wokku account](/docs/getting-started/sign-up) and a [connected server](/docs/getting-started/connect-server)
- An [SSH key registered](/docs/apps/ssh-keys) under **Profile → SSH Keys** (for `git push`)
- A Laravel app locally (`composer create-project laravel/laravel my-app` if you're starting fresh)

## 1. Create the app

:::tabs
::web-ui
1. Go to **Apps → New App**
2. Choose your server and name it (e.g. `my-laravel-app`)
3. Pick a box size and click **Create**

::cli
```bash
wokku apps:create my-laravel-app --server my-server
```
:::

## 2. Prepare your Laravel app

Add a `Procfile` to your project root so Wokku knows how to serve the app and
run migrations on each deploy:

```procfile
web: vendor/bin/heroku-php-apache2 public/
release: php artisan migrate --force
```

The buildpack auto-detects Laravel from `composer.json` and installs PHP +
Composer dependencies. The `release` process runs **after a successful build,
before traffic shifts** — so migrations apply with zero downtime.

## 3. Set environment variables

Laravel needs at least an app key and production env. Generate a key locally
with `php artisan key:generate --show`, then:

:::tabs
::web-ui
Open your app → **Config** and add:

| Key | Value |
|---|---|
| `APP_KEY` | `base64:...` (from `key:generate --show`) |
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |

::cli
```bash
wokku config:set my-laravel-app \
  APP_KEY="base64:..." APP_ENV=production APP_DEBUG=false
```
:::

See [Environment Variables](/docs/apps/config) for the full reference.

## 4. Add a database

Provision a Postgres database and link it — Wokku injects a `DATABASE_URL`
automatically. Point Laravel at it by setting `DB_CONNECTION=pgsql` (Laravel
reads `DATABASE_URL` natively in recent versions).

:::tabs
::web-ui
App → **Resources → Add-ons**, choose **Postgres**, and link it to the app.

::cli
```bash
wokku addons:create postgres my-laravel-app
wokku config:set my-laravel-app DB_CONNECTION=pgsql
```
:::

More detail in [Create & Link a Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
Copy the git remote from your app's overview page, then:

```bash
git remote add wokku git@git.wokku.cloud:my-laravel-app
git push wokku main
```

::github
Connect your repo under **Apps → Connect GitHub** and every push to your
deploy branch ships automatically. See [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-laravel-app
git push wokku main
```
:::

Watch the build stream in your logs. When it finishes, your app is live at
`https://my-laravel-app.wokku.app`.

## 6. Add a custom domain

Point your own domain and Wokku provisions SSL automatically — see
[Custom Domains](/docs/domains-ssl/custom-domains).

## Troubleshooting

- **500 on first load** — usually a missing `APP_KEY`. Set it (step 3) and redeploy.
- **Migrations didn't run** — confirm the `release:` line is in your `Procfile` and check the deploy logs.
- **Storage / sessions** — use the database or cache driver for sessions in production; local disk is ephemeral.

## Next steps

- [Background workers & queues](/docs/scaling/bundled-processes)
- [Logs](/docs/apps/logs) · [Production Readiness](/docs/apps/best-practices)
