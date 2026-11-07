---
title: Framework
summary: Apa saja yang dibutuhkan tiap framework agar jalan di Wokku — perintah start, port, settings, dan migration.
last_updated: 2026-11-07
---

Semua framework di-deploy dengan cara yang sama (`git push`); halaman-halaman ini hanya membahas bagian yang berbeda. Baru kenal Wokku? Mulai dari [Quickstart](/docs/getting-started/first-deploy).

## Pilih framework-mu

| Framework | Panduan | Starter sekali klik |
|---|---|---|
| Astro | [Astro](/docs/frameworks/astro) | `astro` |
| Django | [Django](/docs/frameworks/django) | `django` |
| FastAPI | [FastAPI](/docs/frameworks/fastapi) | `fastapi` |
| Flask | [Flask](/docs/frameworks/flask) | `flask` |
| Go | [Go](/docs/frameworks/go) | `go` |
| Laravel | [Laravel](/docs/frameworks/laravel) | `laravel` |
| Next.js | [Next.js](/docs/frameworks/nextjs) | `nextjs` |
| Node.js / Express | [Node.js](/docs/frameworks/nodejs) | `express` |
| Nuxt | [Nuxt](/docs/frameworks/nuxt) | — |
| Phoenix | [Phoenix](/docs/frameworks/phoenix) | `phoenix` |
| Ruby on Rails | [Rails](/docs/frameworks/rails) | `rails`, `rails-api`, `rails-sidekiq`, `rails-tailwind` |
| Situs statis | [Situs Statis](/docs/frameworks/static) | — |

Starter adalah repo yang sudah jalan dan bisa kamu deploy sekali klik dari [Templates](/docs/templates/browse), atau lewat `wokku deploy <starter> --name my-app`.

## Cara Wokku mem-build app-mu

1. Kalau repo-mu punya `Dockerfile`, Wokku mem-build-nya.
2. Kalau tidak, **Nixpacks** mendeteksi bahasanya dari `package.json`, `requirements.txt`, `Gemfile`, `composer.json`, `go.mod`, `mix.exs` dan sebagainya, lalu mem-build image.

Baris `web:` di `Procfile` menjadi perintah start. Setiap baris lainnya menjadi process type yang bisa kamu [scale](/docs/scaling/dynos) (misalnya `worker:`).

## Aturan yang berlaku untuk semua app

- **Listen di `$PORT`, di `0.0.0.0`.** Wokku mengisi `PORT` dan hanya mengirim traffic ke sana. Port tetap, atau `EXPOSE` di Dockerfile, diabaikan.
- **Tidak ada release phase.** Baris `release:` tidak dijalankan sebelum deploy. Jalankan migration setelah setiap deploy dengan `wokku run`:

  ```bash
  wokku run my-app -- bin/rails db:migrate
  ```

- **Buat perintah Procfile tetap sederhana.** Perintah yang mengandung `'`, `|`, `;` atau `&` berjalan tanpa shell. Taruh perintah gabungan (`a && b`) di sebuah script lalu panggil script itu. Untuk mengisi env var secara inline, tulis `env HOST=0.0.0.0 node server.js`, bukan `HOST=0.0.0.0 node server.js`.
- **Disk-nya sementara.** File yang ditulis saat runtime hilang di deploy atau restart berikutnya. Simpan upload di object storage dan data di [database](/docs/databases/create-link).
- **Config var berlaku saat runtime, bukan saat build.** Nilai yang di-inline framework saat build (`NEXT_PUBLIC_*`, `PUBLIC_*`) harus ada di repo-mu, misalnya di `.env.production` yang di-commit.

## Snippet deploy

Setiap panduan diakhiri dengan tiga perintah yang sama:

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

App-mu live di `https://my-app.wokku.app`. Untuk alur lewat dashboard, auto-deploy GitHub, dan SSH key, lihat [Create & Deploy](/docs/apps/deploy).
