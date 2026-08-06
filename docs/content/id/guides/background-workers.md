# Jalankan Background Worker

Jalankan queue, job consumer, atau proses non-web jangka panjang apa pun
berdampingan dengan aplikasi web-mu — Sidekiq, Celery, BullMQ, consumer kustom,
apa saja.

## Cara kerja

Wokku menjalankan tiap baris di `Procfile`-mu sebagai process type tersendiri.
Proses `web` menerima traffic HTTP; process type lain (biasanya `worker`)
berjalan di background. Kamu scale masing-masing secara independen.

## 1. Deklarasikan worker di Procfile

```procfile
web: bin/rails server -p $PORT
worker: bundle exec sidekiq
```

Contoh lain:

```procfile
worker: celery -A myproject worker --loglevel=info   # Celery (Python)
worker: node worker.js                                # BullMQ / kustom (Node)
```

## 2. Deploy

```bash
git push wokku main
```

Saat deploy, Wokku memulai proses `web`-mu. Proses background mulai di **nol
instance** secara default — kamu scale naik secara eksplisit.

## 3. Scale worker

:::tabs
::web-ui
Buka aplikasimu → **Resources** → atur jumlah instance untuk `worker`.

::cli
```bash
wokku scale my-app worker=1
# scale keduanya sekaligus:
wokku scale my-app web=2 worker=2
```
:::

Lihat [Bundled Processes](/docs/scaling/bundled-processes) untuk bagaimana
process scaling dan ukuran box berinteraksi.

## 4. Berbagi backend queue

Worker biasanya butuh Redis (atau DB) sebagai broker. Tambahkan sekali dan
proses web maupun worker membaca `REDIS_URL` / `DATABASE_URL` yang sama:

```bash
wokku addons:create redis my-app
```

Lihat [Tambah Postgres + Redis](/docs/guides/postgres-redis).

:::callout note
Semua process type satu aplikasi berbagi config var dan add-on yang sama —
set `REDIS_URL` sekali dan worker pun melihatnya.
:::

## Troubleshooting

- **Worker tidak jalan** — default-nya 0 instance; scale ke ≥1.
- **Job tidak diambil** — pastikan web dan worker menunjuk broker URL yang sama.
- **Worker mati saat deploy** — job panjang menerima `SIGTERM`; tangani graceful shutdown dan buat job idempotent.

## Langkah berikutnya

- [Jadwalkan tugas (cron)](/docs/guides/scheduled-tasks) · [Logs](/docs/apps/logs)
