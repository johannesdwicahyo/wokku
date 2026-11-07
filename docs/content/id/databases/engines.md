---
title: Engine yang Didukung
summary: Database dan cache apa saja yang dijalankan Wokku, shared gratis atau dedicated berbayar, dan env var yang didapat app kamu.
last_updated: 2026-11-07
---

Pilih engine dan mode. Wokku membuatnya, menghubungkannya ke app kamu, dan mengatur URL koneksinya sebagai environment variable.

## Engine

| Engine | Shared (gratis) | Dedicated (berbayar) |
|---|---|---|
| PostgreSQL | ✓ | ✓ |
| MariaDB | ✓ | ✓ |
| Redis | ✓ | ✓ |
| MySQL | — | ✓ |
| MongoDB | — | ✓ |

## Shared vs dedicated

| | Shared | Dedicated |
|---|---|---|
| Biaya | Gratis untuk setiap app | Ditagih per resource (CPU, RAM, disk), lihat [Harga](/docs/billing/pricing) |
| Yang kamu dapat | Database sendiri (atau tenant Redis) di server bersama | Container sendiri |
| Ukuran | 100 MB untuk Postgres/MariaDB, 10 MB untuk Redis | Kamu yang pilih: preset Small, Medium, Large atau slider |
| Backup otomatis | Tidak | Setiap malam, lihat [Backup](/docs/databases/backups) |
| Cocok untuk | Side project, prototype, baru mulai | Data production |

Mulai dari shared. Kalau sudah tidak cukup, [upgrade ke dedicated](/docs/databases/create-link#upgrade-to-dedicated). Data kamu ikut pindah.

:::callout note
Shared Redis tidak pernah di-backup. Pakai sebagai cache, atau upgrade ke dedicated Redis kalau isinya data yang perlu kamu simpan.
:::

## Ukuran dedicated

| Preset | Postgres, MySQL, MariaDB, MongoDB | Redis |
|---|---|---|
| Small | 0.25 vCPU · 512 MB RAM · 5 GB disk | 0.25 vCPU · 256 MB RAM · 1 GB disk |
| Medium | 0.5 vCPU · 1 GB RAM · 20 GB disk | 0.25 vCPU · 1 GB RAM · 2 GB disk |
| Large | 1 vCPU · 2 GB RAM · 50 GB disk | 0.5 vCPU · 2 GB RAM · 4 GB disk |

Kamu juga bisa mengatur CPU, RAM, dan disk lewat slider, dan mengubah ukurannya nanti. Disk hanya bisa diperbesar.

## Environment variable

Wokku mengatur variabel berikut di app yang terhubung. Wokku tidak menimpa `DATABASE_URL` yang sudah ada di app kamu.

| Add-on | Env var yang di-set |
|---|---|
| Shared Postgres | `DATABASE_URL` |
| Shared MariaDB | `MARIADB_URL`, plus `DATABASE_URL` (dalam format `mysql2://` yang dibutuhkan Rails) |
| Shared Redis | `REDIS_URL` |
| Dedicated Postgres | `POSTGRES_URL`, plus `DATABASE_URL` |
| Dedicated MySQL | `MYSQL_URL` |
| Dedicated MariaDB | `MARIADB_URL` |
| Dedicated MongoDB | `MONGODB_URL` |
| Dedicated Redis | `REDIS_URL` |

Baca seperti variabel lainnya: `process.env.DATABASE_URL`, `os.environ["DATABASE_URL"]`, `ENV["DATABASE_URL"]`. Kebanyakan framework (Rails, Django dengan `dj-database-url`, Laravel, Prisma) membaca `DATABASE_URL` dengan sendirinya. Lihat [panduan framework](/docs/frameworks/index) kamu.

## Selanjutnya

- [Tambah & hubungkan database](/docs/databases/create-link)
- [Backup & restore](/docs/databases/backups)
