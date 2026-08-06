# Tambah Postgres + Redis

Wire database dan cache ke satu aplikasi. Wokku menyediakan tiap add-on dan
menyuntikkan URL koneksi sebagai config var otomatis.

## 1. Tambah Postgres

:::tabs
::web-ui
Aplikasi → **Resources → Add-ons** → **Postgres** → pilih **Shared** (gratis,
termasuk) atau **Dedicated** (berbayar) → link ke aplikasi.

::cli
```bash
wokku addons:create postgres my-app
```
:::

Ini men-set `DATABASE_URL` di aplikasimu. Baca langsung:

```text
DATABASE_URL=postgres://user:pass@host:5432/dbname
```

## 2. Tambah Redis

:::tabs
::web-ui
Aplikasi → **Resources → Add-ons** → **Redis** → link ke aplikasi.

::cli
```bash
wokku addons:create redis my-app
```
:::

Ini men-set `REDIS_URL`.

## 3. Baca di aplikasimu

| Bahasa | Pola |
|---|---|
| Node | `process.env.DATABASE_URL` / `process.env.REDIS_URL` |
| Python | `os.environ["DATABASE_URL"]` / `os.environ["REDIS_URL"]` |
| Ruby | `ENV["DATABASE_URL"]` / `ENV["REDIS_URL"]` |
| Go | `os.Getenv("DATABASE_URL")` |

Sebagian besar framework (Rails, Django via `dj-database-url`, Laravel, Prisma)
membaca `DATABASE_URL` secara native. Lihat [panduan framework](/docs/frameworks/index)-mu.

## 4. Verifikasi koneksi

```bash
wokku config my-app | grep -E "DATABASE_URL|REDIS_URL"
```

Buka shell atau console untuk tes live:

```bash
wokku run my-app -- bin/rails dbconsole     # contoh
```

## Shared vs Dedicated

- **Shared** (tier gratis): tenant di cluster bersama dengan batas ukuran. Cocok
  untuk proyek sampingan dan memulai.
- **Dedicated** (berbayar): instance terisolasi dengan resource lebih besar.
  Upgrade kapan saja — lihat [Dedicated Upgrade](/docs/databases/dedicated-upgrade).

## Troubleshooting

- **`DATABASE_URL` kosong** — add-on harus **di-link** ke aplikasi, bukan sekadar dibuat.
- **Error SSL ke Postgres** — tambahkan `?sslmode=require` (atau padanan driver-mu) jika client-mu butuh TLS.
- **Kena batas ukuran** — tenant shared punya kuota; upgrade ke dedicated.

## Langkah berikutnya

- [Backup](/docs/databases/backups) · [Engine yang Didukung](/docs/databases/engines)
