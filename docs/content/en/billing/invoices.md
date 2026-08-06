---
title: Invoices
summary: "Monthly invoice cycle: pre-invoice email → due date → 7-day grace → suspension. Pay via iPaymu. Mid-cycle changes prorated. Refunds via credit on the next bill."
eyebrow: billing
last_updated: 2026-05-29
---

# Invoices

Wokku's paid plans use a **monthly invoice** model. There's no metering, no deposit balance, no per-resource line items — just one flat invoice per workspace per month, plus optional add-on lines (extra seats on Team, mid-cycle proration on plan switches).

This page covers the full invoice lifecycle.

## The cycle

```text
day 0     subscribe (or upgrade)         → 7-day free trial begins
day 7     trial ends                     → first invoice generated
day +N    billing date (your anchor day) → invoice payable from now
day +N+7  due date                       → unpaid? grace period begins
day +N+14 grace period ends              → apps suspended if still unpaid
day +N+30 next billing date              → cycle repeats
```

Your **billing date** is anchored to the day of the month you first subscribed. If you sign up on the 15th, every monthly invoice lands on the 15th.

## What the invoice contains

A standard renewal invoice has one line:

```text
Wokku Pro · 2026-06-15 → 2026-07-15      Rp 225.000
                            Total:        Rp 225.000
```

On the Team plan with extra seats, you'll see a second line:

```text
Wokku Team · 2026-06-15 → 2026-07-15           Rp 750.000
Extra seats × 2 · 2026-06-15 → 2026-07-15      Rp  90.000
                                Total:         Rp 840.000
```

On a mid-cycle upgrade, you'll see a proration line:

```text
Pro → Team upgrade · prorated 18 of 30 days    Rp 315.000
                            Total:             Rp 315.000
```

## When invoices are generated

— **First invoice** — at the end of your 7-day trial
— **Renewal invoice** — 7 days before each billing date (via `Billing::IssueUpcomingInvoicesJob`, daily)
— **Proration invoice** — immediately on a mid-cycle upgrade

You get an email when the invoice is generated, with the amount and the iPaymu payment link.

## Paying

iPaymu handles all payment methods:

— **QRIS** — universal Indonesian QR — works with any e-wallet
— **Virtual Account** — BCA, Mandiri, BNI, BRI, Permata
— **E-wallet direct** — GoPay, OVO, DANA, LinkAja
— **Card** — Visa, Mastercard, Amex (3DS where supported)

You can pay from the email link or from `/dashboard/billing`. iPaymu's webhook updates the invoice status to `paid` within seconds of the bank confirmation.

## Grace period & suspension

If an invoice goes unpaid past the **due date**, you enter a 7-day grace period. Nothing visible happens — your apps stay up, your team keeps working. We email you reminders at days 1, 3, and 6.

If the invoice is still unpaid at **7 days past due**, `Billing::SuspendOverdueJob` runs and:

— Sets the workspace's `billing_status` to `suspended`
— Stops every paid app's containers (data preserved on disk; databases keep running)
— Emails the workspace owner

Pay the invoice → apps wake up automatically (within ~30 seconds of the webhook landing). No redeploy, no data loss.

## Mid-cycle changes

### Upgrade

Switch from Solo to Pro on day 18 of a 30-day cycle:

— A proration invoice is issued **immediately** for the difference, prorated for the days remaining: `(Pro_price - Solo_price) × (days_left / total_days)`
— The plan flips as soon as the proration invoice is paid (or right away if you're inside the trial)
— Your next regular renewal lands on the original billing date with the full new plan price

### Downgrade

Switch from Pro to Solo on day 18:

— No immediate invoice — you've already paid for Pro through the end of the cycle
— The plan change is **scheduled** for the next billing date
— Until then, you keep Pro
— The next renewal invoice is at the Solo price

This is intentional: you don't lose what you've paid for.

### Cancel

Cancel the plan from `/dashboard/plan`:

— Like downgrade: scheduled for end of cycle
— At the billing date, you fall back to the Free plan
— Your paid resources (Postgres beyond 100 MB, second Redis, larger boxes) are gracefully restricted: data preserved, but reads/writes that exceed the Free tier limits get a 503 with a "upgrade to continue" message

## Refunds

Paid invoices are **non-refundable** as a default. If something goes wrong on our side (hosting incident, billing bug, data loss caused by us), email [billing@wokku.cloud](mailto:billing@wokku.cloud) with the invoice number — we'll work it out case-by-case.

## API

```bash
curl https://wokku.cloud/api/v1/invoices \
  -H "Authorization: Bearer $TOKEN"
```

Returns every invoice for the active workspace, ordered newest first. Each row includes `status` (`pending` / `paid` / `failed` / `expired` / `refunded`), `amount_idr`, `period_start`, `period_end`, and the iPaymu payment URL if still unpaid.

## Self-hosted

Community Edition has **no invoice flow**. You run the platform yourself; there's nothing to bill.

## See also

— [Plans & Pricing](/docs/billing/plans) — what each plan costs and includes
— [Usage](/docs/billing/usage) — live view of plan + seat + bundle utilization
— [Plan Bundles](/docs/billing/plan-bundles) — DB / Redis / MinIO caps that ship with each plan
