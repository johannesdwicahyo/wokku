---
title: Invoices & Payment
summary: How your monthly invoice is built, how to pay it, and what happens if it goes unpaid.
last_updated: 2026-11-07
---

You'll read your invoice, pay it, and check your usage on the Billing page.

## The cycle

Your **billing date** is the day of the month you first ran something paid. If that was the 15th, every invoice is for the 15th.

| When | What happens |
|---|---|
| 7 days before your billing date | Invoice issued and emailed (PDF attached, with a pay link) |
| Billing date | Invoice due |
| 7 days after the due date, still unpaid | Account suspended (see below) |

Free-only accounts never get an invoice. If there's nothing to bill, no invoice is issued.

## What's on an invoice

Each app process, volume and dedicated database gets its own lines:

| Line | Meaning |
|---|---|
| **Advance** | The coming month for each resource, at its current size |
| **Usage** | What each resource actually cost per day since your last invoice (dates shown) |
| **Already paid in advance for these days** | Subtracts what an earlier advance already covered |
| **Credit carried from last invoice** | Subtracts credit left over, for example after a downsize |

So you pay the next month up front, and the next invoice settles the difference with what you really ran. If credits are bigger than the charges, you pay Rp0 and the rest carries to the next invoice.

Your first invoice has no earlier advance to subtract: it covers your usage so far plus the coming month.

## Pay an invoice

1. Open the invoice email and click the pay link, or go to **Settings** → **Billing** and click **Pay now**.
2. On iPaymu's page, pay with QRIS (any e-wallet or banking app), bank transfer (BCA, BNI, BRI, Mandiri and more) or card (Visa, Mastercard).
3. The invoice turns **paid** once iPaymu confirms the payment.

Paying always happens in the dashboard. The CLI, API and MCP can list invoices and give you the pay link.

## If an invoice goes unpaid

Seven days after the due date, your account is suspended:

- Your running paid apps are stopped. Free sleeping apps keep running.
- You can't start, restart or deploy apps until you pay.
- You get an email listing the stopped apps.

Your data is kept. Pay every overdue invoice and your apps start again automatically; you get an email when they're back.

## The Billing page

Go to **Settings** → **Billing**:

- **Upcoming invoice** with a **Pay now** button, and your **last paid** invoice.
- **This month so far** and **Projected next invoice** (with its date), plus any **Credit**.
- Every app process and dedicated database with its size and monthly price.
- Your recent invoices, with **view all** and a **csv** export.

## List invoices

:::tabs
::web-ui
**Settings** → **Billing** → **view all**.

::cli
```bash
wokku billing:invoices
```
Unpaid invoices show their pay link.

::api
```bash
curl https://wokku.cloud/api/v1/billing/invoices \
  -H "Authorization: Bearer $TOKEN"
```
Each invoice has `reference`, `period`, `amount_idr`, `status` (`pending`, `paid`, `failed`, `expired`, `refunded`, `void`), `due_date`, `paid_at`, and `pay_url` while unpaid.

::mcp
Ask Claude: *"List my Wokku invoices"*
:::

## See also

- [Pricing](/docs/billing/pricing)
- [Resources & Sizing](/docs/scaling/resources)
