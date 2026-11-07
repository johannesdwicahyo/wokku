---
title: Scaling Process
summary: Jalankan lebih banyak instance process web atau worker kamu, atau ubah ukuran masing-masing.
last_updated: 2026-11-07
---

Di sini kamu akan mengatur berapa banyak instance yang berjalan untuk setiap process type.

## Process type

Process type berasal dari `Procfile` kamu:

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
```

| Type | Fungsi |
|------|---------|
| `web` | Melayani request HTTP |
| nama lainnya | Berjalan di background (job, queue) |

## Lihat yang sedang berjalan

:::tabs
::web-ui
Buka app kamu → **Runtime** → **Scaling**.

::cli
```bash
wokku ps my-app
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Minta ke Claude: *"Tampilkan process untuk my-app"*
:::

## Ubah jumlah instance

:::tabs
::web-ui
Di **Runtime** → **Scaling**, atur **Instances** untuk setiap process, lalu klik **Save resources**.

::cli
```bash
wokku ps:scale my-app web=2 worker=1
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scaling": {"web": 2, "worker": 1}}'
```

::mcp
Minta ke Claude: *"Scale my-app jadi 2 web dan 1 worker"*
:::

## Aturan

- 0–10 instance per process.
- `web` tidak bisa di-scale ke 0. Untuk menghentikan app, pakai **Stop** (`wokku ps:stop my-app`).
- App sleeping gratis hanya menjalankan satu instance `web`.
- Setiap instance ditagih sesuai ukuran process-nya: 2 instance biayanya dua kali lipat dari 1.

## Ubah ukuran

Untuk memberi process lebih banyak CPU atau RAM, bukan menambah instance:

```bash
wokku ps:resize my-app worker --cpu 0.5 --memory 1024
```

Lihat [Resource & Ukuran](/docs/scaling/resources).
