# Deploy Nuxt

Deploy aplikasi Nuxt 3 ke Wokku. `nuxt build` menghasilkan server Nitro mandiri
yang kamu jalankan dengan Node.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Nuxt 3 (`npx nuxi init my-app` jika mulai dari nol)

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-nuxt-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-nuxt-app --server my-server
```
:::

## 2. Siapkan aplikasi Nuxt-mu

Node buildpack menjalankan `nuxt build`, yang menghasilkan `.output/`. Jalankan
server Nitro dan arahkan ke `$PORT`:

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

:::callout note
Nitro membaca `PORT` (dan `HOST`) dari environment otomatis, jadi
`node .output/server/index.mjs` bind ke port yang ditetapkan Wokku tanpa flag tambahan.
:::

## 3. Environment variable

:::tabs
::web-ui
Aplikasi → **Config** → tambahkan `NODE_ENV=production` plus runtime config-mu.
Nilai publik (`NUXT_PUBLIC_*`) dibaca saat runtime oleh Nitro; yang privat tetap di sisi server.

::cli
```bash
wokku config:set my-nuxt-app NODE_ENV=production
```
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-nuxt-app
```

Baca `process.env.DATABASE_URL` di server route / ORM-mu. Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-nuxt-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-nuxt-app
git push wokku main
```
:::

Live di `https://my-nuxt-app.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **Crash saat boot** — pastikan kamu menjalankan `.output/server/index.mjs` (bukan `nuxt dev`/`preview`).
- **Build kehabisan memori** — pilih ukuran box lebih besar untuk langkah build.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
