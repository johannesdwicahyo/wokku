---
title: Uptime & Insiden
summary: Wokku mengecek app kamu setiap menit, membuka insiden saat app down, dan memberi tahu kamu — mute push alert saat kamu butuh tenang.
last_updated: 2026-11-07
---

Di sini kamu akan melihat cara kerja uptime check, mencari insiden, dan me-mute alert di HP kamu. Uptime check aktif untuk setiap app yang sedang jalan dan punya domain — tidak perlu diaktifkan.

## Cara kerja uptime check

- Setiap menit Wokku me-request `https://<your-domain>/` (domain pertama app kamu, misalnya `my-app.wokku.app`).
- **Up** = respons apa pun di bawah HTTP 500. 404 tetap berarti app kamu hidup.
- **Down** = 3 check gagal berturut-turut. Wokku membuka **insiden** dan mengirim [notifikasi](/docs/monitoring/notifications) `app_down`.
- Check sukses pertama menutup insiden dan mengirim `app_recovered`.
- App gratis yang [tidur saat idle](/docs/scaling/resources) tidak dicek, supaya check tidak membuatnya terus bangun.

Setiap insiden mencatat penyebabnya:

| Penyebab | Arti |
|---|---|
| `host_down` | Host kami tidak bisa dijangkau — bukan kode kamu; kami sedang menanganinya |
| `app_stopped` | App sedang di-stop |
| `app_crashed` | Container crash — cek `wokku logs my-app` |
| `http_5xx` | App merespons dengan server error |
| `timeout` | App tidak merespons tepat waktu |
| `connection_refused` | Tidak ada yang listen di port app |
| `dns_error` | Domain tidak bisa di-resolve |
| `ssl_error` | Sertifikat SSL gagal saat handshake |

Status seluruh platform bisa dilihat publik di [status.wokku.cloud](https://status.wokku.cloud).

## Melihat daftar insiden

:::tabs
::cli
```bash
wokku incidents                  # open incidents
wokku incidents --all            # recent ones, resolved too
wokku incidents --app my-app     # one app
wokku incidents:info INCIDENT_ID # reason, start, end, duration
```

::api
```bash
curl -G https://wokku.cloud/api/v1/incidents \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "state=all" \
  --data-urlencode "app_id=my-app"

curl https://wokku.cloud/api/v1/incidents/INCIDENT_ID \
  -H "Authorization: Bearer $TOKEN"
```

`state` bernilai `open` (default) atau `all`. Juga menerima `limit` (1–200, default 50) dan `before` (ISO 8601).

::mcp
Tanya Claude: *"Ada yang down?"*
:::

## Mute push alert

Mute hanya membungkam **push alert di HP kamu**, dan hanya untuk kamu. Alert email, Slack, Discord, Telegram, dan webhook tetap dikirim ke seluruh tim.

Mute satu app, satu event, atau keduanya — opsional untuk sementara waktu. Tanpa batas waktu, mute berlaku sampai kamu menghapusnya.

:::tabs
::cli
```bash
wokku alerts:mute --app my-app --for 8h       # all events for my-app, 8 hours
wokku alerts:mute --event deploy_succeeded    # one event, every app
wokku alerts:mutes                            # list active mutes
wokku alerts:unmute MUTE_ID
```

`--for` menerima menit, jam, atau hari: `30m`, `8h`, `1d`.

::api
```bash
curl -X POST https://wokku.cloud/api/v1/alert_mutes \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"app_id": "my-app", "event": "app_down", "until": "2026-11-08T09:00:00Z"}'

curl https://wokku.cloud/api/v1/alert_mutes -H "Authorization: Bearer $TOKEN"
curl -X DELETE https://wokku.cloud/api/v1/alert_mutes/MUTE_ID -H "Authorization: Bearer $TOKEN"
```

::mcp
Tanya Claude: *"Mute alert untuk my-app sampai besok pagi."*
:::

Event yang bisa di-mute: `deploy_succeeded`, `deploy_failed`, `app_crashed`, `backup_completed`, `backup_failed`, `resource_high_cpu`, `resource_high_memory`, `app_down`, `app_recovered`.

:::callout note
Push alert butuh app Wokku iOS & Mac, yang segera hadir. Lihat [App iOS & Mac](/docs/mobile/download).
:::

## Lihat juga

- [Notifikasi](/docs/monitoring/notifications) — pilih ke mana alert `app_down` dikirim
- [Health check](/docs/monitoring/health-checks) — keamanan saat deploy
