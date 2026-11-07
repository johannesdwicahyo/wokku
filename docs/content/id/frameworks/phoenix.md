---
title: Phoenix
summary: Jalankan app Phoenix (Elixir) di Wokku sebagai Mix release yang di-build dari Dockerfile.
last_updated: 2026-11-07
---

Generate Dockerfile release, isi secret-mu, push, lalu jalankan migration. Mau repo yang sudah jalan dulu? Deploy starter `phoenix` dari [Templates](/docs/templates/browse).

## Build dengan Dockerfile

Phoenix meng-generate Dockerfile production, sebuah release, dan script `bin/server` / `bin/migrate`:

```bash
mix phx.gen.release --docker
```

Commit file-file hasil generate. Wokku mem-build `Dockerfile` dan menjalankan `CMD`-nya (`/app/bin/server`). Kamu tidak perlu Procfile.

## Config runtime

`config/runtime.exs` hasil generate sudah membaca `PORT`, `DATABASE_URL`, `SECRET_KEY_BASE` dan `PHX_HOST`. `bin/server` mengisi `PHX_SERVER=true`, jadi endpoint-nya ikut start.

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  PHX_HOST=my-app.wokku.app
```

Add-on Postgres mengisi `DATABASE_URL`. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy dan migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- /app/bin/migrate
```

Jalankan perintah migrate setiap kali deploy yang menambahkan migration. Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Domain kustom

Setelah kamu menambahkan [domain kustom](/docs/domains-ssl/custom-domains), isi `PHX_HOST` dengan domain itu lalu restart: `wokku ps:restart my-app`.

## Troubleshooting

- **App boot tapi tidak pernah merespons** — cek apakah `runtime.exs` bind `PORT` di semua interface dan `PHX_SERVER=true` sudah diisi (start dengan `bin/server`).
- **`SECRET_KEY_BASE` tidak ada** — generate dengan `mix phx.gen.secret` lalu isi.
- **Error origin WebSocket/LiveView** — `PHX_HOST` harus sama dengan hostname yang kamu buka.
