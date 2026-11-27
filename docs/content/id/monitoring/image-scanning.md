---
title: Pemindaian Image
summary: Periksa image setiap deploy untuk kerentanan yang sudah diketahui, lihat hasilnya di panel Security app, dan aktifkan di instalasi self-host.
last_updated: 2026-11-27
---

Pemindaian image mencari kerentanan yang sudah diketahui publik (CVE) pada paket sistem operasi dan library di dalam image app kamu. Hasilnya muncul di **Overview** app dan di **Settings → Security**.

## Apa yang dilakukan dan tidak dilakukan

- Yang dipindai adalah **layer image** yang sedang berjalan, memakai Trivy. Kode sumber kamu tidak dibaca.
- Hanya kerentanan yang **sudah diketahui**. "No known vulnerabilities in the image" artinya scanner tidak menemukan apa pun di databasenya — bukan klaim bahwa app kamu aman. Kode kamu sendiri, konfigurasi, dan secret tidak diperiksa.
- Pemindaian tidak pernah memblokir atau menggagalkan deploy. Kalau pemindaian gagal atau timeout, deploy tidak terpengaruh dan dicoba lagi malam itu.

## Aktifkan (self-host)

Pemindaian image nonaktif secara default. Untuk mengaktifkannya:

1. Di initializer Rails, set `c.image_scans = true` di dalam `Wokku.configure`.
2. Di setiap host, tambahkan `WOKKUD_IMAGE_SCAN=1` ke `/etc/wokkud/env` lalu restart wokkud.

Batas opsional untuk container scanner: `WOKKUD_SCAN_MEMORY` (default `2g`), `WOKKUD_SCAN_PIDS` (`512`), dan `WOKKUD_SCAN_CPUS` (`2`).

## Resource, disk, dan bandwidth

- Satu pemindaian per host dalam satu waktu, tidak pernah saat build berjalan, dan timeout 5 menit per pemindaian.
- Scanner berjalan di container sementara tersendiri tanpa jaringan, filesystem read-only, dan semua capability dilepas.
- Database kerentanan disimpan di volume Docker `wokku-trivy-cache`. Database utama diperbarui setiap hari; database Java diperbarui seminggu sekali dan berukuran sekitar 1 GB. Pembaruan adalah satu-satunya langkah yang memakai jaringan.
- Kalau disk host terpakai lebih dari 85%, pemindaian gagal dengan `disk_full` supaya disk tidak penuh.
- Image dipindai setelah setiap deploy, dan setiap malam image yang pemindaian terakhirnya lebih dari 20 jam dipindai ulang.

## Membaca panel Security

Panel menghitung temuan per tingkat keparahan: Critical, High, Medium, Low, dan Unknown, plus berapa yang sudah punya perbaikan. Panel juga menampilkan kapan image dipindai dan versi Trivy.

Klik **View findings** untuk daftarnya: severity, ID (ID CVE tertaut ke advisory), paket, versi terpasang → versi perbaikan, dan judul. Pakai **Fixable only** untuk melihat apa yang selesai dengan update. Daftar menampilkan 50 temuan paling parah. Perbaikannya biasanya build ulang dengan base image yang lebih baru atau update paket, lalu deploy lagi.
