# Deploy Laravel

Deploy aplikasi Laravel ke Wokku dengan Postgres, jalankan migration di setiap
release, dan live di HTTPS — dalam hitungan menit.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) di **Profile → SSH Keys** (untuk `git push`)
- Aplikasi Laravel di lokal (`composer create-project laravel/laravel my-app` jika mulai dari nol)

## 1. Buat aplikasi

:::tabs
::web-ui
1. Buka **Apps → New App**
2. Pilih server dan beri nama (mis. `my-laravel-app`)
3. Pilih ukuran box lalu klik **Create**

::cli
```bash
wokku apps:create my-laravel-app --server my-server
```
:::

## 2. Siapkan aplikasi Laravel-mu

Tambahkan `Procfile` di root proyek supaya Wokku tahu cara menyajikan aplikasi
dan menjalankan migration di tiap deploy:

```procfile
web: vendor/bin/heroku-php-apache2 public/
release: php artisan migrate --force
```

Buildpack mendeteksi Laravel otomatis dari `composer.json` dan meng-install
dependency PHP + Composer. Proses `release` berjalan **setelah build sukses,
sebelum traffic dialihkan** — jadi migration diterapkan tanpa downtime.

## 3. Set environment variable

Laravel minimal butuh app key dan env production. Generate key di lokal dengan
`php artisan key:generate --show`, lalu:

:::tabs
::web-ui
Buka aplikasimu → **Config** dan tambahkan:

| Key | Value |
|---|---|
| `APP_KEY` | `base64:...` (dari `key:generate --show`) |
| `APP_ENV` | `production` |
| `APP_DEBUG` | `false` |

::cli
```bash
wokku config:set my-laravel-app \
  APP_KEY="base64:..." APP_ENV=production APP_DEBUG=false
```
:::

Lihat [Environment Variables](/docs/apps/config) untuk referensi lengkap.

## 4. Tambahkan database

Buat database Postgres dan link — Wokku menyuntikkan `DATABASE_URL` otomatis.
Arahkan Laravel ke sana dengan `DB_CONNECTION=pgsql` (Laravel versi baru membaca
`DATABASE_URL` secara native).

:::tabs
::web-ui
Aplikasi → **Resources → Add-ons**, pilih **Postgres**, lalu link ke aplikasi.

::cli
```bash
wokku addons:create postgres my-laravel-app
wokku config:set my-laravel-app DB_CONNECTION=pgsql
```
:::

Detail di [Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
Salin git remote dari halaman overview aplikasimu, lalu:

```bash
git remote add wokku git@git.wokku.cloud:my-laravel-app
git push wokku main
```

::github
Hubungkan repo di **Apps → Connect GitHub** dan setiap push ke deploy branch
otomatis live. Lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-laravel-app
git push wokku main
```
:::

Pantau build streaming di logs. Begitu selesai, aplikasimu live di
`https://my-laravel-app.wokku.app`.

## 6. Tambahkan domain kustom

Arahkan domain milikmu dan Wokku menyediakan SSL otomatis — lihat
[Domain Kustom](/docs/domains-ssl/custom-domains).

## Troubleshooting

- **500 saat pertama dibuka** — biasanya `APP_KEY` belum di-set. Set (langkah 3) lalu deploy ulang.
- **Migration tidak jalan** — pastikan baris `release:` ada di `Procfile` dan cek deploy logs.
- **Storage / session** — pakai driver database atau cache untuk session di production; disk lokal bersifat ephemeral.

## Langkah berikutnya

- [Background worker & queue](/docs/scaling/bundled-processes)
- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
