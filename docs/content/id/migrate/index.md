# Migrasi ke Wokku

Pindah dari platform lain? Panduan ini memetakan konsep tiap platform ke Wokku
dan memandumu melakukan perpindahan — aplikasi, environment, database, dan
domain — dengan downtime sesedikit mungkin.

## Pilih sumbermu

- **[Dari Heroku](/docs/migrate/heroku)** — paling mirip: Procfile, buildpack, add-on, `git push`
- **[Dari Vercel](/docs/migrate/vercel)** — Next.js dan serverless → container jangka panjang
- **[Dari Netlify](/docs/migrate/netlify)** — situs statis + functions
- **[Dari Render](/docs/migrate/render)** — web service, DB terkelola, cron job
- **[Dari VPS biasa](/docs/migrate/vps)** — gantikan nginx + systemd + deploy manual + certbot

## Bentuk umum sebuah migrasi

Apa pun asalmu, perpindahannya sama — empat langkah:

1. **Buat ulang aplikasi** di Wokku ([buat aplikasi](/docs/apps/create))
2. **Salin environment variable** ([config](/docs/apps/config))
3. **Pindahkan database** — `pg_dump` dari provider lama, restore ke add-on
   [Postgres Wokku](/docs/guides/postgres-redis)
4. **Arahkan domain** — tambahkan dengan SSL otomatis, lalu alihkan DNS
   ([domain kustom](/docs/domains-ssl/custom-domains))

:::callout note
Deploy ke URL sementara `*.wokku.app` dulu dan verifikasi semuanya berjalan.
Baru alihkan DNS domain aslimu setelah puas — itu menjaga downtime hanya seputar
jendela propagasi DNS.
:::

## Pindah database, ringkas

```bash
# 1. Dump dari provider-mu saat ini (format custom)
pg_dump "$OLD_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

# 2. Buat database Wokku dan baca URL-nya
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL

# 3. Restore ke Wokku
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Tiap panduan di bawah mengulang ini dengan catatan spesifik per provider.
