---
title: Box Tier
summary: "Lima ukuran box untuk app hobby sampai production. Jumlah yang bisa kamu jalanin ditentuin plan; ukurannya nyesuain workload."
eyebrow: scaling
last_updated: 2026-05-29
---

# Box Tier

*Box* itu satu container Dokku — yang di industri lain disebut "dyno". Wokku punya lima ukuran box; jumlah yang bisa kamu jalanin ditentuin [plan](/docs/billing/plans) kamu, ukurannya nyesuain workload.

## Lima ukurannya

| Tier | RAM | vCPU | Disk | Catatan |
|---|---|---|---|---|
| **Sleeping** | 256 MB | shared, tidur | — | App idle. Bangun saat request pertama (~2-3 detik). |
| **Small** | 512 MB | shared | 1 GB | Side project, dev / staging, app hobby. |
| **Medium** | 1 GB | shared | 2 GB | Production Rails / Django / Laravel di traffic low-to-medium. |
| **Large** | 2 GB | 1.0 dedicated | 4 GB | Workload production dengan traffic stabil + worker. |
| **X-Large** | 4 GB | 2.0 dedicated | 8 GB | Production berat (image processing, ML inference, klien DB besar). Add-on plan Team. |

Sleeping / Small / Medium pakai shared vCPU — kapasitas burst tergantung beban tetangga. Large dan X-Large dapat core dedicated.

## Berapa yang kamu dapat

Tiap plan dapat quota tetap per ukuran. Tabel lengkap di [Plan & Harga](/docs/billing/plans).

| Plan | Small | Medium | Large | Sleeping |
|---|---|---|---|---|
| Free | — | — | — | 3 |
| Solo | 3 | — | — | 3 |
| Pro | 3 | 2 | — | 3 |
| Team | 3 | 2 | 1 | 3 |

**Team** bisa beli tambahan: Rp 300.000/bulan per Extra Large, Rp 600.000/bulan per Extra X-Large. Nggak ada metering — harga add-on flat.

> Kenapa "sleeping" spesial: box sleeping nggak masuk quota box aktif dan nggak ada biayanya. App-nya idle-in container-nya; request berikutnya bangunin container dalam 2-3 detik. Cocok buat environment staging, app demo, dan side project traffic rendah.

## Pilih ukuran

Aturan kasar yang cocok buat kebanyakan app:

— **Dev / staging** → Small (512 MB). Cukup buat workload `bin/dev`.
— **Production Rails / Django / Laravel di <50 req/s** → Small atau Medium.
— **Production di 50–200 req/s** → Medium.
— **Background worker (Sidekiq / Celery / RQ) handle 100+ job/menit** → Medium atau Large tergantung memory per-job.
— **Image / video processing, ML inference, report DB-side berat** → Large atau X-Large.

Kalau ragu, mulai dari satu ukuran lebih kecil dan pantau [metrics](/docs/monitoring/metrics) seminggu. Dashboard nampilin p95 memory dan CPU per 5 menit — gampang spot tier yang kronis kekecilan atau kebesaran.

## Ganti ukuran

Dari dashboard: buka app → **Scaling → Change Tier**. Apply.

Wokku roll container ke ukuran baru tanpa downtime: proxy nahan koneksi baru beberapa detik selama container baru start; request yang lagi jalan selesai di container lama sebelum terminate.

Ganti tier mid-cycle akan **diprorata** di invoice berikutnya — kamu nggak ditagih sebulan penuh buat upgrade di hari ke-28.

## Bundling vs split process

Jumlah box yang kamu butuh tergantung gimana kamu atur process-nya:

— **Bundle web + worker dalam satu container** → 1 box. [Caranya](/docs/scaling/bundled-processes).
— **Split jadi process type terpisah** → N box, scaling independen.

Pilih bundled buat app kecil; pilih split buat production yang web dan worker-nya mau scale beda rate.

## Self-hosted

Wokku Community Edition nggak punya sistem tier. Kamu manage resource langsung di server — pilih batas memory container di Dokku setup sesuai mau kamu.
