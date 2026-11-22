---
title: Frameworks
summary: What each framework needs to run on Wokku — start command, port, settings and migrations.
last_updated: 2026-11-07
---

Every framework deploys the same way (`git push`); these pages cover only what differs. New to Wokku? Start with the [Quickstart](/docs/getting-started/first-deploy).

## Pick your framework

| Framework | Guide | One-click starter |
|---|---|---|
| Astro | [Astro](/docs/frameworks/astro) | `astro` |
| Django | [Django](/docs/frameworks/django) | `django` |
| FastAPI | [FastAPI](/docs/frameworks/fastapi) | `fastapi` |
| Flask | [Flask](/docs/frameworks/flask) | `flask` |
| Go | [Go](/docs/frameworks/go) | `go` |
| Laravel | [Laravel](/docs/frameworks/laravel) | `laravel` |
| Next.js | [Next.js](/docs/frameworks/nextjs) | `nextjs` |
| Node.js / Express | [Node.js](/docs/frameworks/nodejs) | `express` |
| Nuxt | [Nuxt](/docs/frameworks/nuxt) | — |
| Phoenix | [Phoenix](/docs/frameworks/phoenix) | `phoenix` |
| Ruby on Rails | [Rails](/docs/frameworks/rails) | `rails`, `rails-api`, `rails-sidekiq`, `rails-tailwind` |
| Static sites | [Static Site](/docs/frameworks/static) | — |

A starter is a working repo you deploy in one click from [Templates](/docs/templates/browse), or with `wokku deploy <starter> --name my-app`.

## How Wokku builds your app

1. If your repo has a `Dockerfile`, Wokku builds it.
2. Otherwise **Nixpacks** detects the language from `package.json`, `requirements.txt`, `Gemfile`, `composer.json`, `go.mod`, `mix.exs` and so on, and builds an image.

The `web:` line of a `Procfile` becomes the start command. Every other line becomes a process type you can [scale](/docs/scaling/dynos) (for example `worker:`).

## Rules every app follows

- **Listen on `$PORT`, on `0.0.0.0`.** Wokku sets `PORT` and sends traffic only there. A fixed port, or a Dockerfile `EXPOSE`, is ignored.
- **There is no release phase.** A `release:` line does not run before deploys. Run migrations after each deploy with `wokku run`:

  ```bash
  wokku run my-app -- bin/rails db:migrate
  ```

- **Keep Procfile commands simple.** A command that contains `'`, `|`, `;` or `&` runs without a shell. Put compound commands (`a && b`) in a script and call the script. To set an env var inline, write `env HOST=0.0.0.0 node server.js`, not `HOST=0.0.0.0 node server.js`.
- **The disk is temporary.** Files written at runtime disappear on the next deploy or restart. Keep uploads in [object storage](/docs/databases/object-storage) and data in a [database](/docs/databases/create-link).
- **Config vars apply at runtime, not at build time.** Values a framework inlines during the build (`NEXT_PUBLIC_*`, `PUBLIC_*`) must be in your repo, for example in a committed `.env.production`.

## The deploy snippet

Each guide ends with the same three commands:

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

The app is live at `https://my-app.wokku.app`. For the dashboard flow, GitHub auto-deploy and SSH keys, see [Create & Deploy](/docs/apps/deploy).
