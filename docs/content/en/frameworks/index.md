# Deploy by Framework

Step-by-step guides to deploy your favorite framework to Wokku. Each guide
takes you from an empty project to a live URL — including the database,
environment variables, and custom domain.

Every guide assumes you have a [Wokku account](/docs/getting-started/sign-up),
a [connected server](/docs/getting-started/connect-server), and an
[SSH key registered](/docs/apps/ssh-keys) for `git push`.

## Pick your framework

**JavaScript / TypeScript**
- **[Next.js](/docs/frameworks/nextjs)** — React, server-rendered or static
- **[Nuxt](/docs/frameworks/nuxt)** — Vue, Nitro server
- **[Astro](/docs/frameworks/astro)** — static or SSR
- **[Node.js / Express](/docs/frameworks/nodejs)** — any Node HTTP server

**Python**
- **[Django](/docs/frameworks/django)** — with `migrate` + `collectstatic`
- **[Flask](/docs/frameworks/flask)** — Gunicorn
- **[FastAPI](/docs/frameworks/fastapi)** — Uvicorn workers

**Other**
- **[Laravel](/docs/frameworks/laravel)** — PHP, with `artisan migrate` on release
- **[Ruby on Rails](/docs/frameworks/rails)** — with migrations + asset precompile
- **[Go](/docs/frameworks/go)** — compiled to a single binary
- **[Phoenix](/docs/frameworks/phoenix)** — Elixir, with Ecto migrations
- **[Static Site](/docs/frameworks/static)** — HTML/CSS/JS or any build output

Don't see yours? Almost any app deploys the same way: push a repo with a
`Procfile` (or a `Dockerfile`) and Wokku builds it. See
[Deploy](/docs/apps/deploy) for the generic flow.

## How deployment works

Wokku builds your app on your server the moment you `git push`, using
[Cloud Native Buildpacks](https://buildpacks.io) for most languages (auto-detected
from `composer.json`, `package.json`, `requirements.txt`, `go.mod`, etc.) or your
own `Dockerfile` if you provide one. No build config required for the common case.

:::callout note
Prefer not to wire anything by hand? The one-click
[template gallery](/docs/templates/browse) deploys 130+ apps, and the framework
**starters** give you a repo that's already Wokku-ready — clone, push, done.
:::
