---
title: Menjadwalkan Task (Cron)
summary: Jalankan perintah sesuai jadwal cron, seperti pembersihan tiap malam atau email laporan, tanpa worker yang berjalan terus.
last_updated: 2026-11-07
---

Kamu akan menambahkan entri cron yang menjalankan perintah dengan config vars dan add-on milik app kamu.

:::callout note
Scheduled tasks sudah termasuk begitu team kamu membayar resource apa pun. Team yang hanya pakai paket gratis akan melihat ajakan upgrade. Lihat [Pricing](/docs/billing/pricing).
:::

## Buat task

:::tabs
::web-ui
1. App → tab **Settings** → **Scheduled Tasks**.
2. Tambahkan task: jadwal cron, perintah, deskripsi (opsional).
3. Simpan.

::cli
```bash
wokku cron:add my-app \
  --schedule "0 2 * * *" \
  --command "bin/rails runner 'Cleanup.run'" \
  --description "Nightly cleanup"
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"schedule": "0 2 * * *", "command": "bin/rails runner Cleanup.run", "description": "Nightly cleanup"}'
```

::mcp
Minta ke Claude: *"Jadwalkan `bin/rails runner Cleanup.run` setiap hari jam 02:00 di my-app."*
:::

## Referensi cepat cron

```text
┌─ minute (0-59)
│ ┌─ hour (0-23)
│ │ ┌─ day of month (1-31)
│ │ │ ┌─ month (1-12)
│ │ │ │ ┌─ day of week (0-6, Sun=0)
* * * * *
```

| Jadwal | Arti |
|---|---|
| `*/15 * * * *` | setiap 15 menit |
| `0 * * * *` | setiap jam |
| `0 2 * * *` | setiap hari jam 02:00 |
| `0 0 * * 1` | setiap Senin tengah malam |

## Lihat daftar dan hapus

:::tabs
::web-ui
Tab **Settings** → **Scheduled Tasks** menampilkan setiap task. Hapus dari daftar itu.

::cli
```bash
wokku cron my-app                  # list, with task IDs
wokku cron:remove my-app TASK_ID   # remove
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks -H "Authorization: Bearer $TOKEN"
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks/TASK_ID -H "Authorization: Bearer $TOKEN"
```
:::

## Troubleshooting

- **Command not found**: pakai perintah yang sama yang berhasil dengan `wokku run my-app -- <command>`.
- **Error "Upgrade"**: team kamu belum punya resource berbayar.

## Langkah selanjutnya

- [Menjalankan background worker](/docs/guides/background-workers)
- [Log](/docs/monitoring/logs)
