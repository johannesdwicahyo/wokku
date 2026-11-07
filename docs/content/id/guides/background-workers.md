---
title: Menjalankan Background Worker
summary: Jalankan Sidekiq, Celery, BullMQ, atau process non-web apa pun di samping web app kamu.
last_updated: 2026-11-07
---

Kamu akan mendeklarasikan worker di `Procfile`, deploy, lalu scale ke satu instance atau lebih.

## 1. Deklarasikan worker

```procfile
web: bin/rails server -p $PORT
worker: bundle exec sidekiq
```

Contoh lain:

```procfile
worker: celery -A myproject worker --loglevel=info   # Celery
worker: node worker.js                                # BullMQ / custom
```

## 2. Deploy

```bash
git push wokku main
```

Secara default hanya `web` yang dijalankan. Process type lain baru jalan setelah kamu scale.

## 3. Scale worker

:::tabs
::web-ui
App → tab **Runtime** → **Scaling** → atur CPU, RAM, dan jumlah instance untuk `worker`.

::cli
```bash
wokku ps:scale my-app worker=1
wokku ps:scale my-app web=2 worker=2   # both at once
```

::mcp
Minta ke Claude: *"Scale my-app ke 1 worker."*
:::

Setiap process type diatur ukurannya dan ditagih sendiri-sendiri. Lihat [Scaling Processes](/docs/scaling/dynos).

## 4. Tambahkan backend antrean

Kebanyakan worker butuh Redis. Tambahkan yang shared dan gratis:

```bash
wokku addons:shared:enable my-app redis
```

`REDIS_URL` akan di-set di app, dan semua process type bisa melihatnya. Lihat [Menambahkan database](/docs/databases/create-link).

## Troubleshooting

- **Worker tidak jalan**: scale minimal ke 1.
- **Job tidak diambil**: pastikan web dan worker memakai `REDIS_URL` yang sama.
- **Job terhenti saat deploy**: worker menerima `SIGTERM` saat diganti. Buat job yang idempotent. Lihat [Production Readiness](/docs/apps/best-practices).

## Langkah selanjutnya

- [Menjadwalkan task (cron)](/docs/guides/scheduled-tasks)
- [Log](/docs/monitoring/logs)
