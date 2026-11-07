---
title: Migrasi dari Vercel
summary: Pindahkan app Next.js dari Vercel ke app Wokku yang berjalan terus-menerus.
last_updated: 2026-11-07
---

Di Wokku, app kamu berjalan sebagai satu server yang hidup terus, jadi tidak ada cold start atau function timeout. Untuk Next.js, pindahannya kebanyakan soal config dan DNS.

## Peta konsep

| Vercel | Wokku |
|---|---|
| Serverless / Edge Functions | Route di dalam satu server `next start` |
| Environment Variables | [Environment Variables](/docs/apps/config) |
| Vercel Postgres / Neon | [Add-on Postgres](/docs/databases/create-link) |
| Vercel KV / Upstash Redis | Add-on Redis |
| Cron Jobs | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Preview Deployments | [Preview Deploys](/docs/guides/preview-deploys) |
| Domains | [Custom Domains](/docs/domains-ssl/custom-domains) |

## 1. Jalankan sebagai server

Ikuti [panduan Next.js](/docs/frameworks/nextjs): pertahankan `"build": "next build"` dan `"start": "next start"`. API route dan server action tetap jalan di dalam server itu. Kode yang dikunci ke Edge runtime mungkin perlu `export const runtime = "nodejs"`.

## 2. Salin environment variable

```bash
wokku apps:create my-app
vercel env pull .env.vercel --environment=production
grep -v '^#' .env.vercel | grep -v '^NEXT_PUBLIC_' | grep '=' \
  | sed 's/="\(.*\)"$/=\1/' \
  | while IFS= read -r pair; do wokku config:set my-app "$pair"; done
```

Nilai `NEXT_PUBLIC_*` disisipkan saat build, dan config vars Wokku tidak tersedia saat build. Commit nilai-nilai itu di `.env.production` saja.

## 3. Pindahkan data

- **Postgres** — dump lalu import ke database dedicated di Wokku. Lihat [Memindahkan database](/docs/migrate/index).
- **Redis/KV** — `wokku addons:shared:enable my-app redis` akan men-set `REDIS_URL`. Salin datanya hanya kalau itu bukan cache.

## 4. Deploy dan pindahkan domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Cek `https://my-app.wokku.app`, lalu pindahkan domain kamu. Lihat [Custom Domains](/docs/domains-ssl/custom-domains).

## Hal yang perlu diperhatikan

- **Edge middleware dan package `@vercel/*`** — API yang khusus Vercel perlu padanan di Node.
- **Scaling** — yang kamu scale adalah process dan [resources](/docs/scaling/resources), bukan function per request.
- **Vercel Cron** — buat ulang setiap cron di `vercel.json` sebagai [scheduled task](/docs/guides/scheduled-tasks).
