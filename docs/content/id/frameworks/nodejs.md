---
title: Node.js
summary: Jalankan HTTP server Node apa pun (Express, Fastify, Koa, Hono) di Wokku.
last_updated: 2026-11-07
---

Tambahkan script `start`, listen di `process.env.PORT`, push, dan app-mu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `express` dari [Templates](/docs/templates/browse).

## Script start dan port

Nixpacks meng-install dependency dari lockfile-mu, menjalankan `build` kalau ada, lalu `npm start`:

```json
{
  "scripts": { "start": "node server.js" },
  "engines": { "node": "22.x" }
}
```

```js
const port = process.env.PORT || 3000;
app.listen(port, "0.0.0.0", () => console.log(`listening on ${port}`));
```

Kunci versi Node dengan `engines.node` (atau file `.node-version`). Procfile opsional (`web: npm start`).

## Database (opsional)

```bash
wokku addons:shared:enable my-app postgres
```

Baca `process.env.DATABASE_URL` di `pg`, Prisma, atau Drizzle. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **Crash atau tidak pernah merespons** — port di-hardcode. Pakai `process.env.PORT`.
- **Install gagal** — commit lockfile-mu (`package-lock.json`, `pnpm-lock.yaml`, atau `yarn.lock`).
- **Background job** — tambahkan `worker: node worker.js` ke Procfile lalu scale. Lihat [Background Worker](/docs/guides/background-workers).
