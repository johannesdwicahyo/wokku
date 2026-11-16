---
cloud_prices: true
title: Resources & Sizing
summary: Pick CPU and RAM for each process with sliders or presets, or keep a free app sleeping.
last_updated: 2026-11-07
---

You'll choose how much CPU and RAM each process of your app gets. You pay per resource, per day. See [Pricing](/docs/billing/pricing).

## Change an app's size

:::tabs
::web-ui
1. Open your app → **Runtime** → **Scaling**.
2. For each process (`web`, `worker`, …), click a preset or drag the **CPU** and **RAM** sliders. The monthly price updates as you go.
3. Click **Save resources**. The containers restart with the new size.

::cli
```bash
wokku ps:resize my-app web --cpu 0.5 --memory 1024
```
Pass both `--cpu` and `--memory`.

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/ps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"resources": {"web": {"cpu": 0.5, "memory_mb": 1024}}}'
```

::mcp
Ask Claude: *"Resize the web process of my-app to 0.5 vCPU and 1 GB RAM"*
:::

## Presets

| Preset | CPU | RAM |
|---|---|---|
| Nano | 0.25 vCPU | 256 MB |
| Starter | 0.25 vCPU | 512 MB |
| Standard | 0.5 vCPU | 1 GB |
| Large | 1 vCPU | 2 GB |
| X-Large | 2 vCPU | 4 GB |

Sliders go from 0.25 to 4 vCPU (steps of 0.25) and 256 MB to 8 GB RAM (steps of 256 MB).

:::callout tip
256 MB is not enough for Rails. Pick 512 MB or more.
:::

## Free sleeping apps

The **Sleeping (free)** option on the `web` process costs nothing. You can have 3 sleeping apps.

- A sleeping app goes to sleep after 30 minutes without requests.
- The next request wakes it. The first response takes about 30 seconds.
- A sleeping app runs one instance only.

Need it always on? Pick any preset or slider size.

## Disk

If your app has a persistent volume, a **Volume disk** slider (0–100 GB) appears on the same page.

## When a change is billed

- Upsizes bill from that day. Each day is charged at the largest size you had that day.
- Downsizes credit your next invoice.
- Stopped and sleeping apps pay no CPU or RAM. A volume's disk is still charged.

## New-account limit

Until your first payment, the total of all your resources is capped (Rp150.000/month by default; the Billing page shows the current cap). Going over shows *"That size is over your account limit — add credit on the Billing page to go higher."*

## Databases

Dedicated databases are sized the same way, plus disk. See [Create & link a database](/docs/databases/create-link).

## See also

- [Scaling Processes](/docs/scaling/dynos) — run more instances
- [Bundling Processes](/docs/scaling/bundled-processes) — several processes in one container
