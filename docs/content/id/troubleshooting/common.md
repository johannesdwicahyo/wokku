---
title: Masalah Umum
summary: Jalankan wokku doctor dulu, lalu cari gejalamu di bawah — deploy gagal, push ditolak, app tidur, error database.
last_updated: 2026-11-07
---

Cari tahu apa yang salah dengan app dan perbaiki. Mulai dengan `wokku doctor`, lalu langsung ke gejalamu.

## Mulai di sini: `wokku doctor`

```bash
wokku doctor
```

Perintah ini mengecek login kamu, apakah CLI kamu sudah versi terbaru, kesehatan host tempat app kamu berjalan, dan apakah ada app yang crash — lalu mencetak petunjuk untuk apa pun yang ditemukan. Di Claude Code, minta *"Jalankan wokku doctor"* (memakai `wokku_doctor`).

## Deploy gagal

1. Baca build log: tab **Deploy** di app, atau
   ```bash
   wokku deploys my-app                    # find the deploy ID
   wokku deploys:info my-app DEPLOY_ID     # show its build log
   ```
2. Minta diagnosis: `wokku ai:diagnose my-app`.

Penyebab yang biasa:

- **Bahasa yang terdeteksi salah** — Wokku mem-build `Dockerfile` kamu kalau ada, kalau tidak ia mendeteksi otomatis dengan Nixpacks. Kalau deteksinya memilih stack yang salah, tambahkan [Dockerfile](/docs/guides/dockerfile).
- **Kehabisan memory saat build atau start** — beri proses lebih banyak RAM di **Resources** ([Resources](/docs/scaling/resources)).
- **App tidak listen di `$PORT`** — bind ke `0.0.0.0` di port dari environment variable `PORT`.

## Push ditolak

- **Remote salah** — harus `git@git.wokku.cloud:my-app`. Cek dengan `git remote -v`; perbaiki dengan
  ```bash
  git remote set-url wokku git@git.wokku.cloud:my-app
  ```
- **SSH key belum ditambahkan** — jalankan `wokku ssh-keys:add` atau tambahkan di **Profile → SSH Keys**. Lihat [SSH Key](/docs/apps/ssh-keys).
- **App belum ada** — buat dulu: `wokku apps:create my-app`.
- **Branch salah** — push branch yang dipakai app untuk deploy, misalnya `git push wokku main`.
- **App terkunci** — ada yang menjalankan `wokku apps:lock my-app`. Buka kuncinya dengan `wokku apps:unlock my-app`.

## Tabel database hilang setelah deploy

Wokku tidak menjalankan migration untuk kamu — tidak ada release phase, dan baris `release:` di Procfile kamu tidak akan menjalankannya. Jalankan sendiri setelah setiap deploy yang mengubah schema:

```bash
wokku run my-app -- bin/rails db:migrate        # Rails
wokku run my-app -- python manage.py migrate    # Django
```

## Request pertama lambat (app sedang tidur)

App gratis (ukuran **Sleeping**) tidur setelah 30 menit tanpa traffic. Request berikutnya membangunkannya; butuh sekitar 30 detik. Supaya app tetap bangun, pindahkan dari ukuran Sleeping di **Resources** — lihat [Resources](/docs/scaling/resources).

## App tidak bisa diakses

- **App di-stop atau crash** — cek **Overview** app, lalu restart: `wokku ps:restart my-app`. Lihat `wokku logs my-app` untuk penyebab crash.
- **Health check gagal** — path health check kamu harus mengembalikan 200. Lihat [Health Check](/docs/monitoring/health-checks).
- **Custom domain tidak terbuka** — record DNS harus mengarah ke target yang ditampilkan di panel domain app (CNAME, atau A record untuk apex domain). HTTPS diterbitkan begitu DNS ter-resolve. Lihat [Custom Domain](/docs/domains-ssl/custom-domains).

## Tidak bisa konek ke database

- **Belum di-link** — link database ke app; itu otomatis mengatur `DATABASE_URL` (atau `REDIS_URL`). Lihat [Membuat & Link](/docs/databases/create-link).
- **Kredensial lama** — cek `wokku config my-app` menampilkan URL-nya; unlink lalu link ulang untuk me-refresh.
- **Database macet saat provisioning** — `wokku databases:retry DB`.

## Masih buntu?

Email [support@wokku.cloud](mailto:support@wokku.cloud) dengan nama app kamu dan output `wokku doctor`.
