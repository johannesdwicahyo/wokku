---
title: Laravel
summary: Run a Laravel app on Wokku with Nixpacks' PHP setup (nginx + PHP-FPM) and Postgres.
last_updated: 2026-11-07
---

Set your app key and database, push, then run migrations. Want a working repo first? Deploy the `laravel` starter from [Templates](/docs/templates/browse).

## Build and start

Nixpacks detects `composer.json`, installs your Composer dependencies, and serves `public/` with nginx and PHP-FPM. **Don't add a `web:` Procfile line.** Heroku's `vendor/bin/heroku-php-apache2` doesn't exist here, and the app would crash.

Need extra PHP extensions or a custom web server? Commit a [Dockerfile](/docs/guides/dockerfile) that listens on `$PORT`.

## Config

Generate a key locally with `php artisan key:generate --show`, then:

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  APP_KEY="base64:..." APP_ENV=production APP_DEBUG=false \
  APP_URL=https://my-app.wokku.app LOG_CHANNEL=stderr DB_CONNECTION=pgsql
```

## Database

The Postgres add-on sets `DATABASE_URL`. Recent Laravel versions read `DB_URL`, so fall back to it in `config/database.php`:

```php
'pgsql' => [
    'driver' => 'pgsql',
    'url' => env('DB_URL', env('DATABASE_URL')),
    // ...
],
```

See [Create & Link a Database](/docs/databases/create-link).

## Deploy and migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- php artisan migrate --force
```

Run the migrate command after every deploy that adds migrations. Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **500 on first load** — usually a missing `APP_KEY`. Set it and restart (`wokku ps:restart my-app`).
- **Sessions, cache or uploads lost** — local disk is temporary. Use the `database` or `redis` driver for sessions, cache and queues, and [object storage](/docs/databases/object-storage) for files.
- **Queues** — add `worker: php artisan queue:work` to a Procfile and scale it. See [Background Workers](/docs/guides/background-workers).
