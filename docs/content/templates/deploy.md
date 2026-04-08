# Deploy a Template

Deploy a pre-configured app template in one click.

## Deploy

:::tabs
::web-ui
1. Go to **Templates**
2. Find the template you want
3. Click **Deploy**
4. Enter an app name and select your server
5. Click **Deploy**

Wokku creates the app, sets up the Docker container, and configures default environment variables.

::cli
```bash
wokku deploy ghost --server my-server --name my-blog
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/templates/deploy \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"slug": "ghost", "server_id": 1, "name": "my-blog"}'
```

::mcp
Ask Claude: *"Deploy a Ghost blog called my-blog on server 1"*

::mobile
Tap **Templates** → find your template → **Deploy** → enter name → select server → confirm.
:::

## After Deployment

Once deployed, you can:

- [Add a custom domain](/docs/domains-ssl/custom-domains)
- [Enable SSL](/docs/domains-ssl/ssl)
- [Set environment variables](/docs/apps/config) to customize the app
- [View logs](/docs/apps/logs) to verify it's running
