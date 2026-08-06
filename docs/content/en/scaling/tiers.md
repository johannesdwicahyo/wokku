---
title: Box Tiers
summary: "Five box sizes covering hobby apps through production. The number you can run is decided by your plan; the size by the workload."
eyebrow: scaling
last_updated: 2026-05-29
---

# Box Tiers

A *box* is one Dokku container — what the rest of the industry calls a "dyno". Wokku has five box sizes; the number you can run is decided by your [plan](/docs/billing/plans), the size by the workload.

## The five sizes

| Tier | RAM | vCPU | Disk | Notes |
|---|---|---|---|---|
| **Sleeping** | 256 MB | shared, sleeps | — | Idle apps. Wakes on first request (~2-3 s). |
| **Small** | 512 MB | shared | 1 GB | Side projects, dev / staging, hobby apps. |
| **Medium** | 1 GB | shared | 2 GB | Production Rails / Django / Laravel at low-to-medium traffic. |
| **Large** | 2 GB | 1.0 dedicated | 4 GB | Production workloads with steady traffic + a worker. |
| **X-Large** | 4 GB | 2.0 dedicated | 8 GB | Heavy production (image processing, ML inference, big DB clients). Team plan add-on. |

Sleeping / Small / Medium run on shared vCPU — burst capacity depends on neighbour load. Large and X-Large get dedicated cores.

## How many you get

Each plan ships with a fixed quota of each size. See the full grid in [Plans & Pricing](/docs/billing/plans).

| Plan | Small | Medium | Large | Sleeping |
|---|---|---|---|---|
| Free | — | — | — | 3 |
| Solo | 3 | — | — | 3 |
| Pro | 3 | 2 | — | 3 |
| Team | 3 | 2 | 1 | 3 |

**Team** can buy extras: Rp 300.000/month per Extra Large, Rp 600.000/month per Extra X-Large. No metering — flat add-on price.

> Why "sleeping" is special: a sleeping box stays out of the active-box quota and costs nothing. The app idles its container; the next request wakes it in 2-3 seconds. Good for staging environments, demo apps, and low-traffic side projects.

## Picking a size

Rules of thumb that work for most apps:

— **Dev / staging** → Small (512 MB). Plenty for `bin/dev` workloads.
— **Production Rails / Django / Laravel at <50 req/s** → Small or Medium.
— **Production at 50–200 req/s** → Medium.
— **Background worker (Sidekiq / Celery / RQ) handling 100+ jobs/min** → Medium or Large depending on per-job memory.
— **Image / video processing, ML inference, heavy DB-side reports** → Large or X-Large.

When in doubt, start one size smaller and watch [metrics](/docs/monitoring/metrics) for a week. The dashboard surfaces p95 memory and CPU at 5-minute granularity — easy to spot a tier that's chronically under or over.

## Changing size

From the dashboard: open the app → **Scaling → Change Tier**. Apply.

Wokku rolls the container at the new size with no downtime: the proxy holds new connections for a couple of seconds while the new container starts; in-flight requests finish on the old container before it terminates.

Mid-cycle tier changes are **prorated** in the next invoice — you don't get charged a full month for an upgrade you did on day 28.

## Bundling vs splitting processes

The number of boxes you need depends on how you arrange your processes:

— **Bundle web + worker into one container** → 1 box. [How to](/docs/scaling/bundled-processes).
— **Split into separate process types** → N boxes, scales independently.

Pick bundled for small apps; pick split for production where you want web and worker to scale at different rates.

## Self-hosted

Wokku Community Edition has no tier system. You manage resources directly on your servers — pick container memory limits in your Dokku setup as you like.
