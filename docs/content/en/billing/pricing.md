---
title: Pricing
summary: Pay only for the CPU, RAM and disk you run, in Rupiah. No plans or packages.
last_updated: 2026-11-07
---

You'll see what Wokku costs and how to estimate your bill.

## Free

- **3 sleeping apps, free forever.** They sleep after 30 minutes idle and wake on the next request (about 30 seconds).
- **Free shared add-ons with every app:** Postgres or MariaDB (100 MB) and Redis (10 MB). See [Database engines](/docs/databases/engines).
- No credit card needed.

## Unit prices

| Resource | Price per month |
|---|---|
| CPU | Rp16.000 per vCPU |
| RAM | Rp24.000 per GB |
| Disk | Rp1.000 per GB |

All features are included once you pay for anything.

You're charged per day (the monthly price ÷ 30), at the largest size you had that day. Resize any time: upsizes bill from that day, downsizes credit your next invoice.

## What presets cost

App processes, per instance:

| Preset | CPU / RAM | Per month |
|---|---|---|
| Nano | 0.25 vCPU / 256 MB | Rp10.000 |
| Starter | 0.25 vCPU / 512 MB | Rp16.000 |
| Standard | 0.5 vCPU / 1 GB | Rp32.000 |
| Large | 1 vCPU / 2 GB | Rp64.000 |
| X-Large | 2 vCPU / 4 GB | Rp128.000 |

Dedicated databases (Postgres, MySQL, MariaDB, MongoDB):

| Preset | CPU / RAM / disk | Per month |
|---|---|---|
| Small | 0.25 vCPU / 512 MB / 5 GB | Rp21.000 |
| Medium | 0.5 vCPU / 1 GB / 20 GB | Rp52.000 |
| Large | 1 vCPU / 2 GB / 50 GB | Rp114.000 |

Dedicated Redis:

| Preset | CPU / RAM / disk | Per month |
|---|---|---|
| Small | 0.25 vCPU / 256 MB / 1 GB | Rp11.000 |
| Medium | 0.25 vCPU / 1 GB / 2 GB | Rp30.000 |
| Large | 0.5 vCPU / 2 GB / 4 GB | Rp60.000 |

## Example

A Rails app with a Standard `web` (Rp32.000), a Starter `worker` (Rp16.000) and a Small dedicated Postgres (Rp21.000) costs **Rp69.000/month**.

The sliders on **Runtime** → **Scaling** show the price before you save. See [Resources & Sizing](/docs/scaling/resources).

## What you don't pay for

- Sleeping apps, and apps that are stopped (a volume's disk is still charged).
- Apps you created but never deployed.
- Shared add-ons.

## New accounts

Until your first invoice is paid, the total of all your resources is capped at Rp150.000/month (your Billing page shows the current cap). Pay that invoice to go higher.

## Price changes

The prices above are today's. The [pricing page](https://wokku.cloud/pricing) and your Billing page always show the current ones. If a price increase raises your bill, you're emailed at least 30 days before it starts.

## Paying

You get one monthly invoice in Rupiah. Pay with QRIS, bank transfer or card. See [Invoices & Payment](/docs/billing/invoices).

## Self-hosting

The open-source edition has no billing. See [Self-hosting](/docs/oss/overview).
