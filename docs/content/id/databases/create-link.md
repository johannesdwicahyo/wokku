---
shared_dbs: true
title: Tambah & Hubungkan Database
summary: Tambahkan shared database gratis ke app kamu, upgrade ke dedicated, atau pakai satu database bersama untuk beberapa app.
last_updated: 2026-11-07
---

Tambahkan Postgres, MariaDB, atau Redis ke `my-app` dalam satu langkah. Wokku menghubungkannya dan mengatur URL koneksinya, jadi app kamu bisa langsung memakainya setelah restart berikutnya.

## Tambah shared database (gratis)

:::tabs
::web-ui
Buka app → **Runtime → Scaling** → **Add-ons** → **+ Add**. Pilih engine, pilih **Shared**, lalu konfirmasi.

::cli
```bash
wokku addons:shared:enable my-app postgres   # or mariadb, redis
```

Atau tambahkan sekalian saat membuat app:

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
Minta ke Claude: *"Tambahkan shared Postgres gratis ke my-app"* (tool `wokku_enable_shared_addon`).
:::

Provisioning butuh beberapa detik. Setelah itu, cek apakah URL-nya sudah di-set:

```bash
wokku config my-app
```

Cari `DATABASE_URL` (Postgres, MariaDB) atau `REDIS_URL` (Redis). Daftar lengkapnya ada di [Engine yang Didukung](/docs/databases/engines#environment-variables).

## Tambah dedicated database

Dedicated database berjalan di container sendiri, mendapat backup setiap malam, dan ditagih per resource. Di dashboard, pilih **Dedicated** alih-alih **Shared** di panel **+ Add**, lalu pilih preset ukuran atau atur slider-nya.

MySQL dan MongoDB hanya tersedia sebagai dedicated dan dimulai dalam keadaan kosong:

```bash
wokku addons:dedicated:upgrade my-app mysql    # or mongodb
```

## Upgrade ke dedicated

Memindahkan shared Postgres, MariaDB, atau Redis yang sudah ada ke container sendiri. Wokku menyalin data kamu, mengarahkan URL app ke database baru, lalu me-restart app.

:::tabs
::web-ui
Buka app → **Settings**. Di bagian **Add-ons**, klik **Upgrade to dedicated** pada kartu shared Postgres atau Redis. Untuk MariaDB, pakai CLI atau API.

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
Minta ke Claude: *"Upgrade Postgres my-app ke dedicated"* (tool `wokku_upgrade_dedicated_addon`).
:::

### Ubah ukuran dedicated database

Buka **Databases** di sidebar → database kamu → **Settings**, atau:

```bash
wokku databases:resize my-app-postgres-dedicated --cpu 0.5 --memory 1024 --disk 20
```

Isi ketiga flag tersebut. Disk hanya bisa diperbesar. Jalankan `wokku databases` untuk melihat nama-nama database kamu.

## Pakai satu database untuk beberapa app

Hubungkan database yang sudah ada ke app lain:

```bash
wokku databases:link my-db other-app --alias DATABASE
```

App tersebut mendapat `<ALIAS>_URL`, dalam contoh ini `DATABASE_URL`. Tanpa `--alias`, namanya mengikuti engine, misalnya `POSTGRES_URL`. Untuk melepasnya, jalankan `wokku databases:unlink my-db other-app`.

## Hapus database

:::callout warning
Menghapus add-on berarti menghapus datanya. Wokku membuat snapshot terakhir lebih dulu, tapi jangan jadikan itu satu-satunya salinan kamu.
:::

:::tabs
::web-ui
Buka app → **Runtime → Scaling** → **Add-ons**, lalu klik **Remove** pada add-on tersebut.

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

## Jalankan migration

Wokku tidak menjalankan migration untuk kamu. Setelah deploy, jalankan sebagai perintah one-off:

```bash
wokku run my-app -- bin/rails db:migrate
```

## Troubleshooting

- **`DATABASE_URL` tidak ada:** add-on masih dalam proses provisioning, atau app sudah punya `DATABASE_URL` sendiri. Cek `wokku addons my-app` dan `wokku config my-app`.
- **Shared database penuh:** upgrade ke dedicated (lihat di atas).
- **Database tertahan di status error:** `wokku databases:retry DB`.

## Selanjutnya

- [Backup & restore](/docs/databases/backups)
- [Environment variable](/docs/apps/config)
