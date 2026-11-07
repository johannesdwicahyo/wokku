---
title: Metrics
summary: Lihat CPU dan memory app kamu, traffic HTTP, Web Vitals dari pengguna nyata, dan kesehatan database.
last_updated: 2026-11-07
---

Di sini kamu akan mengecek performa app dan database kamu. Semuanya sudah built-in — tidak ada yang perlu di-install, kecuali satu script tag untuk Web Vitals.

## Yang bisa kamu lihat

| Tampilan | Menampilkan | Dashboard | CLI |
|---|---|---|---|
| **Metrics** | CPU % dan memory per app, resolusi 1 menit | App → **Performance** → **Metrics** | `wokku metrics my-app` |
| **Requests** | Request per menit, latency p50 / p95, error rate, URL paling lambat | App → **Performance** → **Requests** | `wokku monitor my-app` |
| **Vitals** | p75 dari LCP, INP, CLS, FCP, dan TTFB dari pengunjung nyata | App → **Performance** → **Vitals** | `wokku vitals my-app` |
| **Database monitor** | Koneksi, ukuran atau memory, cache hit ratio, slow query (Postgres dan Redis) | Database → **Monitor** | `wokku db:monitor my-db` |

Requests hanya menghitung traffic yang sampai ke app kamu lewat domain Wokku-nya (`my-app.wokku.app` atau [custom domain](/docs/domains-ssl/custom-domains)).

## Mengaktifkan Web Vitals

1. Buka app kamu → **Performance** → **Vitals**.
2. Salin **Install snippet** — satu tag `<script defer …>`.
3. Tempel di `<head>` HTML situs kamu, lalu deploy.

Data muncul beberapa menit setelah kunjungan berikutnya. Kalau snippet-nya bocor atau kamu ingin mencabutnya, rotate token-nya — script tag lama berhenti berfungsi, jadi update situs kamu dengan yang baru:

:::tabs
::web-ui
**Performance** → **Vitals** → **Rotate token**.

::cli
```bash
wokku vitals:rotate-token my-app
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/vitals/rotate_token \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Tanya Claude: *"Rotate token vitals untuk my-app."*
:::

## API dan Claude

:::tabs
::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/metrics -H "Authorization: Bearer $TOKEN"   # CPU + memory
curl https://wokku.cloud/api/v1/apps/my-app/monitor -H "Authorization: Bearer $TOKEN"   # requests
curl https://wokku.cloud/api/v1/apps/my-app/vitals  -H "Authorization: Bearer $TOKEN"   # Web Vitals
curl https://wokku.cloud/api/v1/databases/my-db/monitor -H "Authorization: Bearer $TOKEN"
```

::mcp
Tanya Claude: *"Bagaimana kondisi my-app? Cek CPU, memory, dan latency p95."*
:::

Metrics disimpan dalam jangka waktu terbatas.

## Lihat juga

- [Log](/docs/monitoring/logs)
- [Uptime & insiden](/docs/monitoring/uptime) — dapat kabar saat app kamu down
- [Resources](/docs/scaling/resources) — beri app kamu CPU atau memory lebih
