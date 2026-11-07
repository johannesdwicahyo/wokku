---
title: Next.js
summary: Jalankan app Next.js server-rendered di Wokku dengan next start.
last_updated: 2026-11-07
---

Pertahankan script `build` dan `start` standar, push, dan app-mu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `nextjs` dari [Templates](/docs/templates/browse).

## Build dan start

Nixpacks mendeteksi Next.js dari `package.json`, menjalankan `npm run build`, lalu `npm start`. `create-next-app` sudah menyertakan kedua script itu:

```json
{
  "scripts": {
    "build": "next build",
    "start": "next start"
  }
}
```

`next start` membaca `PORT` dari environment, jadi kamu tidak perlu `-p`. Procfile opsional (`web: npm start`).

## Environment variable

Nilai `NEXT_PUBLIC_*` di-inline oleh `next build`, dan config var Wokku tidak tersedia selama build. Commit nilai publik di `.env.production`. Secret yang hanya untuk server taruh di [config var](/docs/apps/config) dan dibaca saat runtime:

```bash
wokku config:set my-app NODE_ENV=production
```

## Database (opsional)

```bash
wokku addons:shared:enable my-app postgres
```

Baca `process.env.DATABASE_URL` di Prisma, Drizzle, atau `pg`. Untuk migration Prisma, jalankan `wokku run my-app -- npx prisma migrate deploy` setelah deploy. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Static export

Situs tanpa kode server (`output: "export"`) di-build ke `out/`. Sajikan seperti yang dijelaskan di [Situs Statis](/docs/frameworks/static).

## Troubleshooting

- **Crash saat boot** — ada `-p 3000` yang di-hardcode. Hapus, atau pakai `-p $PORT`.
- **Nilai `NEXT_PUBLIC_*` hilang** — nilainya dipakai saat build; commit lalu deploy ulang.
