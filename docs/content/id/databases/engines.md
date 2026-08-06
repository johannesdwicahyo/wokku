---
title: Engine yang Didukung
summary: "Lima shared engine gratis (Postgres, Redis, Memcached, RabbitMQ, Meilisearch) tersedia di tiap box, plus empat dedicated engine (Postgres, MySQL, MongoDB, Redis) sebagai upgrade berbayar. Connection URL di-inject otomatis."
eyebrow: database
last_updated: 2026-05-31
---

# Engine yang Didukung

Wokku punya dua kategori engine: **shared** (gratis, multi-tenant, enable per box) dan **dedicated** (upgrade berbayar, container single-tenant). Object storage workspace (MinIO) terpisah dari keduanya.

## Shared engine

Lima engine jalan di shared host container. Kamu pilih mana yang mau di-enable saat bikin box — atau tambah/hapus belakangan dari tab **Settings → Add-ons** box. Nggak perlu provisioning terpisah, nggak perlu nunggu; tenant langsung dibuat.

| Engine | Tipe | Env var URL |
|---|---|---|
| **PostgreSQL** | Relasional | `DATABASE_URL` |
| **Redis** | Key-value / Cache | `REDIS_URL` |
| **Memcached** | Cache | `MEMCACHED_URL` |
| **RabbitMQ** | Message Queue | `RABBITMQ_URL` |
| **Meilisearch** | Full-text Search | `MEILISEARCH_URL` |

> **Batasan Free plan** — Box Free plan cuma lihat Postgres dan Redis di picker addon. Memcached, RabbitMQ, dan Meilisearch tersedia mulai Solo plan ke atas.

### Cara kerja shared tenancy

Tiap shared engine menjalankan satu container per server. Saat kamu enable engine di box, Wokku provision role + namespace per-box (role + database buat Postgres, key prefix buat Redis dan Memcached, virtual host buat RabbitMQ, index namespace buat Meilisearch). Tenant terisolasi; satu box nggak bisa baca data box lain.

`DATABASE_URL` (dan var sejenis) di-inject sebagai env var app dan di-update otomatis kalau shared tenant pernah dimigrasikan. Code app kamu lihat nama env var yang sama, baik engine-nya shared maupun dedicated.

## Dedicated engine

Empat engine bisa di-provision sebagai dedicated container single-tenant. Dedicated engine adalah upgrade berbayar — mengonsumsi satu slot dari kuota plan kamu (3 DB slot + 3 Redis slot per workspace berbayar). Lihat [Dedicated upgrade](/docs/databases/dedicated-upgrade) untuk flow lengkapnya.

| Engine | Tipe | Env var URL | Catatan |
|---|---|---|---|
| **PostgreSQL** | Relasional | `DATABASE_URL` | Migrasi data dari shared Pg saat upgrade |
| **MySQL** | Relasional | `DATABASE_URL` | Fresh-create only (nggak ada shared MySQL) |
| **MongoDB** | Document | `MONGO_URL` | Fresh-create only (nggak ada shared MongoDB) |
| **Redis** | Key-value / Cache | `REDIS_URL` | Migrasi data dari shared Redis saat upgrade |

> Ketiga DB engine (Postgres, MySQL, MongoDB) berbagi **satu pool 3 dedicated DB slot** per workspace. Redis punya pool sendiri sebanyak 3 slot. Size mengikuti box: box medium dapat dedicated engine medium.

### Batas koneksi (dedicated Postgres)

| Plan | Max koneksi |
|---|---|
| Solo | 20 |
| Pro | 80 |
| Team | 160 |

Butuh headroom lebih? Pasang [PgBouncer](https://www.pgbouncer.org/) di depan Postgres — dia multiplex koneksi tanpa perlu ganti `DATABASE_URL`.

## MinIO workspace (object storage)

MinIO bukan addon per-box — ini adalah object storage level workspace yang di-share ke semua box kamu. Tiap paid plan include bucket MinIO; ukurannya tergantung plan (Solo 2 GB / Pro 10 GB / Team 20 GB). Kredensial akses ada di **Workspace → Storage**.

Use case: upload user (avatar, attachment), PDF generated, asset gambar dan video, deploy artefact, arsip log.

> Support MinIO masih early access — pembuatan bucket dan API S3-compatible sudah stabil, tapi dashboard object browser ship di rilis berikutnya.

## Lihat juga

- [Create & Link add-on](/docs/databases/create-link) — enable shared add-on, referensi CLI + API + MCP
- [Dedicated upgrade](/docs/databases/dedicated-upgrade) — kapan dan cara upgrade ke dedicated engine
- [Plan Bundle](/docs/billing/plan-bundles) — apa saja yang included di tiap plan
