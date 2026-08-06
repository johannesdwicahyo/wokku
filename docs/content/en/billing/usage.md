---
title: Usage
summary: "See what you're paying for at a glance: current plan, box quota used, addon bundle usage, and seat headroom. Updated live."
eyebrow: billing
last_updated: 2026-05-29
---

# Usage

The **Usage** page in the dashboard is the single screen for seeing what your plan covers vs what you're actually using. Go to **Settings → Usage** (or `/dashboard/usage`).

## What you'll see

### Plan summary

The top section shows:

— Your current plan name and monthly price
— Trial status and days remaining (if you're inside a trial)
— Next invoice date and amount

### Box quota

A four-tile row showing **used / included** for each box size on your plan: Small / Medium / Large / Sleeping. The number reflects every container actually running, including bundled-process containers (which count as one box even though they run multiple processes).

When you go over quota, the tile shows "over quota" in red. New deploys at that size will be blocked until you scale down or upgrade the plan.

### Addon bundle

Three tiles for the resources bundled with your plan:

— **Postgres** — count of databases vs the 1-included; the cap is the per-tenant size limit (e.g. 100 MB on Free, 1 GB on Solo, 10 GB on Team)
— **Redis** — same shape; the cap is the memory limit
— **Object Storage** — MinIO bucket count + bucket-size cap

### Apps table

Every app you own, with status (running / sleeping / crashed / stopped), the box tier it runs on, and the number of containers. Click any row to jump to the app's overview.

## How billing works

Wokku uses a **monthly invoice** model — no hourly metering, no deposit balance. See [Plans & Pricing](/docs/billing/plans#how-billing-works) for the full cycle: pre-invoice email → due date → 7-day grace → suspension. For the deeper dive on invoice generation, proration, and refunds see [Invoices](/docs/billing/invoices).

## Upgrade / downgrade

Two places to change plans:

— **Plan switcher** on `/dashboard/plan` — pick a plan, confirm. Mid-cycle upgrades issue a prorated invoice immediately; downgrades are scheduled for your next billing date.
— **Box scaling** on `/dashboard/apps/<app>/scaling` — changes the size of an individual container without touching the plan. Useful when you have headroom on the box quota but want a beefier container for one app.

## Payment methods

iPaymu handles everything:

— **QRIS** — pay with any Indonesian e-wallet (GoPay, OVO, DANA, ShopeePay, BCA mobile, Mandiri, BRImo, etc.)
— **Virtual Account** — BCA, Mandiri, BNI, BRI, Permata
— **E-wallet direct** — GoPay, OVO, DANA, LinkAja
— **Card** — Visa, Mastercard, Amex (3DS where supported)

The invoice issued 7 days before the billing date includes the iPaymu payment URL. The dashboard's billing page always has a "Pay now" button for unpaid invoices.

## Seat usage (Team plan)

If you're on Team:

— Seats included with the plan: 3
— Extra seats: Rp 45.000 each / month, prorated for partial cycles
— A small banner appears at the top of `/dashboard/team` when you're over the included seat count — the overage gets added to your next invoice automatically

## Self-hosted

Community Edition has no billing surface. The usage page in CE shows resource counts only, no costs.
