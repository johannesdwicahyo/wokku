# Create an App

Create a new application on one of your connected servers.

## Create

:::tabs
::web-ui
1. Go to **Apps → New App**
2. Enter an app name (lowercase, alphanumeric, hyphens allowed)
3. Select the server to deploy on
4. Optionally set the deploy branch (default: `main`)
5. Click **Create**

::cli
```bash
wokku apps:create my-app --server my-server
```

Options:
- `--server` — server name or ID (required)
- `--branch` — deploy branch (default: main)

::api
```bash
curl -X POST https://wokku.dev/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-app", "server_id": 1, "deploy_branch": "main"}'
```

::mcp
Ask Claude: *"Create an app called my-app on server 1"*

::mobile
Tap **+** on the Apps screen, enter a name, select your server, and tap **Create**.
:::

## App Naming Rules

- Lowercase letters, numbers, and hyphens only
- Must start with a letter
- 3-30 characters
- Must be unique per server

## After Creation

Your app is created but not yet deployed. Next steps:

1. [Deploy your code](/docs/apps/deploy) via git push or GitHub
2. [Set environment variables](/docs/apps/config) for your app
3. [Add a custom domain](/docs/domains-ssl/custom-domains)
4. [Add a database](/docs/databases/create-link) if needed
