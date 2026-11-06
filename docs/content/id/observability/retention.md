---
title: Window Retensi
summary: "Berapa lama Wokku simpan log, metrics, sample request, dan snapshot database — plus gimana job prune nightly di-wire buat hormati retensi plan kamu."
eyebrow: observability
last_updated: 2026-05-29
---

# Window Retensi

Data observability Wokku hidup di control plane dan **di-prune per plan**. Halaman ini dokumentasiin apa yang disimpan, berapa lama, dan job nightly mana yang ngelakuin prune.

## Matrix lengkap

| Data | Free | Solo | Pro | Team |
|---|---|---|---|---|
| Log | 1 hari | 3 hari | 7 hari | 30 hari |
| Sample request (high-res) | 24 jam | 48 jam | 7 hari | 14 hari |
| Aggregate request (bucket 5-menit) | 7 hari | 30 hari | 90 hari | 365 hari |
| Metrics (1-menit high-res) | 1 hari | 7 hari | 30 hari | 90 hari |
| MetricHourly (bucket rollup) | 7 hari | 30 hari | 90 hari | 365 hari |
| Snapshot stats DB | 24 jam | 24 jam | 24 jam | 24 jam |
| Audit log | unlimited | unlimited | unlimited | unlimited |

## Gimana window retensi di-wire

Model Plan punya empat kolom retensi:

```ruby
log_retention_days              # prune row log plain
sample_retention_hours          # prune request_samples high-res
metric_high_res_days            # batas metric 1-menit → rollup per jam
metric_aggregate_retention_days # prune aggregate hourly + request
```

Dashboard nampilin angka saat ini di page Usage; file seed (`db/seeds/plans.rb`) adalah source of truth dan di-apply ulang tiap reseed.

## Log

— **Apa** — row `Log`: satu per baris stdout/stderr container yang dikirim dari Vector
— **Job prune** — `LogRetentionPruneJob`, nightly 3:45 pagi
- Buat tiap plan, delete `Log.where(app_record_id: ids_on_plan).where("ts < cutoff")` dimana `cutoff = plan.log_retention_days.days.ago`
- Row orphan (nggak ada app_record_id — mis. container database platform) fallback ke cap 30 hari supaya admin tetap bisa debug

## Sample request + aggregate

— **Apa** — row `RequestSample` dari parser nginx-proxy Vector, plus bucket 5-menit `RequestAggregate` yang dia rollup
— **Prune sample** — jalan di dalam `RequestAggregateRollupJob` tiap 5 menit; delete sample lebih lama dari `plan.sample_retention_hours` per app
— **Prune aggregate** — `RequestAggregateRetentionPruneJob`, nightly 4:00 pagi, delete bucket lebih lama dari `plan.metric_aggregate_retention_days`

Roll-up pakai `PERCENTILE_DISC` Postgres buat p50 / p95, jadi math-nya survive prune — sekali bucket di-build, kamu tetap dapat percentile akurat meski sample raw udah hilang.

## Metrics

— **Apa** — row `Metric` dari `MetricsPollJob` (`docker stats` di-parse jadi satu row per app per menit), plus bucket rollup `MetricHourly`
— **Job rollup** — `MetricRollupJob`, nightly 4:15 pagi
  - Buat tiap app, aggregate row `Metric` raw lebih lama dari `plan.metric_high_res_days` ke bucket per jam via PostgreSQL `DATE_TRUNC('hour', recorded_at)`, terus upsert ke `MetricHourly` dan delete row sumber
  - Pass yang sama prune `MetricHourly` past `plan.metric_aggregate_retention_days`

Ini ngasih kamu resolusi level menit buat debugging recent dan resolusi per jam buat capacity planning window panjang.

## Snapshot stats DB

— **Apa** — row `DatabaseStatsSnapshot` dari `DatabaseStatsCollectorJob` (satu per database per 5 menit); nyimpan connection count, size, cache hit ratio, top query
— **Prune** — di-handle di dalam recurring job lewat check retensi 24 jam; nggak ada yang dijadwal terpisah

24 jam cukup buat dashboard nampilin status "live / stale" dan query stats terbaru — snapshot historis nggak berguna karena query rotate sering.

## Audit log

— **Apa** — row `Activity`: tiap action penting (deploy, ganti config, add member, dll.)
— **Prune** — **nggak ada**. Retensi unlimited di tiap plan
— **Kenapa unlimited** — payload audit log kecil (puluhan KB per workspace per bulan) dan value audit retroaktif dominate cost storage

Kalau perlu purge buat GDPR / right-to-be-forgotten di member yang di-remove, hubungi support.

## Soal override per-app?

Nggak ada. Retensi adalah **plan-wide** — tiap app, addon, dan request di workspace dapat window retensi yang sama. Model yang lebih simple fit ke pricing bundle: kalau butuh 90 hari metrics, kamu upgrade plan, bukan satu resource.

## Tradeoff

Window retensi di-tune buat:

— **Free** — cukup buat debug crash hari ini, dorong kamu pindah sebagai user beneran (semurah mungkin tanpa kami hosting data historis kamu gratis)
— **Solo** — cukup buat liat minggu lalu
— **Pro** — sebulan penuh history metric buat capacity planning
— **Team** — setahun penuh buat compliance, analisis post-incident, dan trending capacity

Kalau kamu punya kebutuhan retensi spesifik yang nggak ke-cover di sini (industri ter-regulasi, retensi data kontrak), email [support@wokku.cloud](mailto:support@wokku.cloud) — kita akan susun SKU retensi custom.

## Self-hosted

Community Edition punya infrastruktur retensi tapi nggak ada default yang ship — set value retensi `Plan` jadi apa pun hardware kamu bisa nampung. Job prune baca dari row `Plan` cara yang sama; kamu cuma kasih window-nya.

## Lihat juga

— [Log](/docs/monitoring/logs) — surface log + filter
— [Metrics](/docs/monitoring/metrics) — tiga monitor surface
— [Audit Log](/docs/monitoring/audit-log) — event siapa-ngapain
— [Plan & Harga](/docs/billing/plans) — plan mana yang dipilih
