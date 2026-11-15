---
title: Siap Production
summary: Jauhkan state dari container, shutdown dengan rapi, dan atur ukuran app supaya deploy dan resize tidak bikin kaget.
last_updated: 2026-11-07
---

Kamu akan mengecek beberapa hal yang menjaga app production tetap sehat saat deploy, restart, dan resize.

## Pilih ukuran yang tetap menyala

App gratis tidur setelah 30 menit tanpa trafik dan butuh sekitar 30 detik untuk bangun di request berikutnya. Itu tidak masalah untuk eksperimen. Untuk apa pun yang diandalkan orang, beri app CPU dan RAM berbayar supaya tetap menyala. Lihat [Resource](/docs/scaling/resources) dan [Harga](/docs/billing/pricing).

## Jauhkan state dari container

Setiap deploy, restart, dan resize mengganti container, dan disk lokalnya ikut hilang.

| Tempat data disimpan | Bertahan setelah deploy? |
|------------------|--------------------|
| Add-on database (Postgres, MySQL, MariaDB, MongoDB, Redis) | Ya |
| Disk milik container itu sendiri (`/tmp`, `./uploads`, file SQLite di disk) | **Tidak** |

:::callout warning
Upload user di folder lokal atau database SQLite di disk akan hilang di deploy berikutnya. Simpan state di [database](/docs/databases/create-link) atau [object storage](/docs/databases/object-storage).
:::

## Shutdown dengan rapi

Saat container diganti, proses kamu menerima `SIGTERM`, lalu `SIGKILL` setelah masa tenggang singkat.

- Web server sebaiknya menyelesaikan request yang sedang berjalan lalu exit.
- Background job yang masih berjalan akan di-kill. Buat job yang idempotent supaya retry aman, dan pecah job panjang jadi langkah-langkah yang lebih kecil.

Restart atau resize app akan me-restart **semua** process type-nya, jadi resize web juga me-restart worker kamu.

## Kesehatan

Platform mengawasi container kamu: saat deploy, container baru dijalankan sebelum yang lama dihentikan, dan container yang crash di-restart otomatis. Health check yang bisa dikonfigurasi segera hadir. Lihat [Health Check](/docs/monitoring/health-checks).

## Resize dengan aman

- Menaikkan ukuran **(up)** itu aman.
- Menurunkan ukuran **(down)** di bawah pemakaian sebenarnya bisa membuat app di-kill karena kehabisan memori saat boot. Cek [Metrik](/docs/monitoring/metrics) dulu.
- Resize sebelum lonjakan trafik, bukan saat sedang terjadi.

## Checklist

- [ ] App berjalan di ukuran berbayar, bukan ukuran sleeping yang gratis
- [ ] Tidak ada data penting yang ditulis ke disk container
- [ ] Migration dijalankan dengan `wokku run my-app -- <migrate command>` setelah setiap deploy
- [ ] Background job idempotent dan menangani `SIGTERM`
- [ ] Pemakaian memori di bawah ukuran baru sebelum kamu menurunkan ukuran
