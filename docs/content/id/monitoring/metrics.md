---
title: Metrics
summary: "Tiga monitor surface: app runtime (CPU + RAM), HTTP request (req-rate, p50/p95, error %), dan database (koneksi, hit ratio, slow query). Semua retensi per-plan."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Metrics

Wokku punya **tiga monitor surface** buat view berbeda dari health app:

1. **Runtime metrics** — CPU dan RAM level container, granularity 1 menit
2. **App monitor** — HTTP request rate, p50 / p95 latency, error % dari nginx access log
3. **DB monitor** — connection pool Postgres + Redis, cache hit ratio, slow query

Ketiganya built-in di tiap plan. Window retensi beda per plan.

## Runtime metrics (CPU + RAM)

Page `/dashboard/apps/<app>/metrics` nampilin per-container CPU% dan memory usage di **resolusi 1 menit**, chart 24 jam terakhir.

Cara kerjanya:

— `MetricsPollSchedulerJob` jalan tiap menit
— `MetricsPollJob(server_id)` SSH ke host, jalanin `docker stats --no-stream --format '{{json .}}'`, parse, tulis satu row `Metric` per app per menit
— `MetricRollupJob` nightly nge-aggregate row 1-menit yang lebih lama dari `plan.metric_high_res_days` ke bucket `MetricHourly` per jam dan hapus row sumbernya
— Pass kedua prune `MetricHourly` yang lewat `plan.metric_aggregate_retention_days`

| Plan | High-res (1-min) | Rollup per jam |
|---|---|---|
| Free | 1 hari | 7 hari |
| Solo | 7 hari | 30 hari |
| Pro | 30 hari | 90 hari |
| Team | 90 hari | 365 hari |

## App monitor (HTTP request)

`/dashboard/apps/<app>/monitor` nampilin page Sumopod-style dengan:

— 4 stat tile: **req / menit · p95 latency · error rate · status monitoring (live atau idle)**
— Sparkline req-rate (24 jam)
— Chart latency p50 / p95 (24 jam)
— Tabel slow request (jam terakhir, top 10 by response time)

Cara kerjanya:

— Vector tambah transform `parse_nginx_requests` yang parse tiap baris access-log proxy di tiap host dengan regex
— Entri parsed di-POST ke `/api/v1/requests/ingest` (bearer token per-server, auth sama kayak log)
— Row `RequestSample` nyimpan request individual (retensi `plan.sample_retention_hours` jam)
— Tiap 5 menit, `RequestAggregateRollupJob` bangun bucket `RequestAggregate` (PERCENTILE_DISC p50/p95, count, error count, bytes) dan prune sample sumber per plan

Resolusi:

| Plan | Sample high-res | Retensi aggregate |
|---|---|---|
| Free | 24 jam | 7 hari |
| Solo | 48 jam | 30 hari |
| Pro | 7 hari | 90 hari |
| Team | 14 hari | 365 hari |

Lookup vhost-to-app coba `Domain#hostname` dulu (custom domain) terus fallback subdomain pertama (`<app>.wokku.cloud`). Vhost yang nggak match ingest dengan `app_record_id: nil` dan nggak muncul di app monitor — berguna buat admin debug, nggak keliatan user.

## DB monitor

`/dashboard/addons/<db>/monitor` nampilin page Sumopod-style buat satu service Postgres atau Redis:

— Stat tile **koneksi aktif / max**
— **Size DB** (Postgres) atau **Memory used** (Redis)
— **Cache hit ratio** dengan label Optimal / Healthy / Degraded
— Indikator status **Live / Stale** (umur snapshot sukses terakhir)
— Tabel **Query Performance** (Postgres `pg_stat_statements` slowest / most-time / most-called) atau **Slow Log** (Redis `SLOWLOG GET 50`)

Cara kerjanya:

— `DatabaseStatsCollectorJob` jalan tiap 5 menit via `config/recurring.yml`
— Buat Postgres: satu session SSH `postgres:connect`, jalanin meta query + query `pg_stat_statements`, persist ke `DatabaseStatsSnapshot`
— Buat Redis: `redis:connect` dengan stdin `INFO\nSLOWLOG GET 50\nQUIT`, parse INFO block, hitung hit ratio

Snapshot retensi 24 jam. Page monitor baca snapshot terbaru; kalau collection terakhir error, dia fallback ke yang sukses terakhir dan nampilin banner error.

## CLI / API

```bash
wokku metrics                    # app monitor (req rate, latency, error)
wokku metrics --runtime          # container CPU + RAM
wokku metrics --addon mydb       # DB monitor
```

```bash
curl https://wokku.cloud/api/v1/apps/myapp/metrics \
  -H "Authorization: Bearer $TOKEN"
```

## Konfigurasi pg_stat_statements

Query stats Postgres butuh extension. Plugin shared-postgres enable defaultnya. Buat DB dedicated:

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- restart postgres
CREATE EXTENSION pg_stat_statements;
```

Setelah itu, page monitor populate data query di collector pass berikutnya.

## Self-hosted

Community Edition ship collector runtime metric tapi **bukan** request monitor atau DB monitor (itu tergantung pipeline Vector + job database monitor, yang butuh schema DB control-plane).

## Lihat juga

— [Log](/docs/monitoring/logs) — pipeline Vector yang sama, payload beda
— [Window retensi](/docs/observability/retention) — matrix retensi per-plan lengkap
— [Health check](/docs/monitoring/health-checks) — uptime + status check
