---
title: Ruby on Rails
summary: Jalankan app Rails di Wokku dengan Puma, Postgres, dan migration lewat wokku run.
last_updated: 2026-11-07
---

Tambahkan perintah start Puma, isi master key-mu, push, lalu jalankan migration. Mau repo yang sudah jalan dulu? Deploy starter `rails`, `rails-api`, `rails-sidekiq` atau `rails-tailwind` dari [Templates](/docs/templates/browse).

## Perintah start

```procfile
web: bin/rails server -b 0.0.0.0 -p $PORT
```

Nixpacks mendeteksi Rails dari `Gemfile`-mu dan meng-install gem-nya.

:::callout warning
App Rails 7.1+ sudah menyertakan `Dockerfile`, dan Wokku mem-build-nya kalau ada. Di Rails 8, command default-nya menjalankan Thruster di port 80, yang tidak menerima traffic. Pertahankan baris Procfile di atas (baris ini menggantikan command image), atau hapus Dockerfile-nya supaya di-build dengan Nixpacks.
:::

## Config dan database

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  RAILS_ENV=production RAILS_LOG_TO_STDOUT=true RAILS_SERVE_STATIC_FILES=true
```

Jangan pernah commit `config/master.key`. Add-on Postgres mengisi `DATABASE_URL`, yang dibaca Rails di production. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy dan migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- bin/rails db:migrate
```

Jalankan perintah migrate setiap kali deploy yang menambahkan migration. Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Background job

Tambahkan `worker: bundle exec sidekiq` (atau `bin/jobs` untuk Solid Queue) ke Procfile lalu scale. Sidekiq juga butuh Redis (`wokku addons:shared:enable my-app redis`, yang mengisi `REDIS_URL`). Lihat [Background Worker](/docs/guides/background-workers).

## Troubleshooting

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — `RAILS_MASTER_KEY` salah atau belum diisi.
- **Asset 404** — isi `RAILS_SERVE_STATIC_FILES=true` dan cek [log](/docs/monitoring/logs) build untuk `assets:precompile`. Kalau tidak jalan, build dengan [Dockerfile](/docs/guides/dockerfile).
- **Error blocked host** — tambahkan domain-mu ke `config.hosts`, atau biarkan `config.hosts` kosong di production.
