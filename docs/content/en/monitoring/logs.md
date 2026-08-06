---
title: Logs
summary: "Every container log line, persisted and searchable. Shipped from your Dokku host by Vector and stored on the control plane. Retention scales with your plan."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Logs

Wokku captures **every line** of stdout/stderr from every container — your apps, the addons, the Dokku internals — and stores them on the control plane. You can scroll back in time, search by container, and filter by level.

## How it works

On every Dokku host, a **Vector** agent tails Docker container logs and ships them in NDJSON batches to `POST /api/v1/logs/ingest`. The control plane writes one row per line to the `logs` table.

The whole pipeline:

```text
container stdout → Docker JSON file → Vector docker_logs source → HTTP POST → logs table
```

Vector authenticates with a per-server bearer token (`Server#ingest_token`). The token rotates from the dashboard at any time.

## Viewing logs

### Dashboard

Open the app → **Logs** tab. You get:

— **Live tail** — new lines stream in via WebSocket as they arrive
— **History scroll** — every line stored for the plan's retention window
— **Search** — case-insensitive substring match against the line content
— **Level filter** — info / warn / error / debug (auto-detected from line content if Vector didn't set a level)
— **Container filter** — narrow to one process type (e.g. `web` vs `worker` vs `sidekiq`)

### CLI

```bash
wokku logs                       # live tail
wokku logs --tail 500            # last 500 lines
wokku logs --since 2h            # last 2 hours
wokku logs --search "ERROR 500"  # filter by substring
wokku logs --level error         # filter by level
wokku logs --container web       # one process type
```

### API

```bash
curl https://wokku.cloud/api/v1/apps/myapp/logs \
  -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode "lines=500" --data-urlencode "level=error"
```

## Retention

How far back logs reach depends on your plan:

| Plan | Log retention |
|---|---|
| Free | 1 day |
| Solo | 3 days |
| Pro | 7 days |
| Team | 30 days |

A nightly `LogRetentionPruneJob` deletes lines older than your plan's window. Need more? See [retention windows](/docs/observability/retention) for the cleanup pass schedule and how the per-plan windows are wired.

## Log levels

Vector best-effort detects a level from line content (looks for `ERROR`, `WARN`, `INFO`, `DEBUG`, `FATAL`, `TRACE`, plus common framework markers like `exception`, `panic`, `traceback`). Lines that don't match anything default to `info`.

If your app emits structured logs (JSON lines), set the level field explicitly:

```json
{"level":"error","msg":"db connect failed","attempt":3}
```

The ingest controller picks that up over the regex fallback.

## Log drains (external forwarding)

If you want to forward logs to Datadog, Logtail, Papertrail, or any HTTP/syslog endpoint, add a log drain on the **app → Settings → Log drains** page. Drains run in addition to the Vector ingest (you keep your in-dashboard history; the drain gets a copy).

Supported targets:

— HTTPS endpoint (Datadog, Logtail, custom)
— Syslog over TLS (Papertrail, custom)

## What's NOT captured

— Log lines emitted before Vector started on the host (extremely rare; happens during initial provisioning)
— Lines longer than 16 KB — trimmed to 16 KB at ingest
— Build-time logs from the Dokku builder (those live on the deploy page, not the runtime log)

## Self-hosted

Community Edition ships Vector setup as a Rake task (`rake vector:install[<host>]`). Without it, the dashboard shows live tail only (via SSH) and no history.

## See also

— [Metrics](/docs/monitoring/metrics) — CPU + memory for the same containers
— [Audit log](/docs/monitoring/audit-log) — who-did-what records (separate from app logs)
— [Retention windows](/docs/observability/retention) — full per-plan retention matrix
