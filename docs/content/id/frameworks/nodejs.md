# Deploy Node.js / Express

Deploy server HTTP Node apa pun (Express, Fastify, Koa, Hono, `http` biasa) ke Wokku.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Node dengan `package.json`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-node-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-node-app --server my-server
```
:::

## 2. Siapkan aplikasimu

Node buildpack membaca `package.json`. Sediakan script `start` dan listen di
`process.env.PORT`:

```json
{
  "scripts": { "start": "node server.js" },
  "engines": { "node": ">=20" }
}
```

```js
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`listening on ${port}`));
```

:::callout warn
Selalu bind ke `process.env.PORT`. Port yang di-hardcode adalah penyebab nomor 1
aplikasi Node jalan di lokal tapi crash di Wokku.
:::

Opsional, kunci perintah start dengan `Procfile`:

```procfile
web: npm start
```

## 3. Environment variable

:::tabs
::web-ui
Aplikasi → **Config** → tambahkan `NODE_ENV=production` dan secret-mu.

::cli
```bash
wokku config:set my-node-app NODE_ENV=production
```
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-node-app
```

Baca `process.env.DATABASE_URL` di client `pg`/Prisma/Drizzle-mu. Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-node-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-node-app
git push wokku main
```
:::

Live di `https://my-node-app.wokku.app`.

## Tambahkan domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **Crash saat boot** — port di-hardcode. Pakai `process.env.PORT`.
- **`npm ci` gagal** — commit `package-lock.json`-mu.
- **Versi Node salah** — kunci via `"engines": { "node": ... }`.

## Langkah berikutnya

- [Background worker](/docs/scaling/bundled-processes) · [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
