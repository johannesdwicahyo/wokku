---
title: Ruby on Rails
summary: Run a Rails app on Wokku with Puma, Postgres and migrations via wokku run.
last_updated: 2026-11-07
---

Add a Puma start command, set your master key, push, then run migrations. Want a working repo first? Deploy the `rails`, `rails-api`, `rails-sidekiq` or `rails-tailwind` starter from [Templates](/docs/templates/browse).

## Start command

```procfile
web: bin/rails server -b 0.0.0.0 -p $PORT
```

Nixpacks detects Rails from your `Gemfile` and installs your gems.

:::callout warning
Rails 7.1+ apps ship a `Dockerfile`, and Wokku builds it when present. On Rails 8 its default command runs Thruster on port 80, which doesn't receive traffic. Keep the Procfile line above (it replaces the image's command), or delete the Dockerfile to build with Nixpacks.
:::

## Config and database

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  RAILS_ENV=production RAILS_LOG_TO_STDOUT=true RAILS_SERVE_STATIC_FILES=true
```

Never commit `config/master.key`. The Postgres add-on sets `DATABASE_URL`, which Rails reads in production. See [Create & Link a Database](/docs/databases/create-link).

## Deploy and migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- bin/rails db:migrate
```

Run the migrate command after every deploy that adds migrations. Live at `https://my-app.wokku.app`. First deploy? See the [Quickstart](/docs/getting-started/first-deploy).

## Background jobs

Add `worker: bundle exec sidekiq` (or `bin/jobs` for Solid Queue) to the Procfile and scale it. Sidekiq also needs Redis (`wokku addons:shared:enable my-app redis`, which sets `REDIS_URL`). See [Background Workers](/docs/guides/background-workers).

## Troubleshooting

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — `RAILS_MASTER_KEY` is wrong or missing.
- **Assets 404** — set `RAILS_SERVE_STATIC_FILES=true` and check the build [logs](/docs/monitoring/logs) for `assets:precompile`. If it didn't run, build with a [Dockerfile](/docs/guides/dockerfile).
- **Blocked host errors** — add your domain to `config.hosts`, or leave `config.hosts` empty in production.
