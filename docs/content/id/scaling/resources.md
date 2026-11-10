---
title: Resource & Ukuran
summary: Pilih CPU dan RAM untuk setiap process dengan slider atau preset, atau biarkan app gratis tetap sleeping.
last_updated: 2026-11-07
---

Di sini kamu akan memilih berapa CPU dan RAM yang didapat setiap process di app kamu. Kamu bayar per resource, per hari. Lihat [Harga](/docs/billing/pricing).

## Ubah ukuran app

:::tabs
::web-ui
1. Buka app kamu → **Runtime** → **Scaling**.
2. Untuk setiap process (`web`, `worker`, …), klik preset atau geser slider **CPU** dan **RAM**. Harga bulanan ikut ter-update saat kamu mengubahnya.
3. Klik **Save resources**. Container akan restart dengan ukuran baru.

::cli
```bash
wokku ps:resize my-app web --cpu 0.5 --memory 1024
```
Isi `--cpu` dan `--memory` sekaligus.

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"resources": {"web": {"cpu": 0.5, "memory_mb": 1024}}}'
```

::mcp
Minta ke Claude: *"Ubah ukuran process web my-app jadi 0.5 vCPU dan 1 GB RAM"*
:::

## Preset

| Preset | CPU | RAM |
|---|---|---|
| Nano | 0.25 vCPU | 256 MB |
| Starter | 0.25 vCPU | 512 MB |
| Standard | 0.5 vCPU | 1 GB |
| Large | 1 vCPU | 2 GB |
| X-Large | 2 vCPU | 4 GB |

Slider berkisar dari 0.25 sampai 4 vCPU (kelipatan 0.25) dan 256 MB sampai 8 GB RAM (kelipatan 256 MB).

:::callout tip
256 MB tidak cukup untuk Rails. Pilih 512 MB atau lebih.
:::

## App sleeping gratis

Opsi **Sleeping (free)** di process `web` tidak dikenakan biaya. Kamu bisa punya 3 app sleeping.

- App sleeping akan tidur setelah 30 menit tanpa request.
- Request berikutnya akan membangunkannya. Response pertama butuh sekitar 30 detik.
- App sleeping hanya menjalankan satu instance.

Butuh app yang selalu nyala? Pilih preset atau ukuran slider apa saja.

## Disk

Kalau app kamu punya persistent volume, slider **Volume disk** (0–100 GB) muncul di halaman yang sama.

## Kapan perubahan ditagih

- Upsize ditagih mulai hari itu. Setiap hari ditagih sesuai ukuran terbesar yang kamu pakai di hari itu.
- Downsize menjadi kredit di invoice berikutnya.
- App yang di-stop dan app sleeping tidak bayar CPU atau RAM. Disk volume tetap ditagih.

## Batas akun baru

Sampai pembayaran pertama kamu, total semua resource kamu dibatasi (default Rp150.000/bulan; halaman Billing menampilkan batas saat ini). Kalau melebihi batas, akan muncul *"That size is over your account limit — add credit on the Billing page to go higher."*

## Database

Ukuran dedicated database diatur dengan cara yang sama, plus disk. Lihat [Buat & hubungkan database](/docs/databases/create-link).

## Lihat juga

- [Scaling Process](/docs/scaling/dynos) — jalankan lebih banyak instance
- [Menggabungkan Process](/docs/scaling/bundled-processes) — beberapa process dalam satu container
