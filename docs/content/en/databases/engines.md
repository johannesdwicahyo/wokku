---
shared_dbs: true
cloud_prices: true
title: Supported Engines
summary: Which databases and caches Wokku runs, free shared or paid dedicated, and the env vars your app gets.
last_updated: 2026-11-07
---

Pick an engine and a mode. Wokku creates it, links it to your app and sets the connection URL as an environment variable.

## Engines

| Engine | Shared (free) | Dedicated (paid) |
|---|---|---|
| PostgreSQL | ✓ | ✓ |
| MariaDB | ✓ | ✓ |
| Redis | ✓ | ✓ |
| MySQL | — | ✓ |
| MongoDB | — | ✓ |

## Shared vs dedicated

| | Shared | Dedicated |
|---|---|---|
| Cost | Free with every app | Billed per resource (CPU, RAM, disk), see [Pricing](/docs/billing/pricing) |
| What you get | Your own database (or Redis tenant) on a shared server | Its own container |
| Size | 100 MB for Postgres/MariaDB, 10 MB for Redis | You choose: Small, Medium, Large presets or sliders |
| Automatic backups | No | Nightly, see [Backups](/docs/databases/backups) |
| Good for | Side projects, prototypes, getting started | Production data |

Start on shared. When you outgrow it, [upgrade to dedicated](/docs/databases/create-link#upgrade-to-dedicated). Your data moves with you.

:::callout note
Shared Redis is never backed up. Use it as a cache, or upgrade to a dedicated Redis if it holds data you need to keep.
:::

## Dedicated sizes

| Preset | Postgres, MySQL, MariaDB, MongoDB | Redis |
|---|---|---|
| Small | 0.25 vCPU · 512 MB RAM · 5 GB disk | 0.25 vCPU · 256 MB RAM · 1 GB disk |
| Medium | 0.5 vCPU · 1 GB RAM · 20 GB disk | 0.25 vCPU · 1 GB RAM · 2 GB disk |
| Large | 1 vCPU · 2 GB RAM · 50 GB disk | 0.5 vCPU · 2 GB RAM · 4 GB disk |

You can also set CPU, RAM and disk with sliders, and resize later. Disk can only grow.

## Environment variables

Wokku sets these on the linked app. It doesn't overwrite a `DATABASE_URL` your app already has.

| Add-on | Env vars set |
|---|---|
| Shared Postgres | `DATABASE_URL` |
| Shared MariaDB | `MARIADB_URL`, plus `DATABASE_URL` (in the `mysql2://` form Rails expects) |
| Shared Redis | `REDIS_URL` |
| Dedicated Postgres | `POSTGRES_URL`, plus `DATABASE_URL` |
| Dedicated MySQL | `MYSQL_URL` |
| Dedicated MariaDB | `MARIADB_URL` |
| Dedicated MongoDB | `MONGODB_URL` |
| Dedicated Redis | `REDIS_URL` |

Read them like any other variable: `process.env.DATABASE_URL`, `os.environ["DATABASE_URL"]`, `ENV["DATABASE_URL"]`. Most frameworks (Rails, Django with `dj-database-url`, Laravel, Prisma) read `DATABASE_URL` on their own. See your [framework guide](/docs/frameworks/index).

## Next

- [Add & link a database](/docs/databases/create-link)
- [Backups & restore](/docs/databases/backups)
