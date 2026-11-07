---
title: Rollback Deploy yang Bermasalah
summary: Kembali ke release sebelumnya saat sebuah deploy merusak app kamu.
last_updated: 2026-11-07
---

Kamu akan mencari release terakhir yang masih bagus lalu rollback ke sana.

## 1. Cari release-nya

:::tabs
::web-ui
App → tab **Deploy** → **Releases** menampilkan setiap release beserta versi dan commit-nya.

::cli
```bash
wokku releases my-app            # versions and descriptions
wokku releases my-app --json     # includes each release's ID
wokku releases:info my-app RELEASE_ID
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/releases \
  -H "Authorization: Bearer $TOKEN"
```
:::

## 2. Rollback

:::tabs
::web-ui
Klik **Rollback** pada release yang kamu mau.

::cli
```bash
wokku rollback my-app RELEASE_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/releases/RELEASE_ID/rollback \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Rollback my-app ke release sebelumnya."*
:::

Rollback muncul sebagai release baru ("Rollback to vN").

## Apa yang dilakukan rollback

- **Memulihkan kode** dari release itu. Prosesnya cepat kalau image release itu masih tersimpan; kalau tidak, Wokku build ulang dari source yang tersimpan.
- **Mempertahankan environment variable yang sekarang.** Rollback tidak memulihkan config lama. Ubah lewat [Environment Variables](/docs/apps/config) kalau perlu.
- **Tidak membatalkan migration database.** Pulihkan dari [backup](/docs/databases/backups) kalau sebuah migration merusak data.

Release yang sudah sangat lama mungkin tidak lagi punya image atau source yang tersimpan. Rollback-nya akan gagal dengan pesan, dan kamu perlu deploy baru.

:::callout tip
Tulis migration yang backward-compatible (tambah dulu, hapus belakangan) supaya rollback kode tetap aman.
:::

## Roll forward

Bug-nya sudah diperbaiki? Deploy lagi. Perbaikannya jadi release terbaru.

## Langkah selanjutnya

- [Backups](/docs/databases/backups)
- [Production Readiness](/docs/apps/best-practices)
