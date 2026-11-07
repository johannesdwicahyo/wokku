---
title: Backup & Restore
summary: Backup harian untuk database dedicated, backup on-demand, download, dan restore.
last_updated: 2026-11-07
---

Cek backup database kamu, buat backup sekarang, download, atau restore.

## Apa saja yang di-backup

| Database | Backup otomatis |
|---|---|
| Dedicated Postgres, MySQL, MariaDB, MongoDB, Redis | Setiap malam. Wokku menyimpan minimal 7 backup harian terakhir. |
| Shared Postgres, MariaDB | Tidak ada. Snapshot terakhir dibuat saat kamu menghapus add-on. |
| Shared Redis | Tidak pernah di-backup. |

Backup dienkripsi, dan Wokku yang mengatur lokasi penyimpanannya.

:::callout tip
Butuh backup untuk shared database? [Upgrade ke dedicated](/docs/databases/create-link#upgrade-to-dedicated). Data kamu ikut pindah.
:::

## Lihat daftar backup

:::tabs
::web-ui
Klik **Databases** di sidebar → database kamu → **Backups**.

::cli
```bash
wokku databases          # find the database name
wokku backups my-db
```

::api
```bash
curl https://wokku.cloud/api/v1/databases/my-db/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Tampilkan daftar backup untuk my-db"* (tool `wokku_list_backups`).
:::

## Backup sekarang

:::tabs
::web-ui
Di tab **Backups**, klik **Backup now**.

::cli
```bash
wokku backups:capture my-db
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/databases/my-db/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Backup my-db sekarang"* (tool `wokku_create_backup`).
:::

## Download backup

:::tabs
::web-ui
Di tab **Backups**, klik **Download** di samping backup yang sudah selesai.

::cli
```bash
wokku backups:download my-db BACKUP_ID my-db.dump
```

Kalau nama file tidak diisi, yang ditampilkan adalah URL download berumur pendek.

::api
```bash
curl https://wokku.cloud/api/v1/databases/my-db/backups/BACKUP_ID/download \
  -H "Authorization: Bearer $TOKEN"
```

Mengembalikan URL download yang kedaluwarsa setelah 5 menit.

::mcp
Minta ke Claude: *"Kasih link download untuk backup terbaru my-db"* (tool `wokku_get_backup_download_url`).
:::

## Restore backup

:::callout warning
Restore akan **menimpa** database. Semua data yang ditulis setelah backup itu akan hilang.
:::

:::tabs
::web-ui
Di tab **Backups**, klik **Restore** di samping backup, lalu **Yes, restore now**.

::cli
```bash
wokku backups:restore my-db BACKUP_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/databases/my-db/backups/BACKUP_ID/restore \
  -H "Authorization: Bearer $TOKEN"
```

Restore berjalan di background.

::mcp
Minta ke Claude: *"Restore my-db dari backup BACKUP_ID"* (tool `wokku_restore_backup`).
:::

Backup Redis tidak bisa di-restore dari dashboard. Download backup-nya lalu hubungi support.

## Self-hosting

Menjalankan Wokku di server sendiri? Kamu yang menentukan tujuan backup (S3, R2, Backblaze B2, dan storage lain yang kompatibel dengan S3). Lihat [Self-hosting](/docs/oss/overview).
