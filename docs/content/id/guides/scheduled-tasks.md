# Jadwalkan Tugas (Cron)

Jalankan perintah sesuai jadwal — pembersihan tiap malam, email laporan, cache
warmer, sinkronisasi data — tanpa worker yang berjalan terus.

:::callout note
Scheduled task adalah fitur **Pro**. Lihat [Plan](/docs/billing/plans).
:::

## Cara kerja

Scheduled task menjalankan perintah sekali-pakai di dalam salinan baru container
aplikasimu sesuai jadwal cron, lalu keluar. Ia berbagi config var dan add-on
aplikasimu, jadi bisa menjangkau database dan Redis-mu.

## Buat scheduled task

:::tabs
::web-ui
1. Buka aplikasimu → **Scheduled Tasks**
2. **New Task** → masukkan ekspresi cron dan perintahnya
3. Simpan — jalan sesuai jadwal mulai sekarang

::cli
```bash
# setiap hari jam 02:00
wokku scheduled-tasks:create my-app \
  --schedule "0 2 * * *" \
  --command "bin/rails runner 'Cleanup.run'"
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/scheduled_tasks \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"schedule": "0 2 * * *", "command": "bin/rails runner Cleanup.run"}'
```

::mcp
Tanya Claude: *"Jadwalkan `bin/rails runner Cleanup.run` jalan tiap hari jam 2 pagi di my-app"*
:::

## Referensi cepat ekspresi cron

```text
┌─ menit (0-59)
│ ┌─ jam (0-23)
│ │ ┌─ tanggal (1-31)
│ │ │ ┌─ bulan (1-12)
│ │ │ │ ┌─ hari (0-6, Min=0)
* * * * *
```

| Jadwal | Arti |
|---|---|
| `*/15 * * * *` | tiap 15 menit |
| `0 * * * *` | tiap jam, di awal jam |
| `0 2 * * *` | tiap hari jam 02:00 |
| `0 0 * * 1` | tiap Senin tengah malam |

:::callout warn
Jadwal berjalan dalam **UTC**. Konversi waktu lokalmu (WIB = UTC+7) — mis. 09:00
WIB = `0 2 * * *`.
:::

## List & hapus

:::tabs
::cli
```bash
wokku scheduled-tasks my-app            # list
wokku scheduled-tasks:remove my-app ID  # hapus
```
:::

## Troubleshooting

- **Tugas tidak jalan** — pastikan cron dalam UTC dan aplikasi berstatus Pro.
- **Command not found** — pakai path yang sama seperti di `wokku run` (mis. `bin/rails`, `python manage.py`).
- **Butuh DB** — otomatis mewarisi config var + add-on; tanpa wiring tambahan.

## Langkah berikutnya

- [Jalankan background worker](/docs/guides/background-workers) · [Logs](/docs/apps/logs)
