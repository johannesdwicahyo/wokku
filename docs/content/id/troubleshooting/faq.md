---
cloud_prices: true
title: FAQ
summary: Jawaban singkat tentang cara Wokku mem-build app, apa yang gratis, backup, migrasi dari Heroku, dan self-hosting.
last_updated: 2026-11-07
---

## Apakah Wokku managed?

Ya. Wokku Cloud menjalankan server untuk kamu — kamu push kode, kami build dan jalankan. Kamu tidak pernah menghubungkan atau memilih server. Kalau kamu ingin menjalankan Wokku sendiri, lihat [Self-Hosting](/docs/oss/overview).

## Bahasa apa saja yang didukung?

Apa pun yang bisa jalan di container. Kalau repo kamu punya `Dockerfile`, Wokku mem-build-nya. Kalau tidak, Wokku mendeteksi otomatis Node.js, Python, Ruby, Go, PHP, Java, dan lainnya dengan Nixpacks. Lihat [Framework](/docs/frameworks/index) dan [app one-click](/docs/templates/browse).

## Ada tier gratis?

Ada. App gratis tidur setelah 30 menit tanpa traffic dan bangun lagi di request berikutnya (sekitar 30 detik). Shared Postgres, MariaDB, dan Redis juga gratis. Kamu hanya membayar CPU, RAM, dan dedicated database yang kamu pilih — lihat [Harga](/docs/billing/pricing).

## Bagaimana cara kerja billing?

Kamu top up saldo (dalam IDR) dan Wokku memotong biaya resource kamu setiap hari. Lihat [Harga](/docs/billing/pricing) dan [Invoice](/docs/billing/invoices).

## Bagaimana cara kerja backup?

Dedicated database di-backup otomatis untuk kamu, terenkripsi, dan kamu bisa membuat backup on-demand atau restore dari halaman database. Lihat [Backup](/docs/databases/backups).

## Bisa migrasi dari Heroku?

Bisa. Alur kerjanya sama — `git push` untuk deploy, `Procfile` untuk process type, env var untuk config. Satu perbedaan: tidak ada release phase, jadi jalankan migration dengan `wokku run my-app -- <command>` setelah deploy. Lihat [Migrasi dari Heroku](/docs/migrate/heroku).

## Bisa self-host Wokku?

Bisa — engine-nya open source (AGPL-3.0). Lihat [Self-Hosting](/docs/oss/overview).

## Bagaimana cara mendapat bantuan?

Email [support@wokku.cloud](mailto:support@wokku.cloud).
