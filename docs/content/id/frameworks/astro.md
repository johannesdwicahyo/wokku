---
title: Astro
summary: Jalankan situs Astro di Wokku, server-rendered dengan Node adapter atau sebagai output statis.
last_updated: 2026-11-07
---

Pasang Node adapter (atau static server), push, dan situsmu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `astro` dari [Templates](/docs/templates/browse).

## Server-rendered (SSR)

Tambahkan Node adapter dalam mode standalone:

```bash
npx astro add node
```

```js
// astro.config.mjs
import { defineConfig } from "astro/config";
import node from "@astrojs/node";

export default defineConfig({ output: "server", adapter: node({ mode: "standalone" }) });
```

```procfile
web: env HOST=0.0.0.0 node ./dist/server/entry.mjs
```

Server standalone membaca `PORT` sendiri. Pakai `env HOST=…`; prefix `HOST=… node …` tanpa `env` akan gagal di Procfile.

## Output statis

Dengan `output: "static"` default, `astro build` menulis ke `dist/`. Sajikan dengan static server kecil:

```bash
npm install serve
```

```json
"scripts": { "build": "astro build", "start": "serve dist -l $PORT" }
```

```procfile
web: npm start
```

## Environment variable

Variabel `PUBLIC_*` di-inline saat build, dan config var Wokku tidak tersedia selama build. Commit nilainya di `.env.production`. Secret sisi server taruh di [config var](/docs/apps/config):

```bash
wokku config:set my-app NODE_ENV=production
```

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **App crash atau tidak pernah merespons** — untuk SSR, jalankan `dist/server/entry.mjs` dengan `HOST=0.0.0.0`; untuk output statis, sajikan di `$PORT`.
- **Nilai `PUBLIC_*` hilang** — nilainya dipakai saat build; commit lalu deploy ulang.
