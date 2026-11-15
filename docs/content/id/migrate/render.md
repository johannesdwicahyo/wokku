---
title: Migrasi dari Render
summary: Pindahkan web service, worker, cron job, dan Postgres dari Render ke Wokku.
last_updated: 2026-11-07
---

Render dan Wokku bekerja dengan cara yang mirip: service dari repo Git, managed database, worker, dan cron. Terjemahkan `render.yaml` kamu ke Procfile, lalu pindahkan config dan data.

## Peta konsep

| Render | Wokku |
|---|---|
| Web Service | Process `web` |
| Background Worker | Process type lain ([Background Workers](/docs/guides/background-workers)) |
| Cron Job | [Scheduled Tasks](/docs/guides/scheduled-tasks) |
| Build / Start Command | `Dockerfile` kamu atau Nixpacks / baris `web:` di Procfile |
| Pre-Deploy Command | Tidak ada. Jalankan `wokku run my-app -- <command>` setelah deploy |
| Instance type | [Resources](/docs/scaling/resources) (CPU dan RAM) |
| Render Postgres | [Add-on Postgres](/docs/databases/create-link) |
| Render Key Value | Add-on Redis |
| Environment Groups | [Environment Variables](/docs/apps/config) |

## 1. Tulis Procfile

```procfile
web: <your start command, listening on $PORT>
worker: <your worker command>
```

Render men-set `PORT`, begitu juga Wokku, jadi tetap listen di situ. Jalankan pre-deploy command kamu (biasanya migration) setelah setiap deploy, misalnya `wokku run my-app -- npm run migrate`.

## 2. Buat app dan salin config

```bash
wokku apps:create my-app
wokku config:set my-app KEY1=value1 KEY2=value2
```

Salin setiap variabel dari **Environment** milik service dan dari Environment Groups yang ada. Lewati `DATABASE_URL` dan `REDIS_URL`; keduanya di-set oleh add-on Wokku.

## 3. Pindahkan database

```bash
# Use the External Database URL from the Render dashboard
pg_dump "$RENDER_EXTERNAL_DATABASE_URL" --no-owner --no-acl -Fc -f dump.bin

wokku addons:dedicated:upgrade my-app postgres
wokku addons my-app                          # note the database name
wokku databases:import <database-name> dump.bin
```

Pakai Key Value? `wokku addons:shared:enable my-app redis` akan men-set `REDIS_URL`. Selengkapnya di [Memindahkan database](/docs/migrate/index).

## 4. Deploy dan pindahkan domain

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Cek `https://my-app.wokku.app`, lalu pindahkan domain kamu. Lihat [Custom Domains](/docs/domains-ssl/custom-domains).

## Hal yang perlu diperhatikan

- **Persistent disk** — tidak ada disk yang terpasang. Simpan file di object storage atau database.
- **Path health check** — atur di [Health Checks](/docs/monitoring/health-checks).
