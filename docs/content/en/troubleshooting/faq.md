---
title: FAQ
summary: Short answers about how Wokku builds apps, what's free, backups, Heroku migration and self-hosting.
last_updated: 2026-11-07
---

## Is Wokku managed?

Yes. Wokku Cloud runs the servers for you — you push code, we build and run it. You never connect or pick a server. If you want to run Wokku yourself, see [Self-Hosting](/docs/oss/overview).

## What languages are supported?

Anything that runs in a container. If your repo has a `Dockerfile`, Wokku builds it. Otherwise it auto-detects Node.js, Python, Ruby, Go, PHP, Java and more with Nixpacks. See [Frameworks](/docs/frameworks/index) and the [one-click apps](/docs/templates/browse).

## Is there a free tier?

Yes. Free apps sleep after 30 minutes without traffic and wake on the next request (about 30 seconds). Shared Postgres, MariaDB and Redis are free too. You pay only for the CPU, RAM and dedicated databases you choose — see [Pricing](/docs/billing/pricing).

## How does billing work?

You top up a balance (in IDR) and Wokku deducts the cost of your resources daily. See [Pricing](/docs/billing/pricing) and [Invoices](/docs/billing/invoices).

## How do backups work?

Dedicated databases are backed up for you, encrypted, and you can take an on-demand backup or restore from the database's page. See [Backups](/docs/databases/backups).

## Can I migrate from Heroku?

Yes. The workflow is the same — `git push` to deploy, a `Procfile` for process types, env vars for config. One difference: there's no release phase, so run migrations with `wokku run my-app -- <command>` after deploying. See [Migrate from Heroku](/docs/migrate/heroku).

## Can I self-host Wokku?

Yes — the engine is open source (AGPL-3.0). See [Self-Hosting](/docs/oss/overview).

## How do I get support?

Email [support@wokku.cloud](mailto:support@wokku.cloud).
