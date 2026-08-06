# Migrasi dari Heroku

Wokku adalah hal paling mirip Heroku yang bisa kamu jalankan di server sendiri —
`Procfile` sama, buildpack sama, deploy `git push` sama, config var dan add-on
sama. Sebagian besar aplikasi pindah **tanpa perubahan kode**.

## Peta konsep

| Heroku | Wokku |
|---|---|
| Dyno | Box |
| CLI `heroku` | CLI `wokku` |
| Config vars | Config vars ([config](/docs/apps/config)) |
| `Procfile` | `Procfile` (identik) |
| Buildpack | Buildpack (terdeteksi otomatis) |
| Heroku Postgres | Add-on Postgres ([panduan](/docs/guides/postgres-redis)) |
| Heroku Data for Redis | Add-on Redis |
| Heroku Scheduler | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Review Apps | [PR Previews](/docs/guides/preview-deploys) |
| `heroku releases` / rollback | [Releases / rollback](/docs/guides/rollback) |
| `heroku run` | `wokku run` |

## 1. Ekspor config Heroku-mu

```bash
heroku config -s -a my-heroku-app > heroku.env
```

## 2. Buat aplikasi Wokku + impor config

```bash
wokku apps:create my-app --server my-server
# impor tiap baris KEY=VALUE:
while IFS= read -r line; do wokku config:set my-app "$line"; done < heroku.env
```

Buang var internal Heroku yang tak perlu (mis. `DATABASE_URL` lama — Wokku
men-set miliknya sendiri saat kamu menambah database di bawah).

## 3. Pindahkan database

```bash
# ambil dump dari Heroku
heroku pg:backups:capture -a my-heroku-app
heroku pg:backups:download -a my-heroku-app   # -> latest.dump

# buat Postgres Wokku + restore
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" latest.dump
```

## 4. Deploy

`Procfile`-mu sudah bekerja. Tinggal tambahkan remote dan push:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Jika kamu memakai fase `release:` di Heroku untuk migration, ia berjalan sama di Wokku.

## 5. Alihkan domain

Tambahkan domainmu di Wokku (SSL otomatis), verifikasi aplikasi di
`my-app.wokku.app`, lalu arahkan ulang DNS. Lihat [Domain Kustom](/docs/domains-ssl/custom-domains).

## Gotcha

- **Filesystem ephemeral** — sama seperti Heroku; jangan simpan upload di disk. Pakai object storage.
- **`DATABASE_URL`** — biarkan add-on Wokku men-set-nya; hapus yang diimpor dari Heroku.
- **Nama env var add-on** — add-on Heroku menyuntikkan nama var-nya sendiri; arahkan aplikasimu ke `DATABASE_URL` / `REDIS_URL` Wokku.

## Langkah berikutnya

- [Background Worker](/docs/guides/background-workers) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
