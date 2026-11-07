---
title: Health Check
summary: Cara Wokku menjaga app kamu tetap sehat saat deploy dan restart, serta status health check yang bisa dikonfigurasi.
last_updated: 2026-11-07
---

Di sini kamu akan tahu apa yang dilakukan Wokku agar app kamu tetap jalan. Tidak ada yang perlu di-setup — kesehatan app diawasi oleh platform.

## Yang terjadi di setiap deploy

- **Yang baru dulu, baru yang lama.** Wokku menyalakan container baru lebih dulu, baru kemudian menghentikan yang lama, jadi deploy tidak memutus traffic.
- **Restart otomatis.** Kalau container berhenti, platform akan me-restart-nya.
- **Deteksi crash.** Crash tampil di app dan bisa [mengirim notifikasi ke kamu](/docs/monitoring/notifications) (`app_crashed`).

Pastikan app kamu listen di `$PORT` dan cepat menjawab HTTP setelah boot.

## Health check yang bisa dikonfigurasi

Path check, timeout, dan jumlah retry kustom **segera hadir**. Sampai saat itu, form **Settings** → **Checks** di dashboard dan `wokku checks:set` tidak akan menyimpan perubahan — kamu akan mendapat pesan "configurable healthchecks are coming soon".

Untuk melihat status saat ini:

:::tabs
::web-ui
Buka app kamu → **Settings** → **Checks**.

::cli
```bash
wokku checks my-app
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/checks \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Tanya Claude: *"Apa pengaturan health check untuk my-app?"*
:::

## Tahu saat app kamu down

Health check menjaga deploy tetap aman. Supaya kamu diberi tahu saat app yang sedang jalan berhenti merespons, pakai [uptime check](/docs/monitoring/uptime).
