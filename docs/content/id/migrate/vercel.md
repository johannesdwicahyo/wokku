# Migrasi dari Vercel

Vercel menjalankan aplikasimu sebagai serverless/edge function. Wokku
menjalankannya sebagai **container jangka panjang** biasa — artinya tanpa cold
start, tanpa timeout function, dan server sungguhan tempat kamu bisa menaruh
worker dan cron di sebelahnya. Untuk Next.js, perpindahannya mudah.

## Peta konsep

| Vercel | Wokku |
|---|---|
| Serverless / Edge Functions | Satu proses server jangka panjang (`web`) |
| `next start` (terkelola) | `next start -p $PORT` ([panduan Next.js](/docs/frameworks/nextjs)) |
| Environment Variables | Config vars ([config](/docs/apps/config)) |
| Vercel Postgres | Add-on Postgres ([panduan](/docs/guides/postgres-redis)) |
| Vercel KV (Redis) | Add-on Redis |
| Cron Jobs | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Preview Deployments | [PR Previews](/docs/guides/preview-deploys) |
| Custom Domains | [Domain Kustom](/docs/domains-ssl/custom-domains) |

## 1. Jalankan aplikasi sebagai server

Ikuti [panduan Next.js](/docs/frameworks/nextjs): pastikan ada script `build` +
`start` dan `start` bind ke `$PORT`:

```json
{ "scripts": { "build": "next build", "start": "next start -p $PORT" } }
```

API route / server action tetap bekerja — mereka jalan di dalam server ini, bukan
sebagai function terisolasi. Kode khusus **Edge runtime** mungkin perlu pindah ke
Node runtime (`export const runtime = "nodejs"`).

## 2. Salin environment variable

Ekspor dari dashboard Vercel (atau `vercel env pull .env`), lalu:

```bash
wokku apps:create my-app --server my-server
# dari file .env:
while IFS= read -r line; do [ -n "$line" ] && wokku config:set my-app "$line"; done < .env
```

:::callout warn
Nilai `NEXT_PUBLIC_*` ditanam saat **build time** — set di Wokku sebelum deploy
pertama, dan deploy ulang setelah mengubahnya.
:::

## 3. Pindahkan data

- **Vercel Postgres** → `pg_dump` connection string-nya, restore ke add-on
  Postgres Wokku (lihat [ringkasan migrasi](/docs/migrate/index)).
- **Vercel KV** → tambah add-on Redis Wokku dan arahkan ulang `REDIS_URL`.

## 4. Deploy + domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Verifikasi di `my-app.wokku.app`, lalu pindahkan domainmu — lihat
[Domain Kustom](/docs/domains-ssl/custom-domains).

## Gotcha

- **API khusus edge** — `@vercel/edge` / middleware di edge runtime mungkin butuh padanan Node.
- **`/api` sebagai function** — mereka jadi route biasa di satu server; perilaku sama, scaling per-box bukan per-request.
- **Optimasi gambar** — `next/image` bekerja; untuk traffic berat, taruh CDN di depan.

## Langkah berikutnya

- [Panduan Next.js](/docs/frameworks/nextjs) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
