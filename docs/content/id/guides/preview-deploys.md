---
title: Preview Deploy untuk Pull Request
summary: Dapatkan URL live untuk setiap pull request, dibuat saat PR dibuka dan dihapus saat PR ditutup.
last_updated: 2026-11-07
---

Kamu akan mengaktifkan PR preview untuk app yang terhubung ke GitHub, lalu membuka pull request untuk mendapatkan URL-nya sendiri.

## Sebelum mulai

App harus terhubung lewat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

## Aktifkan preview

:::tabs
::web-ui
App → tab **Deploy** → **Previews** → centang **Enable PR previews**, simpan.

::cli
```bash
wokku previews:settings my-app --on
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/preview_settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"preview_enabled": true}'
```
:::

Lalu buka pull request. Wokku build branch PR itu di `https://my-app-pr-42.wokku.app` (42 adalah nomor PR) dan mengomentari URL-nya di PR.

## Data

Preview mendapat salinan environment variable app, **termasuk `DATABASE_URL`**, jadi preview terhubung ke database yang sama dengan app kamu. Pengaturan **Database strategy** tersimpan, tapi preview belum mendapat database sendiri.

:::callout warning
Jangan jalankan migration atau script seed di preview, dan jangan klik alur yang menulis data penting. Kalau itu berisiko untuk app kamu, biarkan preview mati.
:::

## Batasan dan pembersihan

- Maksimal 3 preview berjalan bersamaan per team. Lebih dari itu, Wokku memberi komentar di PR alih-alih build.
- Preview dihapus saat PR-nya di-merge atau ditutup. Preview yang idle akan sleep setelah 7 hari dan dihapus setelah 30 hari.

Hapus secara manual:

:::tabs
::web-ui
Tab **Deploy** → **Previews** → **Destroy** di samping preview-nya.

::cli
```bash
wokku previews my-app              # list
wokku previews:destroy my-app 42   # tear down PR #42
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/previews/42 \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Hapus preview PR 42 milik my-app."*
:::

## Troubleshooting

- **Preview tidak muncul**: pastikan preview aktif, PR ada di repo yang terhubung, dan team kamu punya kurang dari 3 preview.
- **Tidak ada komentar di PR**: cek ulang apakah GitHub App masih punya akses ke repo.

## Langkah selanjutnya

- [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
- [Rollback deploy yang bermasalah](/docs/guides/rollback)
