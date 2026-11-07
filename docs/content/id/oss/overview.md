---
title: Self-Hosting
summary: Jalankan engine Wokku open-source di server kamu sendiri dengan satu install script.
last_updated: 2026-11-07
---

Install Wokku di server Ubuntu atau Debian milikmu dan dapatkan dashboard yang sama dengan yang kamu pakai di Wokku Cloud.

:::callout note
Repository source Wokku belum publik. Langkah-langkah ini berlaku setelah kamu punya salinannya; halaman ini akan menautkan repository-nya setelah dipublikasikan.
:::

## Yang kamu dapat

Wokku self-hosted adalah engine yang sama yang menjalankan Wokku Cloud:

| Termasuk | |
|---|---|
| Dashboard dan REST API | ✓ |
| Deploy lewat `git push` (Dockerfile kamu, atau auto-detect Nixpacks) | ✓ |
| HTTPS otomatis dan custom domain (Caddy) | ✓ |
| App one-click | ✓ |
| Database — shared dan dedicated | ✓ |
| Scheduled task, log, metrics, rollback | ✓ |
| Auto-deploy dari GitHub | ✓ |
| Workspace, member, dan role | ✓ |
| Lebih banyak server dalam satu dashboard | ✓ |

Yang berbeda dari Wokku Cloud:

- **Tidak ada billing.** Tidak ada harga, plan, atau batasan.
- **Tidak ada DNS otomatis.** Kamu mengarahkan domain sendiri.
- **CLI `wokku`, plugin Claude Code, dan app iOS hanya terhubung ke wokku.cloud.** Pakai dashboard atau REST API di instalasi kamu.
- **Sign-up tertutup secara default.** Kamu membuat akun admin di kunjungan pertama; orang lain tidak bisa mendaftar kecuali kamu izinkan.

## Persyaratan

- Server **Ubuntu 22.04/24.04** atau **Debian 11+** yang masih fresh, x86_64
- Port **80** dan **443** terbuka
- Akses `sudo`

## Install

1. Taruh salinan repository Wokku di `/opt/wokku` pada server.
2. Jalankan installer:
   ```bash
   sudo bash /opt/wokku/install.sh
   ```
3. Buka URL yang dicetak (`https://<your-ip>.sslip.io`) dan buat akun admin kamu.

Installer akan menyiapkan Docker, menjalankan control plane, dan meng-install runtime app (Docker Swarm, registry lokal, Caddy, Nixpacks, dan agent `wokkud`) di mesin yang sama. Server mendaftarkan dirinya sendiri sebagai server pertama kamu. `<ip>.sslip.io` memberi kamu alamat HTTPS yang langsung berfungsi tanpa setup DNS.

Script ini aman dijalankan ulang.

## Pengaturan

Atur ini di `/opt/wokku/.env`, lalu jalankan `docker compose up -d` di `/opt/wokku`:

| Variable | Fungsinya |
|---|---|
| `WOKKU_CANONICAL_DOMAIN` | Domain tempat app berada (`<app>.<domain>`). Default-nya `<ip>.sslip.io`. Arahkan wildcard DNS record ke server sebelum mengubahnya. |
| `WOKKU_OPEN_REGISTRATION=1` | Izinkan siapa saja sign-up. Default-nya mati. |
| `WOKKU_REQUIRE_ADMIN_2FA=1` | Wajibkan admin mengaktifkan 2FA. Default-nya mati. |

## Update

Jalankan ulang installer. Installer akan menarik kode terbaru dan mem-build ulang:

```bash
sudo bash /opt/wokku/install.sh
```

## Menambah server

Lihat [Menghubungkan Server](/docs/oss/connect-server).

## Reset password admin

```bash
cd /opt/wokku
docker compose run web bin/rails runner \
  'User.find_by(role: :admin).update!(password: "new-strong-password")'
```

## Lisensi

AGPL-3.0-or-later. Kamu bisa menjalankannya untuk diri sendiri, tim, atau perusahaan kamu. Kalau kamu menawarkan versi yang dimodifikasi sebagai layanan hosted, kamu wajib mempublikasikan perubahanmu. Untuk lisensi lain, email [hello@wokku.cloud](mailto:hello@wokku.cloud).

Tidak mau mengurus server? [Wokku Cloud](https://wokku.cloud) menjalankan engine ini untuk kamu.
