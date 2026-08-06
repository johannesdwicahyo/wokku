---
title: Create & Link Add-on
summary: "Enable shared add-on di box saat creation atau belakangan; upgrade ke dedicated dari tab settings box. Referensi CLI, API, dan MCP lengkap."
eyebrow: database
last_updated: 2026-05-31
---

# Create & Link Add-on

Add-on Wokku bekerja di level **box**, bukan sebagai resource standalone. Kamu pilih shared engine mana yang mau di-enable per box saat creation, dan bisa tambah atau hapus belakangan dari settings box.

## Enable shared add-on saat bikin box

:::tabs
::web-ui
Pergi ke **Boxes → New Box**. Di bagian **Add-ons**, centang engine yang kamu mau. Box Free plan cuma tampilkan Postgres dan Redis; paid plan tampilkan semua lima.

::cli
```bash
# Enable Postgres dan Redis saat bikin box
wokku apps:create my-app --shared postgres,redis

# Enable semua lima (Solo+ only)
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
Tanya Claude: *"Buat box namanya my-app dengan shared add-on Postgres dan Redis"*

::mobile
Tap **Boxes → +** → namai box → toggle engine yang kamu mau → **Create**.
:::

## Enable shared add-on setelah box jalan

:::tabs
::web-ui
Pergi ke box → **Settings → Add-ons** → toggle engine-nya on.

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
Tap box → **Settings → Add-ons** → toggle engine-nya on.
:::

## Disable shared add-on

Disable menghapus tenant dan mengisi env var dengan `null`. Data kamu disimpan selama 24 jam; re-enable dalam window itu akan restore data.

:::tabs
::web-ui
Pergi ke box → **Settings → Add-ons** → toggle engine-nya off → konfirmasi.

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
Tap box → **Settings → Add-ons** → toggle engine-nya off.
:::

## Upgrade shared add-on ke dedicated

Upgrade provision container single-tenant, migrasi data (untuk Postgres dan Redis), flip connection URL, dan restart box. Mengonsumsi satu slot dari kuota dedicated plan kamu. Lihat [Dedicated upgrade](/docs/databases/dedicated-upgrade) untuk flow lengkapnya.

:::tabs
::web-ui
Pergi ke box → **Settings → Add-ons** → klik **Upgrade to dedicated** di sebelah engine.

::cli
```bash
# Upgrade shared Postgres ke dedicated
wokku addons:dedicated:upgrade my-app postgres

# Upgrade shared Redis ke dedicated
wokku addons:dedicated:upgrade my-app redis

# Tambah MySQL atau MongoDB (fresh-create; nggak ada shared-nya)
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
Tap box → **Settings → Add-ons** → **Upgrade to dedicated** → konfirmasi.
:::

## Env var connection URL

Saat add-on di-enable, Wokku inject connection URL ke environment box. Nama var yang sama dipakai baik engine-nya shared maupun dedicated.

| Engine | Env var |
|---|---|
| PostgreSQL | `DATABASE_URL` |
| MySQL | `DATABASE_URL` |
| MongoDB | `MONGO_URL` |
| Redis | `REDIS_URL` |
| Memcached | `MEMCACHED_URL` |
| RabbitMQ | `RABBITMQ_URL` |
| Meilisearch | `MEILISEARCH_URL` |

## Lihat juga

- [Engine yang didukung](/docs/databases/engines) — tipe engine, shared vs dedicated
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — flow upgrade lengkap, kuota, dan rollback
- [Plan Bundle](/docs/billing/plan-bundles) — engine mana yang tersedia di tiap plan
