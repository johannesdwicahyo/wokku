---
title: Create & Link Add-ons
summary: "Enable shared add-ons on a box at creation or later; upgrade to dedicated from the box settings tab. Full CLI, API, and MCP reference."
eyebrow: database
last_updated: 2026-05-31
---

# Create & Link Add-ons

Wokku add-ons work at the **box** level, not as standalone resources. You pick which shared engines to enable per box at creation, and you can add or remove them later from the box settings.

## Enable shared add-ons at box creation

:::tabs
::web-ui
Go to **Boxes → New Box**. Under **Add-ons**, check the engines you want. Free plan boxes only show Postgres and Redis; paid plans show all five.

::cli
```bash
# Enable Postgres and Redis when creating the box
wokku apps:create my-app --shared postgres,redis

# Enable all five (Solo+ only)
wokku apps:create my-app --shared postgres,redis,memcached,rabbitmq,meilisearch
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-app",
    "server_id": "SERVER_ID",
    "shared_addons": ["postgres", "redis"]
  }'
```

::mcp
Ask Claude: *"Create a box called my-app with Postgres and Redis shared add-ons"*

::mobile
Tap **Boxes → +** → name the box → toggle the engines you want → **Create**.
:::

## Enable a shared add-on later

:::tabs
::web-ui
Go to the box → **Settings → Add-ons** → toggle the engine on.

::cli
```bash
wokku addons:shared:enable my-app postgres
wokku addons:shared:enable my-app redis
wokku addons:shared:enable my-app memcached
wokku addons:shared:enable my-app rabbitmq
wokku addons:shared:enable my-app meilisearch
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/APP_ID/addons/shared \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"engine": "postgres"}'
```

::mcp
```
Tool: wokku_enable_shared_addon
Arguments: { "app_id": "APP_ID", "engine": "postgres" }
```

::mobile
Tap box → **Settings → Add-ons** → toggle the engine on.
:::

## Disable a shared add-on

Disabling removes the tenant and injects `null` into the env var. Your data is kept for 24 hours; re-enabling within that window restores it.

:::tabs
::web-ui
Go to box → **Settings → Add-ons** → toggle the engine off → confirm.

::cli
```bash
wokku addons:shared:disable my-app postgres
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/APP_ID/addons/shared/postgres \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
```
Tool: wokku_disable_shared_addon
Arguments: { "app_id": "APP_ID", "engine": "postgres" }
```

::mobile
Tap box → **Settings → Add-ons** → toggle the engine off.
:::

## Upgrade a shared add-on to dedicated

Upgrading provisions a single-tenant container, migrates data (for Postgres and Redis), flips the connection URL, and restarts the box. Uses one slot from your plan's dedicated quota. See [Dedicated upgrade](/docs/databases/dedicated-upgrade) for the full flow.

:::tabs
::web-ui
Go to box → **Settings → Add-ons** → click **Upgrade to dedicated** next to the engine.

::cli
```bash
# Upgrade shared Postgres to dedicated
wokku addons:dedicated:upgrade my-app postgres

# Upgrade shared Redis to dedicated
wokku addons:dedicated:upgrade my-app redis

# Add MySQL or MongoDB (fresh-create; no shared equivalent)
wokku addons:dedicated:upgrade my-app mysql
wokku addons:dedicated:upgrade my-app mongodb
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

::mobile
Tap box → **Settings → Add-ons** → **Upgrade to dedicated** → confirm.
:::

## Connection URL env vars

When an add-on is enabled, Wokku injects the connection URL into the box's environment. The same var name is used whether the engine is shared or dedicated.

| Engine | Env var |
|---|---|
| PostgreSQL | `DATABASE_URL` |
| MySQL | `DATABASE_URL` |
| MongoDB | `MONGO_URL` |
| Redis | `REDIS_URL` |
| Memcached | `MEMCACHED_URL` |
| RabbitMQ | `RABBITMQ_URL` |
| Meilisearch | `MEILISEARCH_URL` |

## See also

- [Supported engines](/docs/databases/engines) — engine types, shared vs dedicated
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — the full upgrade flow, quotas, and rollback behavior
- [Plan Bundles](/docs/billing/plan-bundles) — which engines are available on each plan
