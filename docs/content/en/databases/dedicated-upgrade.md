---
title: Dedicated Engine Upgrade
summary: "When and how to upgrade a box from a shared engine to a single-tenant dedicated container. Covers use cases, quota, sizing, the migration flow, and rollback."
eyebrow: database
last_updated: 2026-05-31
---

# Dedicated Engine Upgrade

Every Wokku box starts with free shared engines — multi-tenant containers that are instant, zero-config, and good enough for most apps. When shared is no longer enough, you can upgrade to a **dedicated** engine: a single-tenant container sized to match your box.

## When to upgrade

Upgrade to a dedicated engine when:

- **You've hit the shared cap** — the `SharedDatabaseQuotaJob` warns at 80% usage; at 100% writes are blocked with a 24-hour grace window.
- **You need more resources** — dedicated containers have higher connection limits, no noisy-neighbor I/O, and full admin access (superuser for Postgres, admin vhost for RabbitMQ, etc.).
- **You need a shared DB across multiple apps** — dedicated Postgres or MySQL can be linked to several boxes; shared tenants are box-scoped.
- **You need an engine with no shared tier** — MySQL and MongoDB are dedicated-only; there is no shared MySQL or MongoDB.

## Quota

Each paid workspace gets:

- **3 dedicated DB slots** — shared across Postgres, MySQL, and MongoDB (all three draw from the same pool)
- **3 dedicated Redis slots** — separate pool

Free plan workspaces have 0 dedicated slots; upgrade your plan to unlock them.

| Plan | Dedicated DB slots | Dedicated Redis slots |
|---|---|---|
| Free | 0 | 0 |
| Solo | 3 | 3 |
| Pro | 3 | 3 |
| Team | 3 | 3 |

> **Example**: A Pro workspace with two dedicated Postgres DBs and one dedicated MySQL has used all 3 DB slots. It still has 3 Redis slots available.

## Sizing

Dedicated engine size follows the **box's size** — there is no separate sizing picker. A small box gets a small dedicated engine; a large box gets a large one. If you need a bigger database, resize the box first.

| Box size | Dedicated engine size |
|---|---|
| Sleeping | — (not available) |
| Small | Small |
| Medium | Medium |
| Large | Large |
| X-Large | X-Large |

## How to upgrade

You can upgrade at box creation or any time after from box settings.

### At box creation

:::tabs
::web-ui
In the **New Box** form, expand **Add-ons** → select the engine → toggle **Dedicated**. The dedicated option is greyed out if you have no quota remaining.

::cli
```bash
# Upgrade Postgres to dedicated at creation
wokku apps:create my-app --dedicated postgres

# Or enable shared first, then upgrade later
wokku apps:create my-app --shared postgres
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-app",
    "server_id": "SERVER_ID",
    "dedicated_addons": ["postgres"]
  }'
```

::mcp
```
Tool: wokku_create_app
Arguments: { "name": "my-app", "server_id": "SERVER_ID", "dedicated_addons": ["postgres"] }
```
:::

### From box settings (after creation)

:::tabs
::web-ui
Go to box → **Settings → Add-ons** → click **Upgrade to dedicated** next to the engine → confirm.

::cli
```bash
wokku addons:dedicated:upgrade my-app postgres
wokku addons:dedicated:upgrade my-app redis
wokku addons:dedicated:upgrade my-app mysql    # fresh-create, no shared tier
wokku addons:dedicated:upgrade my-app mongodb  # fresh-create, no shared tier
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/APP_ID/addons/dedicated \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"engine": "postgres"}'
```

::mcp
```
Tool: wokku_upgrade_dedicated_addon
Arguments: { "app_id": "APP_ID", "engine": "postgres" }
```
:::

## What happens during an upgrade

For **Postgres** and **Redis** (which have a shared tier):

1. **Provision** — a new dedicated container is created and healthy-checked.
2. **Migrate data** — a consistent snapshot is taken from the shared tenant and restored into the dedicated container. For Postgres this uses `pg_dump | pg_restore`; for Redis a `BGSAVE` + `RESTORE`.
3. **Flip URL** — `DATABASE_URL` (or `REDIS_URL`) is atomically updated to point at the dedicated container.
4. **Restart** — the box is restarted to pick up the new URL.
5. **Grace period** — the shared tenant is kept for 24 hours in case you need to roll back. After 24 hours it is cleaned up automatically.

For **MySQL** and **MongoDB** (no shared tier):

1. **Provision** — a dedicated container is created and healthy-checked.
2. **Inject URL** — `DATABASE_URL` (MySQL) or `MONGO_URL` (MongoDB) is set on the box.
3. **Restart** — the box restarts. Your app handles schema creation on first boot.

The entire flow typically completes in under 2 minutes for small datasets. For large Postgres databases (> 1 GB) allow 5–10 minutes; the box will continue to serve traffic during the migration (read traffic hits the old shared tenant; write traffic is briefly paused during the URL flip).

## Rollback behavior

If provisioning or data migration fails, Wokku automatically rolls back:

- The shared tenant's URL is left intact; the box keeps running.
- The partially-created dedicated container is destroyed.
- No slot quota is consumed.

If the upgrade succeeds but you want to revert within the 24-hour grace window, contact support — the shared tenant is still available and a manual rollback is possible. After 24 hours the shared tenant is permanently cleaned up.

## Four supported engines

| Engine | URL env var | Data migrated from shared? |
|---|---|---|
| **PostgreSQL** | `DATABASE_URL` | Yes — `pg_dump / pg_restore` |
| **MySQL** | `DATABASE_URL` | No — fresh-create |
| **MongoDB** | `MONGO_URL` | No — fresh-create |
| **Redis** | `REDIS_URL` | Yes — `BGSAVE / RESTORE` |

## See also

- [Supported engines](/docs/databases/engines) — engine overview and connection URL reference
- [Create & Link add-ons](/docs/databases/create-link) — enabling shared add-ons, full CLI/API/MCP reference
- [Plan Bundles](/docs/billing/plan-bundles) — plan quotas and what each plan includes
