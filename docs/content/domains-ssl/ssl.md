# SSL Certificates

Enable free SSL certificates via Let's Encrypt.

## Enable SSL

:::tabs
::web-ui
Go to your app → **Domains** → click **Enable SSL** next to a domain.

::cli
```bash
wokku ssl:enable my-app blog.example.com
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/domains/DOMAIN_ID/ssl \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Enable SSL for blog.example.com on my-app"*

::mobile
Tap your app → Domains → tap the lock icon to enable SSL.
:::

## How It Works

1. Wokku requests a certificate from Let's Encrypt
2. Let's Encrypt verifies domain ownership via HTTP challenge
3. Certificate is installed automatically
4. HTTPS is enabled, HTTP redirects to HTTPS

## Auto-Renewal

Certificates auto-renew before expiration. No action needed.

## Requirements

- Domain DNS must point to your Dokku server
- Port 80 must be accessible for the HTTP challenge
- Domain must be added to the app first
