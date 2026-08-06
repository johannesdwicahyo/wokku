---
title: Retention Windows
summary: "How long Wokku keeps logs, metrics, request samples, and database snapshots — and how the nightly prune jobs are wired to honor your plan's retention."
eyebrow: observability
last_updated: 2026-05-29
---

# Retention Windows

Wokku's observability data lives on the control plane and is **pruned per plan**. This page documents what's retained, for how long, and which nightly job does the pruning.

## The full matrix

| Data | Free | Solo | Pro | Team |
|---|---|---|---|---|
| Logs | 1 day | 3 days | 7 days | 30 days |
| Request samples (high-res) | 24 h | 48 h | 7 days | 14 days |
| Request aggregates (5-min buckets) | 7 days | 30 days | 90 days | 365 days |
| Metrics (1-min high-res) | 1 day | 7 days | 30 days | 90 days |
| MetricHourly (rollup buckets) | 7 days | 30 days | 90 days | 365 days |
| DB stats snapshots | 24 h | 24 h | 24 h | 24 h |
| Audit log | unlimited | unlimited | unlimited | unlimited |

## How the retention windows are wired

The Plan model carries four retention columns:

```ruby
log_retention_days              # plain log row prune
sample_retention_hours          # request_samples high-res prune
metric_high_res_days            # 1-min metric → hourly rollup boundary
metric_aggregate_retention_days # hourly + request aggregate prune
```

The dashboard shows the current numbers on the Usage page; the seed file (`db/seeds/plans.rb`) is the source of truth and gets re-applied on every reseed.

## Logs

— **What** — `Log` rows: one per container stdout/stderr line shipped from Vector
— **Prune job** — `LogRetentionPruneJob`, nightly at 3:45 am
- For each plan, deletes `Log.where(app_record_id: ids_on_plan).where("ts < cutoff")` where `cutoff = plan.log_retention_days.days.ago`
- Orphan rows (no app_record_id — e.g. dokku-postgres system containers) fall back to a 30-day cap so admins can still debug

## Request samples + aggregates

— **What** — `RequestSample` rows from Vector's nginx-proxy parser, plus the 5-min `RequestAggregate` buckets they roll up to
— **Sample prune** — runs inside `RequestAggregateRollupJob` every 5 minutes; deletes samples older than `plan.sample_retention_hours` per app
— **Aggregate prune** — `RequestAggregateRetentionPruneJob`, nightly at 4:00 am, deletes buckets older than `plan.metric_aggregate_retention_days`

The roll-up uses Postgres's `PERCENTILE_DISC` for p50 / p95, so the math survives the prune — once a bucket is built, you keep accurate percentiles even after the raw samples are gone.

## Metrics

— **What** — `Metric` rows from `MetricsPollJob` (`docker stats` parsed to one row per app per minute), plus the `MetricHourly` rollup buckets
— **Rollup job** — `MetricRollupJob`, nightly at 4:15 am
  - For each app, aggregates raw `Metric` rows older than `plan.metric_high_res_days` into hourly buckets via PostgreSQL `DATE_TRUNC('hour', recorded_at)`, then upserts into `MetricHourly` and deletes the source rows
  - Same pass prunes `MetricHourly` past `plan.metric_aggregate_retention_days`

This gives you minute-level resolution for recent debugging and hourly resolution for long-window capacity planning.

## DB stats snapshots

— **What** — `DatabaseStatsSnapshot` rows from `DatabaseStatsCollectorJob` (one per database per 5 min); holds connection count, size, cache hit ratio, top queries
— **Prune** — handled inside the recurring job by virtue of the 24-hour retention check; nothing separate to schedule

24 hours is enough for the dashboard to show "live / stale" status and the latest query stats — historical snapshots aren't useful since queries rotate frequently.

## Audit log

— **What** — `Activity` rows: every meaningful action (deploy, config change, member add, etc.)
— **Prune** — **none**. Retention is unlimited on every plan
— **Why unlimited** — audit log payload is tiny (tens of KB per workspace per month) and the value of retroactive auditing dominates the storage cost

If you ever need to purge for GDPR / right-to-be-forgotten on a removed member, contact support.

## What about per-app overrides?

There aren't any. Retention is **plan-wide** — every app, addon, and request in a workspace gets the same retention window. The simpler model fits the bundle pricing: if you need 90 days of metrics, you upgrade the plan, not a single resource.

## Tradeoffs

The retention windows are tuned to:

— **Free** — keep enough to debug today's crash, force you off as a real user (cheap as we can make it without hosting your historical data for free)
— **Solo** — enough to look at last week
— **Pro** — full month of metric history for capacity planning
— **Team** — full year for compliance, post-incident analysis, and capacity trending

If you have a specific retention need not covered here (regulated industry, contractual data retention), email [support@wokku.cloud](mailto:support@wokku.cloud) — we'll work out a custom retention SKU.

## Self-hosted

Community Edition has retention infrastructure but no defaults shipped — set `Plan` retention values to whatever your hardware can hold. The prune jobs read from `Plan` rows the same way; you just provide the windows.

## See also

— [Logs](/docs/monitoring/logs) — log surface + filters
— [Metrics](/docs/monitoring/metrics) — three monitor surfaces
— [Audit Log](/docs/monitoring/audit-log) — who-did-what events
— [Plans & Pricing](/docs/billing/plans) — what plan to pick
