# Deploy Astro

Deploy situs Astro ke Wokku — output statis atau server-rendered (SSR).

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Proyek Astro (`npm create astro@latest` jika mulai dari nol)

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-astro-site`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-astro-site --server my-server
```
:::

## 2a. Server-rendered (SSR)

Tambahkan adapter Node supaya Astro mem-build server yang bisa dijalankan:

```bash
npx astro add node
```

```js
// astro.config.mjs
import node from "@astrojs/node";
export default defineConfig({ output: "server", adapter: node({ mode: "standalone" }) });
```

`Procfile`:

```procfile
web: HOST=0.0.0.0 PORT=$PORT node ./dist/server/entry.mjs
```

## 2b. Output statis

Untuk situs sepenuhnya statis (`output: "static"`, default), `astro build`
menghasilkan `dist/`. Sajikan dengan static server kecil:

```text
# package.json
"scripts": { "build": "astro build", "start": "npx serve dist -l $PORT" }
```

```procfile
web: npm start
```

:::callout note
Untuk situs statis ber-traffic tinggi, jalur CDN/static-hosting segera hadir
sebagai recipe khusus. Pendekatan `serve` di atas bekerja hari ini di box mana pun.
:::

## 3. Environment variable

```bash
wokku config:set my-astro-site NODE_ENV=production
```

Env var `PUBLIC_*` di-inline saat build time — set sebelum deploy.

## 4. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-astro-site
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-astro-site
git push wokku main
```
:::

Live di `https://my-astro-site.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **Halaman kosong / crash** — untuk SSR, bind ke `HOST=0.0.0.0 PORT=$PORT`.
- **`PUBLIC_*` tidak diterapkan** — build-time; deploy ulang setelah mengubahnya.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
