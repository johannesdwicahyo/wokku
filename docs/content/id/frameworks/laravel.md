---
title: Laravel
summary: Jalankan app Laravel di Wokku dengan setup PHP dari Nixpacks (nginx + PHP-FPM) dan Postgres.
last_updated: 2026-11-07
---

Atur app key dan database, push, lalu jalankan migration. Mau repo yang sudah jalan dulu? Deploy starter `laravel` dari [Templates](/docs/templates/browse).

## Build dan start

Nixpacks mendeteksi `composer.json`, meng-install dependency Composer-mu, dan menyajikan `public/` dengan nginx dan PHP-FPM. **Jangan tambahkan baris `web:` di Procfile.** `vendor/bin/heroku-php-apache2` milik Heroku tidak ada di sini, dan app-nya akan crash.

Butuh ekstensi PHP tambahan atau web server kustom? Commit sebuah [Dockerfile](/docs/guides/dockerfile) yang listen di `$PORT`.

## Config

Generate key secara lokal dengan `php artisan key:generate --show`, lalu:

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  APP_KEY="base64:..." APP_ENV=production APP_DEBUG=false \
  APP_URL=https://my-app.wokku.app LOG_CHANNEL=stderr DB_CONNECTION=pgsql
```

## Database

Add-on Postgres mengisi `DATABASE_URL`. Versi Laravel terbaru membaca `DB_URL`, jadi jadikan `DATABASE_URL` sebagai fallback di `config/database.php`:

```php
'pgsql' => [
    'driver' => 'pgsql',
    'url' => env('DB_URL', env('DATABASE_URL')),
    // ...
],
```

Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy dan migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- php artisan migrate --force
```

Jalankan perintah migrate setiap kali deploy yang menambahkan migration. Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **500 saat pertama dibuka** — biasanya karena `APP_KEY` belum diisi. Isi lalu restart (`wokku ps:restart my-app`).
- **Session, cache, atau upload hilang** — disk lokal bersifat sementara. Pakai driver `database` atau `redis` untuk session, cache, dan queue, serta [object storage](/docs/databases/object-storage) untuk file.
- **Queue** — tambahkan `worker: php artisan queue:work` ke Procfile lalu scale. Lihat [Background Worker](/docs/guides/background-workers).
