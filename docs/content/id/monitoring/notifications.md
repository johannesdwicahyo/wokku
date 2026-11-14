---
title: Notifikasi
summary: Kirim alert deploy, crash, downtime, backup, dan billing ke email, Slack, Discord, Telegram, atau webhook.
last_updated: 2026-11-07
---

Di sini kamu akan menambahkan aturan notifikasi: pilih channel, opsional satu app, dan event yang kamu pedulikan. Aturan dimiliki workspace, jadi semua orang menerima alert yang sama.

## Menambahkan aturan

:::tabs
::web-ui
1. Buka **Settings** → **Notifications** → **+ Add rule**.
2. Pilih **Channel** dan isi setup-nya (lihat tabel di bawah).
3. Opsional, pilih **App** — kosongkan untuk semua app.
4. Centang **Events** lalu klik **Add rule**.
5. Klik **Test** pada aturan baru untuk mengirim pesan contoh.

::cli
CLI hanya bisa menambahkan aturan **email** — pakai dashboard untuk channel lain. Dapatkan ID workspace kamu dengan `wokku teams`.

```bash
wokku notifications:add --team TEAM_ID --channel email \
  --events deploy_failed,app_down,app_crashed
wokku notifications                     # list rules
wokku notifications:test NOTIFICATION_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/notifications \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "TEAM_ID", "channel": "slack",
       "events": ["deploy_failed", "app_down"],
       "config": {"url": "https://hooks.slack.com/services/..."}}'

curl -X POST https://wokku.cloud/api/v1/notifications/NOTIFICATION_ID/test \
  -H "Authorization: Bearer $TOKEN"
```

Dapatkan `team_id` dari `GET /api/v1/teams`. Tambahkan `app_record_id` untuk membatasi aturan ke satu app.

::mcp
Tanya Claude: *"Kirim alert deploy gagal dan downtime untuk my-app ke Slack webhook ini: https://hooks.slack.com/…"*
:::

## Channel

| Channel | Setup |
|---|---|
| **Email** | Tidak perlu apa-apa — dikirim ke email pemilik workspace |
| **Slack** | URL incoming webhook (`config.url`) |
| **Discord** | URL webhook channel (`config.url`) |
| **Telegram** | Bot token + chat ID (`config.bot_token`, `config.chat_id`) |
| **Webhook** | URL HTTPS apa saja (`config.url`). Wokku mengirim POST JSON: `{"event": "...", "app": "...", "timestamp": "..."}` |
| **Push** | Ditambahkan otomatis saat kamu login ke app Wokku iOS & Mac |

## Event

| Event | Dikirim saat |
|---|---|
| `deploy_started` | Deploy dimulai |
| `deploy_succeeded` | Deploy sudah live |
| `deploy_failed` | Deploy gagal |
| `app_crashed` | Container crash |
| `app_auto_stopped` | Wokku menghentikan app yang terus crash |
| `app_down` | [Uptime check](/docs/monitoring/uptime) mendapati app down |
| `app_recovered` | App merespons lagi |
| `backup_failed` | Backup database gagal |
| `domain_added` | Domain ditambahkan |
| `app_created` / `app_deleted` | App dibuat atau dihapus |
| `daily_debit_summary` | Ringkasan billing harian |
| `scheduled_task_failing` | [Scheduled task](/docs/guides/scheduled-tasks) gagal 3 kali berturut-turut |
| `scheduled_task_recovered` | Task tersebut berhasil lagi |

Untuk membungkam push alert di HP kamu tanpa mengubah aturan tim, [mute alert-nya](/docs/monitoring/uptime#mute-push-alerts).

## Menghapus aturan

:::tabs
::web-ui
**Settings** → **Notifications** → hapus aturannya.

::cli
```bash
wokku notifications:remove NOTIFICATION_ID
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/notifications/NOTIFICATION_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Tanya Claude: *"Hapus aturan notifikasi Slack saya."*
:::
