---
title: Metrics
summary: "Three monitor surfaces: app runtime (CPU + RAM), HTTP requests (req-rate, p50/p95, error %), and databases (connections, hit ratio, slow queries). All retained per-plan."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Metrics

Wokku has **three monitor surfaces** for different views of an app's health:

1. **Runtime metrics** — container-level CPU and RAM, 1-minute granularity
2. **App monitor** — HTTP request rate, p50 / p95 latency, error % from the nginx access log
3. **DB monitor** — Postgres + Redis connection pool, cache hit ratio, slow queries

All three come built-in with every plan. Retention windows vary by plan.

## Runtime metrics (CPU + RAM)

The `/dashboard/apps/<app>/metrics` page shows per-container CPU% and memory usage at **1-minute resolution**, charted over the last 24 hours.

How it works:

— `MetricsPollSchedulerJob` runs every minute
— `MetricsPollJob(server_id)` SSHes to the host, runs `docker stats --no-stream --format '{{json .}}'`, parses, writes one `Metric` row per app per minute
— A nightly `MetricRollupJob` aggregates raw 1-minute rows older than `plan.metric_high_res_days` into hourly `MetricHourly` buckets and deletes the source rows
— A second pass prunes `MetricHourly` past `plan.metric_aggregate_retention_days`

| Plan | High-res (1-min) | Hourly rollup |
|---|---|---|
| Free | 1 day | 7 days |
| Solo | 7 days | 30 days |
| Pro | 30 days | 90 days |
| Team | 90 days | 365 days |

## App monitor (HTTP requests)

`/dashboard/apps/<app>/monitor` shows a Sumopod-style page with:

— 4 stat tiles: **req / minute · p95 latency · error rate · monitoring status (live or idle)**
— Req-rate sparkline (24 h)
— p50 / p95 latency chart (24 h)
— Slow-requests table (last hour, top 10 by response time)

How it works:

— Vector adds a `parse_nginx_requests` transform that parses the proxy's access-log lines on each host with a regex
— Parsed entries get POSTed to `/api/v1/requests/ingest` (per-server bearer token, same auth as logs)
— `RequestSample` rows hold individual requests (retained `plan.sample_retention_hours` hours)
— Every 5 minutes, `RequestAggregateRollupJob` builds `RequestAggregate` buckets (PERCENTILE_DISC p50/p95, count, error counts, bytes) and prunes source samples per plan

Resolution:

| Plan | High-res samples | Aggregates retention |
|---|---|---|
| Free | 24 h | 7 d |
| Solo | 48 h | 30 d |
| Pro | 7 d | 90 d |
| Team | 14 d | 365 d |

The vhost-to-app lookup tries `Domain#hostname` first (custom domains) then a first-subdomain fallback (`<app>.wokku.cloud`). Unmatched vhosts ingest with `app_record_id: nil` and don't show up on the app monitor — useful for admin debug, invisible to users.

## DB monitor

`/dashboard/addons/<db>/monitor` shows a Sumopod-style page for one Postgres or Redis service:

— **Active connections / max** stat tile
— **DB size** (Postgres) or **Memory used** (Redis)
— **Cache hit ratio** with Optimal / Healthy / Degraded label
— **Live / Stale** status indicator (last successful snapshot age)
— **Query Performance** table (Postgres `pg_stat_statements` slowest / most-time / most-called) or **Slow Log** (Redis `SLOWLOG GET 50`)

How it works:

— `DatabaseStatsCollectorJob` runs every 5 min via `config/recurring.yml`
— For Postgres: single `postgres:connect` SSH session, runs meta query + `pg_stat_statements` query, persists to `DatabaseStatsSnapshot`
— For Redis: `redis:connect` with `INFO\nSLOWLOG GET 50\nQUIT` stdin, parses INFO blocks, computes hit ratio

Snapshots retained 24 h. The monitor page reads the latest snapshot; if the most recent collection errored, it falls back to the last successful one and shows the error banner.

## CLI / API

```bash
wokku metrics                    # app monitor (req rate, latency, errors)
wokku metrics --runtime          # container CPU + RAM
wokku metrics --addon mydb       # DB monitor
```

```bash
curl https://wokku.cloud/api/v1/apps/myapp/metrics \
  -H "Authorization: Bearer $TOKEN"
```

## Configure pg_stat_statements

Postgres query stats require the extension. The shared-postgres plugin enables it by default. For dedicated DBs:

```sql
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- restart postgres
CREATE EXTENSION pg_stat_statements;
```

After that, the monitor page populates with query data on the next collector pass.

## Self-hosted

Community Edition ships the runtime metric collector but **not** the request monitor or DB monitor (those depend on the Vector pipeline + database monitor jobs, which require the control-plane DB schema).

## See also

— [Logs](/docs/monitoring/logs) — same Vector pipeline, different payload
— [Retention windows](/docs/observability/retention) — full per-plan retention matrix
— [Health checks](/docs/monitoring/health-checks) — uptime + status checks
