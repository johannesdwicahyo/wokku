---
title: Pemberitahuan Beta
summary: Wokku Cloud sedang dalam tahap public beta. Ini artinya untuk app kamu, dan cara melaporkan masalah.
last_updated: 2026-11-07
---

Wokku Cloud sedang dalam tahap **public beta** dan belum ditujukan untuk workload production.

## Apa arti beta

- Platform ini sudah bisa dipakai untuk proyek sungguhan, tapi bug dan gangguan singkat bisa terjadi saat kami merilis update.
- Belum ada SLA uptime.
- API-nya `v1`. Kami mungkin menambah field, tapi kami berusaha tidak merusak field yang sudah ada.

## Cocok untuk saat ini

- Side project, demo, dan portofolio
- Tool internal
- Environment staging dan preview
- Mencoba Wokku sebelum kamu memindahkan workload yang lebih besar

Tunda dulu untuk app yang krusial bagi pendapatan, app dengan kebutuhan uptime ketat, dan data yang sensitif terhadap kepatuhan (compliance).

## Yang bisa kamu andalkan

- **Data kamu milik kamu.** Kamu bisa [mengunduh backup database](/docs/databases/backups) dan pergi kapan saja. Kode kamu tetap ada di repo git kamu sendiri.
- **Harga yang jelas.** Kamu hanya membayar resource yang kamu jalankan. Sampai 3 app sleeping gratis. Lihat [Harga](/docs/billing/pricing).
- **Keamanan dasar.** Trafik dilayani lewat HTTPS, dan backup database dienkripsi.

Simpan salinan sendiri untuk apa pun yang tidak boleh hilang.

## Laporkan masalah

Kirim email ke [support@wokku.cloud](mailto:support@wokku.cloud). Sertakan nama app kamu dan apa yang kamu lihat. Link **Support** di bagian bawah sidebar dashboard membuka alamat yang sama.
