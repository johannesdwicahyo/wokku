---
title: Nuxt
summary: Jalankan app Nuxt di Wokku sebagai Node server Nitro.
last_updated: 2026-11-07
---

`nuxt build` menghasilkan server Nitro yang mandiri di `.output/`. Jalankan, push, dan app-mu langsung live.

## Build dan start

```json
{
  "scripts": {
    "build": "nuxt build",
    "start": "node .output/server/index.mjs"
  }
}
```

```procfile
web: npm start
```

Nitro membaca `PORT` dan `HOST` dari environment, jadi tidak perlu flag apa pun.

## Environment variable

Nuxt meng-override `runtimeConfig` dari variabel `NUXT_*` saat runtime (`NUXT_PUBLIC_*` untuk nilai publik), jadi isi sebagai [config var](/docs/apps/config):

```bash
wokku config:set my-app NODE_ENV=production NUXT_PUBLIC_API_BASE=https://api.example.com
```

## Database (opsional)

```bash
wokku addons:shared:enable my-app postgres
```

Baca `process.env.DATABASE_URL` di server route atau ORM-mu. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crash saat boot** — jalankan `.output/server/index.mjs`, bukan `nuxt dev` atau `nuxt preview`.
- **Situs sepenuhnya statis** — jalankan `nuxt generate` lalu sajikan `.output/public` sebagai [situs statis](/docs/frameworks/static).
