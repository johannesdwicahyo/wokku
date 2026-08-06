---
title: Plan Bundles
summary: "Every box ships with five free shared engines (Postgres, Redis, Memcached, RabbitMQ, Meilisearch) — you pick which to enable per box. Paid plans add dedicated DB and Redis quota. No add-on store, no per-resource invoices."
eyebrow: billing
last_updated: 2026-05-31
---

# Plan Bundles

Every Wokku box is **batteries-included**: five shared engines are available at no extra cost, and you pick which ones to attach at box creation. There is no add-on store and no separate addon invoices. Paid plans additionally include a quota of dedicated engine slots for workloads that have outgrown shared tenancy.

## Plan matrix

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| **Price** | $0 | $5 / Rp 75k/mo | $15 / Rp 225k/mo | $50 / Rp 750k/mo + $3 / Rp 45k per extra seat |
| **Boxes** | 3 sleeping | 3 sleeping + 3 small | 3 sleeping + 3 medium | 3 sleeping + 3 large |
| **Extra boxes** | — | — | — | Large ($10/box) or X-Large ($20/box) |
| **Shared add-ons available** | Postgres + Redis only | All 5 engines | All 5 engines | All 5 engines |
| **Dedicated DB quota** | 0 slots | 3 slots (small size) | 3 slots (medium size) | 3 slots (large size) |
| **Dedicated Redis quota** | 0 slots | 3 slots (small size) | 3 slots (medium size) | 3 slots (large size) |
| **Workspace MinIO** | — | 2 GB | 10 GB | 20 GB |

> "3 DB slots" covers **all three DB engines combined** (Postgres, MySQL, MongoDB). A Pro workspace with 2 dedicated Postgres DBs + 1 dedicated MySQL has used all 3 DB slots.

## Shared add-ons: pick per box

The five shared engines are:

| Engine | Free plan | Solo+ |
|---|---|---|
| PostgreSQL | ✓ | ✓ |
| Redis | ✓ | ✓ |
| Memcached | — | ✓ |
| RabbitMQ | — | ✓ |
| Meilisearch | — | ✓ |

Each engine you enable on a box gets its own isolated tenant — a dedicated role + database for Postgres, a key prefix for Redis and Memcached, a virtual host for RabbitMQ, an index namespace for Meilisearch. Tenants are isolated; one box cannot read another's data.

You can enable or disable engines after creation from **box → Settings → Add-ons**. Disabled engines keep data for 24 hours before the tenant is cleaned up.

## Dedicated engine slots

When a shared tenant is no longer enough — you've hit the size cap, need full admin access, or want to share a DB across multiple boxes — you can upgrade to a dedicated single-tenant container. Upgrade consumes one slot from your quota.

All three DB engines (Postgres, MySQL, MongoDB) share the same 3-slot pool. Redis has its own 3-slot pool.

**Size follows the box**: a medium box gets a medium dedicated engine. To get a bigger engine, resize the box first.

See [Dedicated upgrade](/docs/databases/dedicated-upgrade) for the full migration flow.

## Extra boxes (Team plan only)

Only Team plan workspaces can buy extra boxes beyond the included 3 sleeping + 3 large:

- **Large** — $10 / Rp 150k per box per month
- **X-Large** — $20 / Rp 300k per box per month

Free, Solo, and Pro pay only the flat plan price and cannot add extra boxes.

## Workspace MinIO

MinIO is workspace-level object storage — not a per-box add-on. Every paid plan includes a shared bucket; the size scales with plan. Credentials are in **Workspace → Storage**.

> MinIO is in early access. Bucket creation and the S3-compatible API are stable; the dashboard object browser ships in a later release.

## Why bundle them?

The per-add-on billing model used by Heroku's marketplace or Vercel's integrations works, but it creates friction:

- You end up with 5+ line items on every invoice.
- Cost compounds: a small DB + small Redis + small search engine can be 3× your compute cost.
- You spend time picking tiers across multiple providers, and they don't scale together.

Wokku's model: compute + cache + DB + search + queue, all included in the plan price and sized as a coherent set. The Pro plan's medium boxes are matched to medium dedicated engines — you don't hit one cap before the other.

## Exceeding a shared cap

If a shared engine tenant hits its size limit:

- **Postgres** — writes are blocked with a 24-hour grace period; old rows stay readable. The `SharedDatabaseQuotaJob` warns at 80%.
- **Redis** — LRU eviction kicks in (oldest keys dropped first), or `NOEVICTION` returns errors, depending on your `maxmemory-policy`.
- **Memcached** — entries are evicted normally (Memcached is always LRU).
- **RabbitMQ** — new messages are rejected when the vhost queue depth limit is reached.
- **Meilisearch** — indexing returns errors when the index size limit is reached; existing indexed data remains searchable.

The right fix is usually upgrading to a dedicated engine (frees the shared slot) or moving to a higher plan (bigger dedicated size).

## Self-hosted

Community Edition has no bundle system — you manage Postgres, Redis, and other engines directly via your Dokku setup. No caps, no quotas.

## See also

- [Plans & Pricing](/docs/billing/plans) — what each plan costs and how seats work
- [Supported engines](/docs/databases/engines) — all 5 shared + 4 dedicated engines
- [Create & Link add-ons](/docs/databases/create-link) — enable shared add-ons, CLI/API/MCP reference
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — upgrade flow, quota, sizing, rollback
- [Usage](/docs/billing/usage) — live utilization tiles per workspace
