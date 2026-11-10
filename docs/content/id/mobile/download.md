---
title: App iOS & Mac
summary: App Wokku untuk iPhone dan menu bar Mac — cek app kamu, baca log, perbaiki masalah, dan terima alert saat jauh dari meja.
eyebrow: mobile
last_updated: 2026-11-11
---

Pakai app Wokku supaya tetap bisa on call untuk app kamu dari iPhone atau menu bar Mac.

**[Download Wokku untuk iPhone di App Store](https://apps.apple.com/app/wokku/id6826866287)**

:::callout note
App menu bar Mac segera hadir di Mac App Store.
:::

## Persyaratan

| Platform | Minimum |
|---|---|
| iPhone | iOS 17 |
| Mac (app menu bar) | macOS 14 |

Sign in dengan Apple, dengan email, atau dengan **Continue with wokku.cloud**.

## Di iPhone

App ini punya empat tab: **Apps**, **Incidents**, **Databases**, dan **Settings**.

- **Apps** — lihat status tiap app, lalu restart, stop, start, atau scale. Dari menu **⋯** kamu bisa redeploy, menyalakan atau mematikan maintenance mode, serta lock atau unlock deploy.
- **Deploy dan release** — buka sebuah deploy untuk membaca log-nya, atau rollback ke release sebelumnya.
- **Log** — baca dan live-stream log sebuah app.
- **Config** — lihat environment variable (read-only; nilainya disembunyikan kalau kamu viewer di tim).
- **Incidents** — lihat app mana yang down dan kapan pulih.
- **Databases** — cek status database dan backup sekarang.

Untuk mengubah config, domain, database, atau billing, pakai [dashboard](https://wokku.cloud/dashboard), [CLI](/docs/cli/commands), atau [Claude Code](/docs/mcp/tools).

## Di Mac

App Mac ada di menu bar dan menampilkan kesehatan app kamu sekilas. App ini refresh setiap menit dan setiap ada alert masuk, serta menampilkan status terakhir yang diketahui kalau kamu offline.

Dari menu kamu bisa membuka log sebuah app, start, stop, atau restart app, dan melihat insiden yang masih terbuka. **Open dashboard** membawamu ke wokku.cloud.

## Push alert

Saat pertama kali sign in, tap **Turn on notifications** lalu izinkan. Kalau sebelumnya kamu menolak, buka **Settings → Notifications → Open Settings** lalu izinkan di Settings iOS.

Kamu akan dapat alert saat:

| Alert | Kapan |
|---|---|
| App down | Sebuah app berhenti merespons |
| App recovered | App sudah up lagi |
| App crashed | Proses sebuah app crash |
| Deploy failed | Deploy tidak selesai |
| Backup failed | Backup database tidak selesai |

Tap alert untuk membuka app yang bersangkutan.

### Mute alert

Untuk menjeda alert sementara, buka **Settings → Alert mutes → Add mute…**:

1. Pilih app, tipe alert, atau keduanya.
2. Pilih durasinya: **1 hour**, **8 hours**, **1 day**, atau **Indefinitely**.
3. Tap **Add**.

Untuk menghapus mute, tekan lama lalu tap **Delete**. Mute hanya berlaku untuk alert HP — email dan [channel notifikasi](/docs/monitoring/notifications) lainnya tetap jalan. Kamu juga bisa mute dari CLI dengan `wokku alerts:mute`.

## Hapus akun

**Settings → Delete account…** (di Mac, ada di menu). Ketik email kamu untuk konfirmasi.
