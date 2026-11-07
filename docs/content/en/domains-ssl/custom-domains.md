---
title: Custom Domains & HTTPS
summary: Point your own domain at a Wokku app. HTTPS turns on by itself once DNS resolves.
last_updated: 2026-11-07
---

Add `www.example.com` to `my-app`, point DNS at Wokku, and the certificate is issued for you. Every app also works at `https://my-app.wokku.app` with no setup.

## 1. Add the domain

:::tabs
::web-ui
Open the app → **Settings → Domains** → **+ Add domain**. Enter the hostname and click **Add domain**. The panel shows the exact DNS records to create.

::cli
```bash
wokku domains:add my-app www.example.com
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/domains \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"hostname": "www.example.com"}'
```
:::

## 2. Point DNS at Wokku

Create one record at your DNS provider:

| Domain type | Record | Value |
|---|---|---|
| Subdomain (`www.example.com`, `app.example.com`) | `CNAME` | `my-app.wokku.app` |
| Root domain (`example.com`) | `A` | The IP shown in the **Add domain** panel |
| Root domain, if your provider supports CNAME flattening | `ALIAS` / `ANAME` | `my-app.wokku.app` |

DNS changes usually show up within minutes but can take up to 24 hours.

:::callout tip
Using Cloudflare? Set the record to **DNS only** (grey cloud) until the certificate is issued.
:::

## 3. HTTPS turns on by itself

Wokku checks your DNS every few minutes. Once the record points at Wokku, it issues a Let's Encrypt certificate and renews it before it expires. The domain shows an **SSL** badge when it's ready.

Plain HTTP requests always redirect to HTTPS. You can't turn this off.

If DNS is correct but the badge hasn't appeared, retry by hand:

:::tabs
::web-ui
On **Settings → Domains**, click **Enable SSL** next to the domain.

::cli
```bash
wokku certs:enable my-app www.example.com
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/domains/DOMAIN_ID/ssl \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Enable SSL for www.example.com on my-app"* (tool `wokku_enable_ssl`).
:::

## List and remove domains

:::tabs
::web-ui
Open **Settings → Domains** and click **Remove** next to the domain.

::cli
```bash
wokku domains my-app                           # list
wokku domains:remove my-app www.example.com    # remove one
wokku domains:clear my-app                     # remove every custom domain
```

::api
```bash
# DOMAIN_ID comes from the list
curl https://wokku.cloud/api/v1/apps/my-app/domains \
  -H "Authorization: Bearer $TOKEN"

curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/domains/DOMAIN_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Remove www.example.com from my-app"* (tools `wokku_list_domains`, `wokku_remove_domain`).
:::

## Troubleshooting

- **No SSL badge after an hour:** check the record with `dig www.example.com`. It must resolve to Wokku, not to an old host or a proxy.
- **Certificate error in the browser:** DNS is still propagating, or the domain was never added to the app. Add it first, then wait for the badge.
- **Root domain won't take a CNAME:** that's a DNS rule. Use the `A` record, or `ALIAS`/`ANAME` if your provider has it.
