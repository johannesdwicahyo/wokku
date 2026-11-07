---
title: Menghubungkan Server
summary: Tambahkan server lain ke Wokku self-hosted kamu supaya app bisa jalan di sana.
last_updated: 2026-11-07
---

Tambahkan server kedua (atau ketiga) ke instalasi Wokku self-hosted. Di Wokku Cloud kamu tidak perlu melakukan ini — kami yang menjalankan server.

Server pertama kamu sudah dihubungkan otomatis oleh [installer](/docs/oss/overview).

## Langkah-langkah

1. Sebagai admin, buka **Servers** di sidebar dashboard dan tambahkan server: nama dan alamat IP atau hostname-nya.
2. Halaman server menampilkan perintah install satu baris dengan secret token. Salin perintah itu.
3. Di server baru, jalankan perintah tersebut sebagai user dengan `sudo`. Bentuknya seperti ini:
   ```bash
   curl -sSL https://<your-wokku>/install/wokkud.sh | sudo bash -s -- <token>
   ```
4. Tunggu sekitar 30 detik. Halaman server berubah jadi **connected** saat agent pertama kali check-in.

Script ini mengamankan host (security update, firewall, fail2ban) dan meng-install agent Wokku. Tambahkan `--no-harden` di akhir perintah untuk melewati hardening.

:::callout warning
Token di perintah itu adalah secret server. Jangan dibagikan atau ditempel di tempat publik.
:::

## Cara terhubungnya

Agent di server baru berkomunikasi dengan control plane kamu lewat HTTPS — deploy tidak butuh SSH. Field SSH di form server hanya dipakai untuk membaca log dan stats dari host.
