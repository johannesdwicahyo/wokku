---
title: Plan Bundle
summary: "Tiap box ship dengan lima shared engine gratis (Postgres, Redis, Memcached, RabbitMQ, Meilisearch) — kamu pilih mana yang di-enable per box. Paid plan tambah kuota dedicated DB dan Redis. Nggak ada add-on store, nggak ada invoice per-resource."
eyebrow: billing
last_updated: 2026-05-31
---

# Plan Bundle

Tiap box Wokku **batteries-included**: lima shared engine tersedia tanpa biaya tambahan, dan kamu pilih mana yang mau di-attach saat bikin box. Nggak ada add-on store dan nggak ada invoice addon terpisah. Paid plan juga include kuota dedicated engine slot buat workload yang sudah outgrow shared tenancy.

## Matrix plan

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| **Harga** | $0 | $5 / Rp 75k/bln | $15 / Rp 225k/bln | $50 / Rp 750k/bln + $3 / Rp 45k per extra seat |
| **Box** | 3 sleeping | 3 sleeping + 3 small | 3 sleeping + 3 medium | 3 sleeping + 3 large |
| **Extra box** | — | — | — | Large ($10/box) atau X-Large ($20/box) |
| **Shared add-on tersedia** | Postgres + Redis only | Semua 5 engine | Semua 5 engine | Semua 5 engine |
| **Kuota dedicated DB** | 0 slot | 3 slot (ukuran small) | 3 slot (ukuran medium) | 3 slot (ukuran large) |
| **Kuota dedicated Redis** | 0 slot | 3 slot (ukuran small) | 3 slot (ukuran medium) | 3 slot (ukuran large) |
| **MinIO workspace** | — | 2 GB | 10 GB | 20 GB |

> "3 DB slot" mencakup **ketiga DB engine gabungan** (Postgres, MySQL, MongoDB). Workspace Pro dengan 2 dedicated Postgres DB + 1 dedicated MySQL sudah pakai semua 3 DB slot.

## Shared add-on: pilih per box

Lima shared engine yang tersedia:

| Engine | Free plan | Solo+ |
|---|---|---|
| PostgreSQL | ✓ | ✓ |
| Redis | ✓ | ✓ |
| Memcached | — | ✓ |
| RabbitMQ | — | ✓ |
| Meilisearch | — | ✓ |

Tiap engine yang kamu enable di box dapat tenant terisolasi sendiri — role + database khusus buat Postgres, key prefix buat Redis dan Memcached, virtual host buat RabbitMQ, index namespace buat Meilisearch. Tenant terisolasi; satu box nggak bisa baca data box lain.

Kamu bisa enable atau disable engine setelah creation dari **box → Settings → Add-ons**. Engine yang di-disable menyimpan data selama 24 jam sebelum tenant dibersihkan.

## Dedicated engine slot

Saat shared tenant nggak cukup lagi — kamu hit size cap, butuh full admin access, atau mau share DB lintas beberapa box — kamu bisa upgrade ke dedicated container single-tenant. Upgrade mengonsumsi satu slot dari kuota kamu.

Ketiga DB engine (Postgres, MySQL, MongoDB) berbagi pool 3 slot yang sama. Redis punya pool 3 slot sendiri.

**Size ngikutin box**: box medium dapat dedicated engine medium. Untuk dapat engine yang lebih besar, resize box-nya dulu.

Lihat [Dedicated upgrade](/docs/databases/dedicated-upgrade) untuk flow migrasi lengkapnya.

## Extra box (Team plan only)

Hanya workspace Team plan yang bisa beli extra box di luar 3 sleeping + 3 large yang sudah included:

- **Large** — $10 / Rp 150k per box per bulan
- **X-Large** — $20 / Rp 300k per box per bulan

Free, Solo, dan Pro hanya bayar harga plan flat dan nggak bisa tambah extra box.

## MinIO workspace

MinIO adalah object storage level workspace — bukan add-on per-box. Tiap paid plan include shared bucket; ukurannya naik sesuai plan. Kredensial ada di **Workspace → Storage**.

> MinIO masih early access. Pembuatan bucket dan API S3-compatible sudah stabil; dashboard object browser ship di rilis berikutnya.

## Kenapa di-bundle?

Model billing per-add-on yang dipakai Heroku marketplace atau Vercel integration memang kerja, tapi bikin masalah:

- Kamu berakhir dengan 5+ line item di tiap invoice.
- Biaya compound: DB kecil + Redis kecil + search engine kecil bisa 3× biaya compute kamu.
- Kamu habis waktu pilih tier lintas banyak provider, dan mereka nggak scale bareng.

Model Wokku: compute + cache + DB + search + queue, semua included di harga plan dan ukurannya di-set sebagai set yang koheren. Box medium di Pro plan cocok sama dedicated engine medium — kamu nggak hit satu cap sebelum yang lain.

## Lewat shared cap

Kalau shared engine tenant hit batas size-nya:

- **Postgres** — Write di-block dengan grace period 24 jam; row lama tetap readable. `SharedDatabaseQuotaJob` warning di 80%.
- **Redis** — LRU eviction jalan (key terlama di-drop dulu), atau `NOEVICTION` return error, tergantung `maxmemory-policy` kamu.
- **Memcached** — Entry di-evict secara normal (Memcached selalu LRU).
- **RabbitMQ** — Pesan baru di-reject saat batas queue depth vhost tercapai.
- **Meilisearch** — Indexing return error saat batas size index tercapai; data yang sudah di-index tetap bisa di-search.

Fix yang bener biasanya upgrade ke dedicated engine (bebas shared slot) atau pindah ke plan lebih tinggi (ukuran dedicated lebih besar).

## Self-hosted

Community Edition nggak punya sistem bundle — kamu manage Postgres, Redis, dan engine lain langsung via setup Dokku kamu. Nggak ada cap, nggak ada kuota.

## Lihat juga

- [Plan & Harga](/docs/billing/plans) — harga tiap plan dan cara kerja seat
- [Engine yang didukung](/docs/databases/engines) — semua 5 shared + 4 dedicated engine
- [Create & Link add-on](/docs/databases/create-link) — enable shared add-on, referensi CLI/API/MCP
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — flow upgrade, kuota, sizing, rollback
- [Usage](/docs/billing/usage) — tile utilization live per workspace
