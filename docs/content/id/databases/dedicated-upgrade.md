---
title: Dedicated Engine Upgrade
summary: "Kapan dan cara upgrade box dari shared engine ke dedicated container single-tenant. Mencakup use case, kuota, sizing, flow migrasi, dan rollback."
eyebrow: database
last_updated: 2026-05-31
---

# Dedicated Engine Upgrade

Tiap box Wokku mulai dengan shared engine — container multi-tenant yang instant, zero-config, dan cukup buat kebanyakan app. Saat shared sudah nggak cukup, kamu bisa upgrade ke **dedicated** engine: container single-tenant yang ukurannya ngikutin box kamu.

## Kapan harus upgrade

Upgrade ke dedicated engine kalau:

- **Kamu udah hit shared cap** — `SharedDatabaseQuotaJob` warning di 80% usage; di 100% write di-block dengan grace window 24 jam.
- **Butuh resource lebih** — Container dedicated punya connection limit lebih tinggi, nggak ada noisy-neighbor I/O, dan full admin access (superuser buat Postgres, admin vhost buat RabbitMQ, dll.).
- **Butuh DB shared lintas beberapa app** — Postgres atau MySQL dedicated bisa di-link ke beberapa box; shared tenant hanya scope ke satu box.
- **Butuh engine tanpa shared tier** — MySQL dan MongoDB hanya tersedia sebagai dedicated; nggak ada shared MySQL atau MongoDB.

## Kuota

Tiap workspace berbayar dapat:

- **3 dedicated DB slot** — di-share lintas Postgres, MySQL, dan MongoDB (ketiganya narik dari pool yang sama)
- **3 dedicated Redis slot** — pool terpisah

Workspace Free plan punya 0 dedicated slot; upgrade plan kamu buat unlock.

| Plan | Dedicated DB slot | Dedicated Redis slot |
|---|---|---|
| Free | 0 | 0 |
| Solo | 3 | 3 |
| Pro | 3 | 3 |
| Team | 3 | 3 |

> **Contoh**: Workspace Pro dengan dua dedicated Postgres DB dan satu dedicated MySQL sudah pakai semua 3 DB slot. Masih ada 3 Redis slot yang tersedia.

## Sizing

Ukuran dedicated engine **ngikutin size box** — nggak ada picker sizing terpisah. Box small dapat dedicated engine small; box large dapat dedicated engine large. Kalau butuh DB yang lebih besar, resize box-nya dulu.

| Size box | Size dedicated engine |
|---|---|
| Sleeping | — (tidak tersedia) |
| Small | Small |
| Medium | Medium |
| Large | Large |
| X-Large | X-Large |

## Cara upgrade

Kamu bisa upgrade saat box creation atau kapan saja setelahnya dari settings box.

### Saat bikin box

:::tabs
::web-ui
Di form **New Box**, expand **Add-ons** → pilih engine → toggle **Dedicated**. Opsi dedicated di-grey-out kalau kamu nggak punya sisa kuota.

::cli
```bash
# Upgrade Postgres ke dedicated saat creation
wokku apps:create my-app --dedicated postgres

# Atau enable shared dulu, baru upgrade belakangan
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

### Dari settings box (setelah creation)

:::tabs
::web-ui
Pergi ke box → **Settings → Add-ons** → klik **Upgrade to dedicated** di sebelah engine → konfirmasi.

::cli
```bash
wokku addons:dedicated:upgrade my-app postgres
wokku addons:dedicated:upgrade my-app redis
wokku addons:dedicated:upgrade my-app mysql    # fresh-create, nggak ada shared tier
wokku addons:dedicated:upgrade my-app mongodb  # fresh-create, nggak ada shared tier
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

## Yang terjadi saat upgrade

Untuk **Postgres** dan **Redis** (yang punya shared tier):

1. **Provision** — Container dedicated baru dibuat dan di-healthy-check.
2. **Migrasi data** — Snapshot konsisten diambil dari shared tenant dan di-restore ke container dedicated. Untuk Postgres pakai `pg_dump | pg_restore`; untuk Redis pakai `BGSAVE` + `RESTORE`.
3. **Flip URL** — `DATABASE_URL` (atau `REDIS_URL`) di-update secara atomik untuk menunjuk ke container dedicated.
4. **Restart** — Box direstart untuk mengambil URL baru.
5. **Grace period** — Shared tenant disimpan selama 24 jam kalau kamu perlu rollback. Setelah 24 jam dibersihkan otomatis.

Untuk **MySQL** dan **MongoDB** (tanpa shared tier):

1. **Provision** — Container dedicated dibuat dan di-healthy-check.
2. **Inject URL** — `DATABASE_URL` (MySQL) atau `MONGO_URL` (MongoDB) di-set di box.
3. **Restart** — Box restart. App kamu handle pembuatan schema saat boot pertama.

Flow lengkap biasanya selesai dalam kurang dari 2 menit untuk dataset kecil. Untuk database Postgres besar (> 1 GB) beri waktu 5–10 menit; box akan terus serve traffic saat migrasi (read traffic kena shared tenant lama; write traffic di-pause sebentar saat flip URL).

## Perilaku rollback

Kalau provisioning atau migrasi data gagal, Wokku otomatis rollback:

- URL shared tenant dibiarkan utuh; box terus jalan.
- Container dedicated yang baru dibuat setengah jalan di-destroy.
- Tidak ada kuota slot yang dikonsumsi.

Kalau upgrade sukses tapi kamu mau balik dalam grace window 24 jam, hubungi support — shared tenant masih tersedia dan rollback manual bisa dilakukan. Setelah 24 jam shared tenant dibersihkan permanen.

## Empat engine yang didukung

| Engine | Env var URL | Data dimigrasi dari shared? |
|---|---|---|
| **PostgreSQL** | `DATABASE_URL` | Ya — `pg_dump / pg_restore` |
| **MySQL** | `DATABASE_URL` | Tidak — fresh-create |
| **MongoDB** | `MONGO_URL` | Tidak — fresh-create |
| **Redis** | `REDIS_URL` | Ya — `BGSAVE / RESTORE` |

## Lihat juga

- [Engine yang didukung](/docs/databases/engines) — overview engine dan referensi connection URL
- [Create & Link add-on](/docs/databases/create-link) — enable shared add-on, referensi CLI/API/MCP lengkap
- [Plan Bundle](/docs/billing/plan-bundles) — kuota plan dan apa saja yang included di tiap plan
