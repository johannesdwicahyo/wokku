---
shared_dbs: true
title: Add & Link a Database
summary: Add a free shared database to your app, upgrade it to dedicated, or share one database between apps.
last_updated: 2026-11-07
---

Add Postgres, MariaDB or Redis to `my-app` in one step. Wokku links it and sets the connection URL, so your app can use it on the next restart.

## Add a shared (free) database

:::tabs
::web-ui
Open the app → **Runtime → Scaling** → **Add-ons** → **+ Add**. Pick the engine, choose **Shared**, and confirm.

::cli
```bash
wokku addons:shared:enable my-app postgres   # or mariadb, redis
```

Or add them when you create the app:

```bash
wokku apps:create my-app --shared postgres,redis
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/addons/shared \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"engine": "postgres"}'
```

::mcp
Ask Claude: *"Add a free shared Postgres to my-app"* (tool `wokku_enable_shared_addon`).
:::

Provisioning takes a few seconds. Then check the URL is set:

```bash
wokku config my-app
```

Look for `DATABASE_URL` (Postgres, MariaDB) or `REDIS_URL` (Redis). The full list is in [Supported Engines](/docs/databases/engines#environment-variables).

## Add a dedicated database

A dedicated database runs in its own container, gets nightly backups and is billed per resource. In the dashboard, choose **Dedicated** instead of **Shared** in the **+ Add** panel, then pick a size preset or set the sliders.

MySQL and MongoDB are dedicated only and start empty:

```bash
wokku addons:dedicated:upgrade my-app mysql    # or mongodb
```

## Upgrade to dedicated

Moves an existing shared Postgres, MariaDB or Redis to its own container. Wokku copies your data, points the app's URL at the new database and restarts the app.

:::tabs
::web-ui
Open the app → **Settings**. Under **Add-ons**, click **Upgrade to dedicated** on the shared Postgres or Redis card. For MariaDB, use the CLI or API.

::cli
```bash
wokku addons:dedicated:upgrade my-app postgres   # or mariadb, redis
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/addons/dedicated \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"engine": "postgres"}'
```

::mcp
Ask Claude: *"Upgrade my-app's Postgres to dedicated"* (tool `wokku_upgrade_dedicated_addon`).
:::

### Resize a dedicated database

Open **Databases** in the sidebar → your database → **Settings**, or:

```bash
wokku databases:resize my-app-postgres-dedicated --cpu 0.5 --memory 1024 --disk 20
```

Pass all three flags. Disk can only grow. Run `wokku databases` to see your database names.

## Share one database between apps

Link an existing database to another app:

```bash
wokku databases:link my-db other-app --alias DATABASE
```

The app gets `<ALIAS>_URL`, here `DATABASE_URL`. Without `--alias` it's named after the engine, for example `POSTGRES_URL`. Unlink with `wokku databases:unlink my-db other-app`.

## Remove a database

:::callout warning
Removing an add-on deletes its data. Wokku takes a final snapshot first, but don't rely on it as your only copy.
:::

:::tabs
::web-ui
Open the app → **Runtime → Scaling** → **Add-ons**, and click **Remove** on the add-on.

::cli
```bash
wokku addons:shared:disable my-app postgres   # shared
wokku addons my-app                           # find a dedicated add-on's ID
wokku addons:remove my-app ADDON_ID           # dedicated
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/addons/shared/postgres \
  -H "Authorization: Bearer $TOKEN"
```
:::

## Run migrations

Wokku doesn't run migrations for you. After a deploy, run them as a one-off command:

```bash
wokku run my-app -- bin/rails db:migrate
```

## Troubleshooting

- **`DATABASE_URL` is missing:** the add-on is still provisioning, or the app already had its own `DATABASE_URL`. Check `wokku addons my-app` and `wokku config my-app`.
- **Shared database is full:** upgrade to dedicated (above).
- **A database is stuck in error:** `wokku databases:retry DB`.

## Next

- [Backups & restore](/docs/databases/backups)
- [Environment variables](/docs/apps/config)
