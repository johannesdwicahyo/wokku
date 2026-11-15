---
title: Migrasi dari Heroku
summary: Pindahkan app Heroku ke Wokku beserta config vars, data Postgres, dan domain-nya.
last_updated: 2026-11-07
---

Kebanyakan app Heroku sudah listen di `$PORT` dan punya Procfile, jadi pindahannya cuma soal config, data, dan DNS. Ada dua perbedaan penting: Wokku build pakai Dockerfile kamu atau Nixpacks (bukan buildpack), dan tidak ada release phase.

## Peta konsep

| Heroku | Wokku |
|---|---|
| `heroku` CLI | `wokku` CLI ([install](/docs/cli/install)) |
| Buildpack | `Dockerfile` kamu, atau deteksi otomatis Nixpacks |
| `Procfile` | `Procfile` (`web:` dan process type lain) |
| `release:` phase | Tidak ada. Jalankan `wokku run my-app -- <migrate>` setelah deploy |
| Dyno formation | [Scaling Processes](/docs/scaling/dynos) (`wokku ps:scale`) |
| Ukuran dyno | [Resources](/docs/scaling/resources) (CPU dan RAM) |
| Config vars | [Environment Variables](/docs/apps/config) |
| Heroku Postgres / Redis | [Add-on database](/docs/databases/create-link) |
| Heroku Scheduler | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Review Apps | [Preview Deploys](/docs/guides/preview-deploys) |
| `heroku rollback` | [Rollback](/docs/guides/rollback) |
| `heroku run` | `wokku run my-app -- <command>` |

## 1. Buat app dan salin config

```bash
wokku apps:create my-app
heroku config --json -a my-heroku-app \
  | jq -r 'to_entries[] | select(.key != "DATABASE_URL" and .key != "REDIS_URL") | "\(.key)=\(.value)"' \
  | while IFS= read -r pair; do wokku config:set my-app "$pair"; done
```

Perintah ini melewati `DATABASE_URL` dan `REDIS_URL`, karena keduanya di-set oleh add-on Wokku. Hapus juga variabel untuk add-on Heroku yang tidak akan kamu pakai.

## 2. Pindahkan database

```bash
heroku pg:backups:capture -a my-heroku-app
heroku pg:backups:download -a my-heroku-app        # writes latest.dump

wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                                # note the database name
wokku databases:import <database-name> latest.dump
```

Pakai Heroku Redis? `wokku addons:shared:enable my-app redis` akan men-set `REDIS_URL`. Selengkapnya di [Memindahkan database](/docs/migrate/index).

## 3. Deploy

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Kalau Procfile kamu punya baris `release:`, hapus baris itu dan jalankan perintahnya setelah setiap deploy, misalnya `wokku run my-app -- bin/rails db:migrate`.

## 4. Pindahkan domain

Cek app di `https://my-app.wokku.app`, lalu tambahkan domain kamu (HTTPS otomatis) dan perbarui DNS. Lihat [Custom Domains](/docs/domains-ssl/custom-domains).

## Hal yang perlu diperhatikan

- **Perintah khusus buildpack** — baris Procfile seperti `heroku-php-apache2` tidak ada di sini. Lihat [panduan framework](/docs/frameworks/index) kamu.
- **Disk sementara** — sama seperti Heroku. Simpan upload di object storage.
- **Nama variabel add-on** — arahkan app kamu ke `DATABASE_URL` / `REDIS_URL`, bukan nama add-on Heroku seperti `HEROKU_POSTGRESQL_*`.
