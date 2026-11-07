---
title: Migrasi dari Netlify
summary: Pindahkan situs statis Netlify, beserta function-nya, ke Wokku.
last_updated: 2026-11-07
---

Situs yang murni statis bisa pindah dalam beberapa menit. Netlify Functions jadi route di sebuah server Node kecil.

## Peta konsep

| Netlify | Wokku |
|---|---|
| Publish directory | [Static Site](/docs/frameworks/static) (`Staticfile`, atau serve `dist`) |
| Build command | Script `build` di `package.json` |
| Netlify Functions | Route di [server Node](/docs/frameworks/nodejs) |
| Environment variables | [Environment Variables](/docs/apps/config) (hanya saat runtime) |
| `_redirects` / `_headers` | Routing dan middleware di server kamu |
| Domain dan HTTPS | [Custom Domains](/docs/domains-ssl/custom-domains) |

## Situs statis

1. Tanpa build step: tambahkan `Staticfile`. Dengan build step: serve folder output-nya pakai `serve`. Lihat [Static Site](/docs/frameworks/static).
2. Deploy:

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## Situs dengan function

Pindahkan setiap function ke satu server (Express, Hono, dll.) yang men-serve situs hasil build dan memasang tiap function di bawah `/api/...`:

```procfile
web: node server.js
```

Set secret yang dipakai function sebagai [config vars](/docs/apps/config).

## Redirect dan header

Buat ulang aturan `_redirects` dan `_headers` sebagai route dan middleware di server kamu. Aturan SPA `/* /index.html 200` jadi route catch-all, atau `serve -s` untuk situs statis.

## Pindahkan domain

Cek `https://my-app.wokku.app`, lalu tambahkan domain kamu (HTTPS otomatis) dan perbarui DNS. Lihat [Custom Domains](/docs/domains-ssl/custom-domains).

## Hal yang perlu diperhatikan

- **Variabel saat build** — config vars Wokku tidak tersedia saat build. Commit nilai build yang publik (misalnya di `.env.production`).
- **Netlify Forms dan Identity** — keduanya tidak punya padanan di Wokku; ganti di app kamu.
