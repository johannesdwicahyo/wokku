---
title: Migrasi ke Wokku
summary: Pindahkan app dari platform lain ke Wokku beserta config, database, dan domain-nya.
last_updated: 2026-11-07
---

Buat ulang app-nya, salin config-nya, pindahkan database-nya, lalu alihkan DNS. Pilih platform kamu saat ini untuk detailnya.

## Pilih asal kamu

- **[Heroku](/docs/migrate/heroku)** — app dengan Procfile, config vars, Heroku Postgres
- **[Vercel](/docs/migrate/vercel)** — Next.js dan serverless function
- **[Netlify](/docs/migrate/netlify)** — situs statis dan function
- **[Render](/docs/migrate/render)** — web service, worker, managed Postgres
- **[VPS](/docs/migrate/vps)** — nginx, systemd atau pm2, certbot

## Empat langkahnya

1. **Pastikan app jalan di Wokku.** App harus listen di `$PORT`. Ikuti [panduan framework](/docs/frameworks/index) kamu, lalu buat app-nya ([Create & Deploy](/docs/apps/deploy)).
2. **Salin environment variable** dengan `wokku config:set my-app KEY=VALUE ...` ([Environment Variables](/docs/apps/config)).
3. **Pindahkan database** (lihat di bawah).
4. **Arahkan domain kamu.** Cek semuanya dulu di `https://my-app.wokku.app`, lalu tambahkan domain kamu dan alihkan DNS ([Custom Domains](/docs/domains-ssl/custom-domains)). Downtime hanya selama propagasi DNS.

## Memindahkan database

Import bisa dilakukan di database **dedicated** (Postgres, MySQL, MariaDB, MongoDB). Add-on shared tidak bisa import dump, jadi tambahkan database dedicated untuk proses pindahan ini:

```bash
# 1. Dump from your current provider (Postgres custom format)
pg_dump "$OLD_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

# 2. Add a dedicated Postgres to the app and find its name
wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app

# 3. Import (this overwrites the database)
wokku databases:import <database-name> dump.bin
```

Add-on akan men-set `DATABASE_URL` di app. Hapus `DATABASE_URL` yang kamu salin dari platform lama. Import menerima SQL biasa atau `pg_dump -Fc` untuk Postgres, output `mysqldump` untuk MySQL/MariaDB, dan `mongodump --archive` untuk MongoDB. Lihat [Create & Link a Database](/docs/databases/create-link).

:::callout note
Hentikan penulisan data ke app lama (maintenance mode, atau scale ke nol) sebelum dump terakhir, supaya tidak ada data yang hilang antara dump dan peralihan.
:::
