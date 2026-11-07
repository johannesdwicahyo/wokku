---
title: Harga
summary: Bayar hanya untuk CPU, RAM, dan disk yang kamu jalankan, dalam Rupiah. Tanpa plan atau paket.
last_updated: 2026-11-07
---

Di sini kamu akan melihat berapa biaya Wokku dan cara memperkirakan tagihan kamu.

## Gratis

- **3 app sleeping, gratis selamanya.** App akan tidur setelah 30 menit idle dan bangun saat ada request berikutnya (sekitar 30 detik).
- **Shared add-on gratis untuk setiap app:** Postgres atau MariaDB (100 MB) dan Redis (10 MB). Lihat [Engine database](/docs/databases/engines).
- Tidak perlu kartu kredit.

## Harga per unit

| Resource | Harga per bulan |
|---|---|
| CPU | Rp16.000 per vCPU |
| RAM | Rp24.000 per GB |
| Disk | Rp1.000 per GB |

Semua fitur sudah termasuk begitu kamu membayar apa pun.

Kamu ditagih per hari (harga bulanan ÷ 30), sesuai ukuran terbesar yang kamu pakai di hari itu. Ubah ukuran kapan saja: upsize ditagih mulai hari itu, downsize menjadi kredit di invoice berikutnya.

## Harga preset

Process app, per instance:

| Preset | CPU / RAM | Per bulan |
|---|---|---|
| Nano | 0.25 vCPU / 256 MB | Rp10.000 |
| Starter | 0.25 vCPU / 512 MB | Rp16.000 |
| Standard | 0.5 vCPU / 1 GB | Rp32.000 |
| Large | 1 vCPU / 2 GB | Rp64.000 |
| X-Large | 2 vCPU / 4 GB | Rp128.000 |

Dedicated database (Postgres, MySQL, MariaDB, MongoDB):

| Preset | CPU / RAM / disk | Per bulan |
|---|---|---|
| Small | 0.25 vCPU / 512 MB / 5 GB | Rp21.000 |
| Medium | 0.5 vCPU / 1 GB / 20 GB | Rp52.000 |
| Large | 1 vCPU / 2 GB / 50 GB | Rp114.000 |

Dedicated Redis:

| Preset | CPU / RAM / disk | Per bulan |
|---|---|---|
| Small | 0.25 vCPU / 256 MB / 1 GB | Rp11.000 |
| Medium | 0.25 vCPU / 1 GB / 2 GB | Rp30.000 |
| Large | 0.5 vCPU / 2 GB / 4 GB | Rp60.000 |

## Contoh

App Rails dengan `web` Standard (Rp32.000), `worker` Starter (Rp16.000), dan dedicated Postgres Small (Rp21.000) biayanya **Rp69.000/bulan**.

Slider di **Runtime** → **Scaling** menampilkan harga sebelum kamu menyimpan. Lihat [Resource & Ukuran](/docs/scaling/resources).

## Yang tidak perlu kamu bayar

- App sleeping, dan app yang di-stop (disk volume tetap ditagih).
- App yang sudah dibuat tapi belum pernah di-deploy.
- Shared add-on.

## Akun baru

Sampai invoice pertama kamu dibayar, total semua resource kamu dibatasi Rp150.000/bulan (halaman Billing kamu menampilkan batas saat ini). Bayar invoice tersebut untuk menaikkan batasnya.

## Perubahan harga

Harga di atas adalah harga saat ini. [Halaman harga](https://wokku.cloud/pricing) dan halaman Billing kamu selalu menampilkan harga terbaru. Kalau kenaikan harga membuat tagihan kamu naik, kamu akan dikirimi email minimal 30 hari sebelum berlaku.

## Pembayaran

Kamu menerima satu invoice bulanan dalam Rupiah. Bayar dengan QRIS, transfer bank, atau kartu. Lihat [Invoice & Pembayaran](/docs/billing/invoices).

## Self-hosting

Edisi open-source tidak punya billing. Lihat [Self-hosting](/docs/oss/overview).
