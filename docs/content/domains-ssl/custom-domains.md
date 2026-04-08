# Custom Domains

Add custom domains to your apps.

## Add a Domain

:::tabs
::web-ui
Go to your app → **Domains** tab → **Add Domain**. Enter your domain name.

::cli
```bash
wokku domains:add my-app blog.example.com
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps/my-app/domains \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"domain": "blog.example.com"}'
```

::mcp
Ask Claude: *"Add the domain blog.example.com to my-app"*

::mobile
Tap your app → **Domains** → **+** → enter domain.
:::

## DNS Setup

Point your domain to your Dokku server:

| Record Type | Name | Value |
|-------------|------|-------|
| A | `blog.example.com` | Your server's IP address |
| CNAME | `blog.example.com` | `your-server.example.com` |

DNS changes can take up to 24 hours to propagate.

## Remove a Domain

:::tabs
::web-ui
Go to **Domains** → click the delete icon next to the domain.

::cli
```bash
wokku domains:remove my-app blog.example.com
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/apps/my-app/domains/DOMAIN_ID \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Remove blog.example.com from my-app"*

::mobile
Tap your app → Domains → swipe to delete.
:::
