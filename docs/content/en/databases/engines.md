---
title: Supported Engines
summary: "Five free shared engines (Postgres, Redis, Memcached, RabbitMQ, Meilisearch) available on every box, plus four dedicated engines (Postgres, MySQL, MongoDB, Redis) as paid upgrades. Connection URL injected automatically."
eyebrow: database
last_updated: 2026-05-31
---

# Supported Engines

Wokku provides two categories of engines: **shared** (free, multi-tenant, enabled per box) and **dedicated** (paid upgrade, single-tenant container). Workspace-level object storage (MinIO) is separate from both.

## Shared engines

Five engines run on shared host containers. You pick which ones to enable when you create a box — or add/remove them later from the box's **Settings → Add-ons** tab. No separate provisioning, no waiting; the tenant is created instantly.

| Engine | Type | URL env var |
|---|---|---|
| **PostgreSQL** | Relational | `DATABASE_URL` |
| **Redis** | Key-value / Cache | `REDIS_URL` |
| **Memcached** | Cache | `MEMCACHED_URL` |
| **RabbitMQ** | Message Queue | `RABBITMQ_URL` |
| **Meilisearch** | Full-text Search | `MEILISEARCH_URL` |

> **Free plan restriction** — Free plan boxes only see Postgres and Redis in the addon picker. Memcached, RabbitMQ, and Meilisearch are available from Solo plan upward.

### How shared tenancy works

Each shared engine hosts one container per server. When you enable an engine on a box, Wokku provisions a per-box role + namespace (a role + database for Postgres, a key prefix for Redis and Memcached, a virtual host for RabbitMQ, an index namespace for Meilisearch). Tenants are isolated; one box cannot read another's data.

The `DATABASE_URL` (and sibling vars) are injected as app environment variables and updated automatically if the shared tenant is ever migrated. Your app code sees the same env var name whether the addon is shared or dedicated.

## Dedicated engines

Four engines can be provisioned as single-tenant dedicated containers. Dedicated engines are a paid upgrade — they consume one slot from your plan's quota (3 DB slots + 3 Redis slots per paid workspace). See [Dedicated upgrade](/docs/databases/dedicated-upgrade) for the full flow.

| Engine | Type | URL env var | Notes |
|---|---|---|---|
| **PostgreSQL** | Relational | `DATABASE_URL` | Migrates data from shared Pg on upgrade |
| **MySQL** | Relational | `DATABASE_URL` | Fresh-create only (no shared MySQL) |
| **MongoDB** | Document | `MONGO_URL` | Fresh-create only (no shared MongoDB) |
| **Redis** | Key-value / Cache | `REDIS_URL` | Migrates data from shared Redis on upgrade |

> All three DB engines (Postgres, MySQL, MongoDB) share **one pool of 3 dedicated DB slots** per workspace. Redis has its own pool of 3 slots. Size follows the box: a medium box gets a medium-sized dedicated engine.

### Connection limits (dedicated Postgres)

| Plan | Max connections |
|---|---|
| Solo | 20 |
| Pro | 80 |
| Team | 160 |

Need more headroom? Put [PgBouncer](https://www.pgbouncer.org/) in front of Postgres — it multiplexes connections without changing your `DATABASE_URL`.

## Workspace MinIO (object storage)

MinIO is not a per-box addon — it is workspace-level object storage shared across all your boxes. Every paid plan includes a MinIO bucket; the size depends on your plan (Solo 2 GB / Pro 10 GB / Team 20 GB). Access credentials are available from **Workspace → Storage**.

Use cases: user uploads (avatars, attachments), generated PDFs, image and video assets, deploy artefacts, log archives.

> MinIO support is in early access — bucket creation and the S3-compatible API are stable, but the dashboard object browser ships in a later release.

## See also

- [Create & Link add-ons](/docs/databases/create-link) — enable shared add-ons, CLI + API + MCP reference
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — when and how to upgrade to a dedicated engine
- [Plan Bundles](/docs/billing/plan-bundles) — what each plan includes
