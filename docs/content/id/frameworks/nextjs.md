# Deploy Next.js

Deploy aplikasi Next.js (server-rendered) ke Wokku, lengkap dengan environment
variable, database, dan HTTPS.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Next.js di lokal (`npx create-next-app@latest my-app` jika mulai dari nol)

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → pilih server, beri nama `my-next-app`, pilih ukuran box, **Create**.

::cli
```bash
wokku apps:create my-next-app --server my-server
```
:::

## 2. Siapkan aplikasi Next.js-mu

Node buildpack mendeteksi Next.js otomatis dari `package.json`. Pastikan ada
script `build` dan `start` (create-next-app sudah menambahkannya):

```json
{
  "scripts": {
    "build": "next build",
    "start": "next start -p $PORT"
  }
}
```

:::callout note
Bind ke `$PORT`, jangan hardcode `3000` — Wokku menetapkan port saat runtime.
`next start -p $PORT` menanganinya.
:::

Tambahkan `Procfile` (opsional tapi eksplisit):

```procfile
web: npm run start
```

Untuk image lebih kecil, aktifkan standalone output di `next.config.js`
(`output: "standalone"`).

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config**. Tambahkan `NODE_ENV=production` dan secret `NEXT_PUBLIC_*` /
sisi-server yang dibutuhkan.

::cli
```bash
wokku config:set my-next-app NODE_ENV=production
```
:::

:::callout warn
Nilai `NEXT_PUBLIC_*` ditanam **saat build time**. Set sebelum deploy, dan
deploy ulang setelah mengubahnya.
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-next-app
```

Wokku menyuntikkan `DATABASE_URL`; baca dari `process.env.DATABASE_URL` di
config Prisma/Drizzle/pg-mu. Lihat [Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-next-app
git push wokku main
```

::github
Hubungkan repo di **Apps → Connect GitHub** untuk auto-deploy tiap push —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-next-app
git push wokku main
```
:::

Live di `https://my-next-app.wokku.app` begitu build selesai.

## Static export?

Jika situsmu tanpa kode server, build static export (`output: "export"`) dan
deploy sebagai situs statis — panduan khususnya segera menyusul. Untuk sekarang,
`next start` (di atas) bekerja untuk SSR maupun aplikasi statis-dengan-server.

## Tambahkan domain kustom

Lihat [Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **Aplikasi crash saat boot** — hampir selalu port di-hardcode. Pakai `-p $PORT`.
- **Env var tidak diterapkan** — `NEXT_PUBLIC_*` bersifat build-time; deploy ulang setelah mengubahnya.
- **Build kehabisan memori** — pilih ukuran box lebih besar untuk build, atau set `NODE_OPTIONS=--max-old-space-size`.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Environment Variables](/docs/apps/config) · [Kesiapan Production](/docs/apps/best-practices)
