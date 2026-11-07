---
title: Buat & Deploy
summary: Buat app, push kode kamu dengan git, dan dapatkan URL live di my-app.wokku.app.
last_updated: 2026-11-07
---

Kamu akan membuat app, menambahkan SSH key sekali saja, lalu `git push` untuk deploy.

## 1. Buat app

:::tabs
::web-ui
1. Buka **Apps → + New app**.
2. Masukkan nama, misalnya `my-app`.
3. Atur **Resources** (slider CPU dan RAM, atau preset). Biarkan di ukuran gratis untuk app hobi.
4. Opsional: centang add-on shared (Postgres, MariaDB, Redis) atau pilih database dedicated.
5. Klik **Create App**.

::cli
```bash
wokku apps:create my-app
# with a free shared Postgres and Redis:
wokku apps:create my-app --shared postgres,redis
# with a dedicated database:
wokku apps:create my-app --dedicated-db postgres
```

Flag lainnya: `--branch BRANCH` (default `main`), `--dedicated-redis`.

::api
API butuh `server_id`. Ambil dari `GET /api/v1/servers`, lalu:

```bash
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": "SERVER_ID", "deploy_branch": "main"}'
```

Response-nya menyertakan `git_remote` dan `push_instructions`.

::mcp
Minta ke Claude: *"Buat app bernama my-app dengan Postgres shared."*
:::

Nama app memakai huruf kecil, angka, dan tanda hubung, dan harus diawali huruf.

## 2. Tambahkan SSH key kamu (sekali saja)

Git push diautentikasi dengan SSH key kamu.

```bash
wokku ssh-keys:add --name laptop          # uploads ~/.ssh/id_ed25519.pub
```

Atau tempel di **Profile → SSH Keys**. Lihat [SSH Keys](/docs/apps/ssh-keys).

## 3. Push kode kamu

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Remote dan perintah push juga ada di tab **Deploy** app kamu, lengkap dengan tombol copy. Begitu build selesai, app kamu live di `https://my-app.wokku.app`.

Tidak pakai git? Deploy folder lokal saja: `wokku deploy:tarball my-app .`

## Cara kerja build

- Kalau repo kamu punya `Dockerfile` di root, Wokku mem-build-nya. Lihat [Deploy dengan Dockerfile](/docs/guides/dockerfile).
- Kalau tidak, Wokku mendeteksi bahasa kamu dan mem-build dengan [Nixpacks](https://nixpacks.com/docs/providers).
- App kamu harus listen di `$PORT`.
- `Procfile` mendefinisikan process type. `web` menerima trafik HTTP; yang lain (seperti `worker`) hanya berjalan kalau kamu men-scale-nya. Lihat [Background Worker](/docs/guides/background-workers).

Selama deploy, container baru dijalankan sebelum yang lama dihentikan, dan container yang crash di-restart otomatis.

## Jalankan migration

Tidak ada release phase, jadi baris `release:` di Procfile kamu tidak menjalankan migration. Jalankan setelah deploy:

```bash
wokku run my-app -- bin/rails db:migrate
```

## Cek deploy

```bash
wokku deploys my-app                   # recent deploys
wokku deploys:info my-app DEPLOY_ID    # one deploy and its build log
wokku logs my-app --follow             # runtime logs
```

Di dashboard, buka tab **Deploy** app kamu.

## Langkah berikutnya

- [Auto-deploy dari GitHub](/docs/apps/github-autodeploy)
- [Atur environment variable](/docs/apps/config)
- [Tambahkan database](/docs/databases/create-link)
- [Tambahkan custom domain](/docs/domains-ssl/custom-domains)
