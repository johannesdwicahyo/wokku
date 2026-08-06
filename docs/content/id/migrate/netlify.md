# Migrasi dari Netlify

Netlify hebat untuk situs statis + sedikit function. Di Wokku, build statis
di-deploy via static buildpack, dan Netlify Functions jadi route di server kecil.

## Peta konsep

| Netlify | Wokku |
|---|---|
| Direktori publish statis | [Situs Statis](/docs/frameworks/static) (`Staticfile` / sajikan `dist`) |
| Netlify Functions | Route di server Node ([panduan Node](/docs/frameworks/nodejs)) |
| Build command | Script `build` (Node buildpack) |
| Environment variables | Config vars ([config](/docs/apps/config)) |
| `_redirects` / `_headers` | Routing level-aplikasi / config server |
| Domain kustom + SSL | [Domain Kustom](/docs/domains-ssl/custom-domains) |

## Situs statis murni

Jika tanpa function, ini seluruh migrasinya:

1. Pastikan build-mu menghasilkan folder (mis. `dist`).
2. Sajikan — commit `Staticfile` (`root: dist`) atau tambah script `start` yang
   menyajikan folder itu. Lihat [panduan Situs Statis](/docs/frameworks/static).
3. Deploy:

```bash
wokku apps:create my-site --server my-server
git remote add wokku git@git.wokku.cloud:my-site
git push wokku main
```

## Situs + function

Netlify Functions adalah handler HTTP kecil. Pindahkan ke satu server (mis.
Express) yang menyajikan build statis sekaligus route `/api/*`:

```procfile
web: node server.js
```

Di dalam `server.js`, sajikan folder statis dan mount tiap mantan function
sebagai route. Set secret yang dipakai function sebagai [config var](/docs/apps/config).

## Redirect & header

Terjemahkan aturan `_redirects` / `_headers` ke routing/middleware server-mu
(atau config framework). Fallback SPA (`/* /index.html 200`) jadi route catch-all
yang mengembalikan `index.html`.

## Domain

Tambahkan domainmu (SSL otomatis), verifikasi di `my-site.wokku.app`, lalu
alihkan DNS — lihat [Domain Kustom](/docs/domains-ssl/custom-domains).

## Gotcha

- **Env build** — set `NODE_ENV` dan var `*_PUBLIC`/build-time sebelum deploy.
- **Form handling / identity** — fitur khusus Netlify (Forms, Identity) butuh pengganti level-aplikasi.
- **Media besar** — taruh CDN di depan aplikasi statis untuk traffic tinggi.

## Langkah berikutnya

- [Panduan Situs Statis](/docs/frameworks/static) · [Panduan Node.js](/docs/frameworks/nodejs)
