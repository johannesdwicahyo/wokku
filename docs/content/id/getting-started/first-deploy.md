---
cloud_prices: true
title: Mulai Cepat
summary: Dari akun baru sampai app live di https://my-app.wokku.app, dengan template sekali klik atau kode kamu sendiri lewat git push.
last_updated: 2026-11-07
---

Kamu akan mendaftar, men-deploy app dengan salah satu dari dua cara, lalu membukanya di URL live-nya. Cuma butuh beberapa menit.

## 1. Daftar

Buka [wokku.cloud](https://wokku.cloud) dan klik **Get Started**. Kamu bisa mendaftar dengan email dan password, Google, GitHub, atau Apple. Lihat [Daftar](/docs/getting-started/sign-up).

Selama kamu belum punya app, halaman **Apps** menampilkan kartu **Deploy your first app**. Kartu itu menawarkan beberapa pilihan sekali klik plus **or push your own code**. Dua opsi di bawah sesuai dengan pilihan tersebut.

## 2a. Deploy template sekali klik

Ini cara tercepat untuk melihat sesuatu live. Template adalah app siap pakai seperti Ghost, n8n, atau starter Astro atau Next.js.

:::tabs
::web-ui
1. Di kartu **Deploy your first app**, pilih template. Kamu juga bisa buka **Templates** di sidebar dan memilih app apa saja.
2. Pakai nama app yang disarankan atau ketik sendiri, misalnya `my-app`.
3. Klik **Deploy &lt;template name&gt;**.

Build biasanya butuh 30–90 detik, tergantung stack-nya.

::cli
```bash
wokku templates                    # list templates and their slugs
wokku deploy ghost --name my-app
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/templates/deploy \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "name": "my-app", "server_id": "<server-id>"}'
```

::mcp
Minta ke Claude: *"Deploy template Ghost sebagai my-app."*
:::

Untuk menemukan app lain, lihat [App Sekali Klik](/docs/templates/browse).

## 2b. Push kode kamu sendiri

Wokku mem-build dari `Dockerfile` kalau repo kamu punya. Kalau tidak, Wokku mendeteksi stack kamu dan mem-build app-nya untuk kamu. App kamu harus listen di port yang ada di environment variable `PORT`.

### Tambahkan SSH key kamu (sekali saja)

Server git mengenali kamu dari SSH key, jadi tambahkan dulu sebelum push pertama.

:::tabs
::web-ui
Buka **Settings → SSH Keys** dan tempel public key kamu, biasanya isi dari `~/.ssh/id_ed25519.pub`.

::cli
```bash
gem install wokku-cli
wokku auth:login
wokku ssh-keys:add --name laptop     # uploads ~/.ssh/id_ed25519.pub
```

::mcp
Minta ke Claude: *"Tambahkan SSH public key saya dari ~/.ssh/id_ed25519.pub ke Wokku dengan nama laptop."*
:::

Belum punya key? Jalankan `ssh-keygen -t ed25519` dulu. Opsi lainnya ada di [SSH Keys](/docs/apps/ssh-keys).

### Buat app dan push

:::tabs
::web-ui
1. Di **Apps**, klik **+ New app**, atau klik **or push your own code** di kartu first-deploy.
2. Masukkan nama, misalnya `my-app`. Supaya tetap gratis, biarkan **Resources** di **Sleeping**.
3. Klik **Create App**. Lalu buka tab **Deploy** di app tersebut dan salin baris `git remote add`.
4. Di folder proyek kamu, jalankan:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::cli
```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::api
```bash
# Get your server id first: GET /api/v1/servers
curl -X POST https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": "<server-id>"}'
```

Lalu push:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

::mcp
Minta ke Claude: *"Buat app Wokku bernama my-app."* Lalu push dari terminal kamu:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```
:::

Log build tampil langsung di terminal kamu. Kalau kamu lebih suka deploy setiap kali push ke GitHub, pakai **Connect repository** di tab **Deploy** app kamu. Lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

## 3. Buka app kamu

App kamu live di:

```
https://my-app.wokku.app
```

:::callout note
**App gratis bisa tidur.** App dengan ukuran gratis **Sleeping** akan tidur setelah 30 menit tanpa trafik. Request berikutnya membangunkannya, dan itu butuh sekitar 30 detik. Kamu dapat 3 app sleeping gratis. Supaya app selalu menyala, beri CPU dan RAM di **Resources**. Kamu hanya membayar yang kamu jalankan; lihat [Harga](/docs/billing/pricing).
:::

## Langkah berikutnya

| Untuk melakukan ini | Baca |
|---|---|
| Tambah Postgres, MariaDB, atau Redis gratis | [Buat & Hubungkan Database](/docs/databases/create-link) |
| Atur environment variable | [Environment Variable](/docs/apps/config) |
| Jalankan migration atau perintah sekali jalan lainnya dengan `wokku run my-app -- <cmd>` | [Buat & Deploy](/docs/apps/deploy) |
| Pakai domain kamu sendiri | [Custom Domain](/docs/domains-ssl/custom-domains) |
| Ubah CPU dan RAM | [Resource](/docs/scaling/resources) |
| Dapatkan tips untuk framework kamu | [Framework](/docs/frameworks/index) |
