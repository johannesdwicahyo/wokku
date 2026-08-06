# Migrasi dari VPS Biasa

Menjalankan aplikasimu manual di VPS — nginx, systemd atau pm2, `git pull`
manual, perpanjangan certbot? Wokku tetap memberimu kendali atas server sendiri
tapi mengganti semua glue dengan `git push`.

## Yang digantikan Wokku

| Di VPS-mu sekarang | Di Wokku |
|---|---|
| Unit `systemd` / proses `pm2` | Proses `web` dari `Procfile`-mu |
| Reverse proxy nginx | Routing bawaan ke aplikasimu |
| certbot + cron renewal | SSL otomatis ([SSL](/docs/domains-ssl/ssl)) |
| Script `git pull` + restart | `git push` (build + release + restart) |
| Runtime install manual | Buildpack (otomatis) atau `Dockerfile`-mu |
| `crontab` | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| File `.env` di box | Config vars ([config](/docs/apps/config)) |
| `apt install postgresql` | Add-on Postgres ([panduan](/docs/guides/postgres-redis)) |

## 1. Siapkan aplikasi agar buildpack- atau Docker-ready

- Jika stack standar, tambah `Procfile` dan biarkan buildpack mendeteksinya —
  lihat [panduan framework](/docs/frameworks/index)-mu.
- Jika ada dependency sistem tak biasa, commit `Dockerfile` —
  lihat [Deploy dengan Dockerfile](/docs/guides/dockerfile).

Pastikan aplikasi **listen di `$PORT`**, bukan port tetap di belakang nginx.

## 2. Pindahkan environment-mu

Salin nilai dari `.env` server-mu (atau baris `Environment=` systemd) ke
[config var](/docs/apps/config).

## 3. Pindahkan database

Jika Postgres jalan di VPS:

```bash
# di VPS (atau lewat SSH)
pg_dump "postgres://user:pass@localhost/dbname" --no-owner --no-acl -Fc -f dump.bin

# buat Postgres Wokku + restore
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Pindahkan file upload ke object storage — container Wokku punya disk ephemeral.

## 4. Deploy

```bash
wokku apps:create my-app --server my-server
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## 5. Alihkan DNS

Tambahkan domainmu di Wokku (SSL provisioning otomatis), verifikasi di
`my-app.wokku.app`, lalu arahkan DNS-mu ke Wokku dan matikan box lama setelah
traffic berpindah. Lihat [Domain Kustom](/docs/domains-ssl/custom-domains).

## Gotcha

- **Tulis file lokal** — apa pun yang kamu tulis ke disk (upload, SQLite) harus pindah ke DB atau object storage.
- **Background job dari cron** — ubah jadi proses `worker` atau [Scheduled Tasks](/docs/guides/scheduled-tasks).
- **Port/path di-hardcode** — bind ke `$PORT`; jangan asumsikan nginx ada di depan.

## Langkah berikutnya

- [Deploy dengan Dockerfile](/docs/guides/dockerfile) · [Kesiapan Production](/docs/apps/best-practices)
