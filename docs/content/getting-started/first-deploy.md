# Your First Deploy

Deploy an app to Wokku in under 5 minutes.

## Prerequisites

- A Wokku account ([sign up](/docs/getting-started/sign-up))
- A connected server ([connect one](/docs/getting-started/connect-server))

## Deploy from a Template

The fastest way to get started — deploy a pre-configured app with one click.

:::tabs
::web-ui
1. Go to **Templates** in the sidebar
2. Browse or search for an app (e.g., Ghost, Uptime Kuma, n8n)
3. Click **Deploy**
4. Select your server and give the app a name
5. Click **Deploy** — Wokku handles the rest

::cli
```bash
# List available templates
wokku templates

# Deploy one
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
Tap **Templates** in the bottom nav, find Ghost, tap **Deploy**, select your server, and confirm.
:::

## Deploy from GitHub

Connect a repo and deploy automatically on every push.

:::tabs
::web-ui
1. Go to **Apps → New App**
2. Click **Connect GitHub**
3. Select your repository and branch
4. Click **Create** — Wokku builds and deploys your app
5. Future pushes to that branch auto-deploy

::cli
```bash
wokku apps:create my-app --server my-server
wokku github:connect my-app --repo your-org/your-repo --branch main
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

Then connect GitHub from the dashboard (OAuth flow).

::mobile
Tap **+** on the Apps screen, enter a name, select server. GitHub connection is available from the app detail screen.
:::

## Deploy with Git Push

Push directly to your Dokku server.

:::tabs
::web-ui
After creating an app, copy the git remote URL from the app's overview page:

```bash
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::cli
```bash
wokku apps:create my-app --server my-server
# Copy the git URL from the output, then:
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::api
Create the app via API, then use `git push` to deploy:

```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "my-app", "server_id": 1}'
```

```bash
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

Then push with git:

```bash
git remote add dokku dokku@your-server:my-app
git push dokku main
```

::mobile
Create the app from Mobile, then use `git push` from your terminal.
:::

## Next Steps

- [Add a custom domain](/docs/domains-ssl/custom-domains)
- [Set environment variables](/docs/apps/config)
- [Add a database](/docs/databases/create-link)
