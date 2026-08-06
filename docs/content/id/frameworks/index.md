# Deploy Berdasarkan Framework

Panduan langkah demi langkah untuk men-deploy framework favoritmu ke Wokku.
Setiap panduan membawamu dari proyek kosong sampai URL live — lengkap dengan
database, environment variable, dan domain kustom.

Semua panduan mengasumsikan kamu sudah punya [akun Wokku](/docs/getting-started/sign-up),
[server yang terhubung](/docs/getting-started/connect-server), dan
[SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`.

## Pilih framework-mu

**JavaScript / TypeScript**
- **[Next.js](/docs/frameworks/nextjs)** — React, server-rendered atau statis
- **[Nuxt](/docs/frameworks/nuxt)** — Vue, server Nitro
- **[Astro](/docs/frameworks/astro)** — statis atau SSR
- **[Node.js / Express](/docs/frameworks/nodejs)** — server HTTP Node apa pun

**Python**
- **[Django](/docs/frameworks/django)** — dengan `migrate` + `collectstatic`
- **[Flask](/docs/frameworks/flask)** — Gunicorn
- **[FastAPI](/docs/frameworks/fastapi)** — worker Uvicorn

**Lainnya**
- **[Laravel](/docs/frameworks/laravel)** — PHP, dengan `artisan migrate` saat release
- **[Ruby on Rails](/docs/frameworks/rails)** — dengan migration + precompile aset
- **[Go](/docs/frameworks/go)** — di-compile jadi satu binary
- **[Phoenix](/docs/frameworks/phoenix)** — Elixir, dengan migration Ecto
- **[Situs Statis](/docs/frameworks/static)** — HTML/CSS/JS atau output build apa pun

Tidak menemukan framework-mu? Hampir semua aplikasi di-deploy dengan cara yang
sama: push repo yang punya `Procfile` (atau `Dockerfile`) dan Wokku akan
mem-build-nya. Lihat [Deploy](/docs/apps/deploy) untuk alur umumnya.

## Cara kerja deployment

Wokku mem-build aplikasimu di server-mu begitu kamu `git push`, memakai
[Cloud Native Buildpacks](https://buildpacks.io) untuk sebagian besar bahasa
(terdeteksi otomatis dari `composer.json`, `package.json`, `requirements.txt`,
`go.mod`, dll.) atau `Dockerfile` milikmu sendiri jika kamu menyediakannya.
Tidak perlu konfigurasi build untuk kasus umum.

:::callout note
Tidak mau setel apa pun manual? [Galeri template](/docs/templates/browse)
sekali-klik men-deploy 130+ aplikasi, dan **starter** framework memberimu repo
yang sudah siap-Wokku — clone, push, selesai.
:::
