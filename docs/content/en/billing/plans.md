---
title: Plans & Pricing
summary: "Pick a plan. Each plan includes a bundle of boxes, a Postgres database, a Redis cache, and object storage — billed monthly via iPaymu. No metering, no surprise bills."
eyebrow: billing
badges:
  - tone: success
    label: live
last_updated: 2026-05-29
---

# Plans & Pricing

Wokku has four plans. Each is **a fixed monthly price** with a bundle of boxes (containers), one Postgres database, one Redis cache, and object storage — sized by tier. You pay once per month via iPaymu (QRIS, VA, e-wallet, or card). There's no hourly metering and no overage bills.

## The four plans

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| **Price / month** | Rp 0 | Rp 75.000 | Rp 225.000 | Rp 750.000 |
| **For** | side projects, demos | one builder | one developer with a side income | small team |
| **Seats included** | 1 | 1 | 1 | 3 |
| **Extra seat** | — | — | — | Rp 45.000 / seat / month |
| **Free trial** | — | 7 days | 7 days | 7 days |

> Solo / Pro / Team start with a **7-day free trial**. You get the full feature set; you're only invoiced after the trial ends and only if you stay subscribed.

## What's in each plan

Plans are **batteries-included**: the resources below ship with the plan price, no extra add-ons to wire up.

### Boxes (containers)

A *box* is one Dokku container. Multi-process apps (Rails + Sidekiq, web + cron) can share one box via `foreman`/`supervisor` — see [bundled processes](/docs/scaling/bundled-processes).

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Small (512 MB) | — | 3 | 3 | 3 |
| Medium (1 GB) | — | — | 2 | 2 |
| Large (2 GB) | — | — | — | 1 |
| Sleeping (idle apps) | 3 | 3 | 3 | 3 |
| Extra Large add-on | — | — | — | Rp 300.000 / month |
| Extra X-Large add-on | — | — | — | Rp 600.000 / month |

### Database, cache, object storage

Every plan includes **one of each**, sized to match the plan tier.

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Postgres | 100 MB shared | 1 GB | 5 GB | 10 GB |
| Redis (cache) | 25 MB | 100 MB | 500 MB | 1 GB |
| Object storage (MinIO) | 1 GB | 5 GB | 25 GB | 50 GB |
| Backups | manual | daily · 3-day retention | daily · 7-day retention | daily + monthly · 30-day retention |

See [plan bundles](/docs/billing/plan-bundles) for the detail on each resource.

### Pro features

Available on **Pro** and **Team**:

— **PR previews** — every pull request gets its own preview environment, auto-destroyed on merge
— **Transfer app** — hand an app off to another Wokku user (agency-friendly)
— **Scheduled tasks** — cron-style recurring jobs without spinning up a separate worker

### Observability

Every plan gets per-app logs, metrics, request-level monitoring, and audit logs. Retention windows scale with the plan.

| | **Free** | **Solo** | **Pro** | **Team** |
|---|---|---|---|---|
| Logs | 1 day | 3 days | 7 days | 30 days |
| Metrics (high-res, 1-min) | 1 day | 7 days | 30 days | 90 days |
| Metrics (hourly rollup) | 7 days | 30 days | 90 days | 365 days |
| Audit log | ✓ | ✓ | ✓ | ✓ |

### Support

— **Free / Solo** — chatbot
— **Pro / Team** — chat with a human, priority response
— **Team** — dedicated contact

## Always included

Every plan, free or paid:

— Unlimited apps (within the box quota for your plan)
— Custom domains with **automatic Let's Encrypt SSL**
— `git push` deploys + GitHub auto-deploy
— Real-time logs and metrics in the dashboard
— Deploy history with one-click rollback
— CLI, REST API, and the Claude Code MCP plugin
— No bandwidth fees

## How billing works

Wokku uses a **monthly invoice model**. There's no hourly metering, no deposit balance, and no per-resource line items — you pay one flat invoice for your plan, optionally plus extra seats on Team.

### The monthly cycle

1. You pick a plan and start a 7-day free trial (Solo / Pro / Team) or stay on Free indefinitely.
2. **7 days before your billing date**, we email you the upcoming invoice with the amount and due date.
3. **On your billing date**, the invoice becomes payable. Pay it via iPaymu (QRIS, virtual account, e-wallet, or card).
4. If unpaid past **7 days after the due date**, your paid apps are suspended. They come straight back when the invoice is paid — no data loss, no redeploy needed.
5. The cycle restarts on the next billing date.

The billing date is anchored to the day of the month you first subscribed.

### Trying to upgrade or downgrade

— **Upgrade mid-cycle** — we issue a prorated invoice for the difference. The change takes effect immediately.
— **Downgrade** — scheduled for your next billing date so you keep what you paid for. You can also cancel from the [billing page](/dashboard/billing) and fall back to **Free** at the end of the current cycle.

### Refunds

Paid invoices are non-refundable. If something goes wrong on our side, we'll credit your next invoice — no quibbles.

## Self-hosted (free forever)

Wokku Community Edition is open source under **AGPL-3.0**. Run it on your own servers and there's no billing layer at all:

```bash
git clone https://github.com/johannesdwicahyo/wokku.git
cd wokku && docker compose up -d
```

No quotas, no seat limits, no retention caps. You bring the hardware and the operations; Wokku handles the deploy pipeline. The managed cloud at [wokku.cloud](https://wokku.cloud) is for people who'd rather not run their own VPS.

## How does this compare to Heroku?

| | **Wokku Solo** | **Heroku Basic** equivalent |
|---|---|---|
| 1× Small dyno + Postgres | Rp 75.000 / mo | ~Rp 450.000 / mo |
| Add a Redis cache | included | +Rp 225.000 / mo |
| Add backups + 7-day retention | upgrade to Pro | +Rp 105.000 / mo |
| **Total** | **Rp 75.000 / mo** (Solo) or **Rp 225.000 / mo** (Pro) | **~Rp 780.000 / mo** |

That's **60–90% lower** for the equivalent setup, plus QRIS billing and Indonesian Jakarta-hosted infrastructure.

## Enterprise

Need a custom plan, an SLA, dedicated support, or on-premises deployment? Email [enterprise@wokku.cloud](mailto:enterprise@wokku.cloud).
