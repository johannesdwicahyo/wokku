---
title: Log
summary: "Tiap baris log container, persisted dan searchable. Dikirim dari host kamu sama Vector dan disimpan di control plane. Retensi nyesuain plan."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Log

Wokku capture **tiap baris** stdout/stderr dari tiap container — app kamu, addon, container internal platform — dan simpan di control plane. Kamu bisa scroll mundur, search by container, dan filter by level.

## Cara kerjanya

Di tiap host, agent **Vector** nge-tail log container Docker dan ngirim batch NDJSON ke `POST /api/v1/logs/ingest`. Control plane nulis satu row per baris ke tabel `logs`.

Full pipeline:

```text
stdout container → file JSON Docker → Vector docker_logs source → HTTP POST → tabel logs
```

Vector authenticate pakai bearer token per-server (`Server#ingest_token`). Token-nya bisa di-rotate dari dashboard kapan aja.

## Lihat log

### Dashboard

Buka app → tab **Logs**. Kamu dapat:

— **Live tail** — baris baru stream lewat WebSocket pas dia datang
— **History scroll** — tiap baris disimpan selama window retensi plan
— **Search** — case-insensitive substring match terhadap isi baris
— **Filter level** — info / warn / error / debug (auto-detect dari isi baris kalau Vector nggak set level)
— **Filter container** — narrow ke satu process type (mis. `web` vs `worker` vs `sidekiq`)

### CLI

```bash
wokku logs                       # live tail
wokku logs --tail 500            # 500 baris terakhir
wokku logs --since 2h            # 2 jam terakhir
wokku logs --search "ERROR 500"  # filter by substring
wokku logs --level error         # filter by level
wokku logs --container web       # satu process type
```

### API

```bash
curl https://wokku.cloud/api/v1/apps/myapp/logs \
  -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode "lines=500" --data-urlencode "level=error"
```

## Retensi

Seberapa jauh log bisa di-scroll tergantung plan kamu:

| Plan | Retensi log |
|---|---|
| Free | 1 hari |
| Solo | 3 hari |
| Pro | 7 hari |
| Team | 30 hari |

`LogRetentionPruneJob` nightly nge-delete baris yang lebih lama dari window plan kamu. Butuh lebih? Lihat [window retensi](/docs/observability/retention) buat schedule cleanup dan gimana window per-plan di-wire.

## Level log

Vector best-effort deteksi level dari isi baris (cari `ERROR`, `WARN`, `INFO`, `DEBUG`, `FATAL`, `TRACE`, plus marker framework umum kayak `exception`, `panic`, `traceback`). Baris yang nggak match apa-apa default ke `info`.

Kalau app kamu emit log structured (JSON line), set field level explicit:

```json
{"level":"error","msg":"db connect failed","attempt":3}
```

Ingest controller ambil itu instead of regex fallback.

## Log drain (forwarding eksternal)

Kalau kamu mau forward log ke Datadog, Logtail, Papertrail, atau endpoint HTTP/syslog mana aja, add log drain di page **app → Settings → Log drains**. Drain jalan di samping Vector ingest (history dashboard tetap; drain dapat salinan).

Target yang didukung:

— Endpoint HTTPS (Datadog, Logtail, custom)
— Syslog over TLS (Papertrail, custom)

## Yang TIDAK di-capture

— Baris log yang di-emit sebelum Vector start di host (jarang banget; terjadi pas provisioning awal)
— Baris lebih dari 16 KB — di-trim ke 16 KB pas ingest
— Log build-time dari builder (itu di page deploy, bukan log runtime)

## Self-hosted

Community Edition ship setup Vector sebagai Rake task (`rake vector:install[<host>]`). Tanpa itu, dashboard cuma nampilin live tail (via SSH) dan nggak ada history.

## Lihat juga

— [Metrics](/docs/monitoring/metrics) — CPU + memory buat container yang sama
— [Audit log](/docs/monitoring/audit-log) — record siapa-ngapain (terpisah dari log app)
— [Window retensi](/docs/observability/retention) — matrix retensi per-plan lengkap
