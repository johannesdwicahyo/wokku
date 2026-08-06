# Migrasi dari Render

Render dan Wokku sepupu dekat — web service dari repo Git, Postgres/Redis
terkelola, background worker, dan cron. Perpindahannya sebagian besar membuat
ulang service dan mengarahkannya ke database Wokku.

## Peta konsep

| Render | Wokku |
|---|---|
| Web Service | Aplikasi / proses `web` |
| Background Worker | Proses `worker` ([panduan](/docs/guides/background-workers)) |
| Cron Job | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| `render.yaml` (blueprint) | `Procfile` + config var |
| Render Postgres | Add-on Postgres ([panduan](/docs/guides/postgres-redis)) |
| Render Key Value (Redis) | Add-on Redis |
| Environment Groups | Config vars ([config](/docs/apps/config)) |
| Start Command | Baris `web:` di `Procfile` |

## 1. Terjemahkan `render.yaml` → Procfile

Ambil **start command** service-mu dan taruh di `Procfile`; tambahkan baris
`worker` dan `release` untuk worker atau perintah pra-deploy:

```procfile
web: <start command Render-mu, bind ke $PORT>
worker: <perintah worker-mu>
release: <perintah migrate-mu>
```

Render menyuntikkan `PORT`; Wokku juga — tetap bind ke `$PORT`.

## 2. Buat ulang aplikasi + env

```bash
wokku apps:create my-app --server my-server
```

Salin tiap variabel dari **Environment** / Environment Group Render ke
[config var](/docs/apps/config) (`wokku config:set my-app KEY=VALUE`).

## 3. Pindahkan database

```bash
# Render memberi connection string eksternal di dashboard
pg_dump "$RENDER_EXTERNAL_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin
wokku addons:create postgres my-app
wokku config my-app | grep DATABASE_URL
pg_restore --no-owner --no-acl -d "$WOKKU_DATABASE_URL" dump.bin
```

Tambah add-on Redis jika kamu memakai Render Key Value, lalu arahkan ulang `REDIS_URL`.

## 4. Deploy + domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Verifikasi di `my-app.wokku.app`, lalu pindahkan domainmu — lihat
[Domain Kustom](/docs/domains-ssl/custom-domains).

## Gotcha

- **Disk** — persistent disk Render tak ada padanan langsung; pakai object storage atau DB dedicated.
- **Health check** — Wokku mengecek proses web; lihat [Health Checks](/docs/monitoring/health-checks).
- **Timezone cron** — scheduled task Wokku berjalan dalam UTC.

## Langkah berikutnya

- [Background Worker](/docs/guides/background-workers) · [Scheduled Tasks](/docs/guides/scheduled-tasks)
