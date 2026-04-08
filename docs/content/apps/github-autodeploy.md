# GitHub Auto-Deploy

Connect a GitHub repository to deploy automatically on every push.

## Connect a Repository

:::tabs
::web-ui
1. Go to your app's detail page
2. Click **Connect GitHub**
3. Authorize the Wokku GitHub App (first time only)
4. Select your repository and branch
5. Click **Connect**

::cli
```bash
wokku github:connect my-app --repo your-org/your-repo --branch main
```

::api
GitHub connection requires OAuth — use the Web UI for initial setup.

::mcp
Initial GitHub authorization requires the Web UI.

::mobile
Tap your app → **GitHub** to connect a repository.
:::

## How It Works

1. You push code to the connected branch
2. GitHub sends a webhook to Wokku
3. Wokku triggers a deploy on your Dokku server
4. Build output streams in real-time

## Change Deploy Branch

:::tabs
::web-ui
Go to your app → **Settings → GitHub** and change the deploy branch.

::cli
```bash
wokku apps:update my-app --branch develop
```

::api
```bash
curl -X PUT https://wokku.dev/api/v1/apps/my-app \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"deploy_branch": "develop"}'
```

::mcp
Ask Claude: *"Change my-app deploy branch to develop"*

::mobile
Tap your app → Settings → change the branch.
:::

## Disconnect

:::tabs
::web-ui
Go to your app → **Settings → GitHub** → **Disconnect**.

::cli
```bash
wokku github:disconnect my-app
```

::api
```bash
curl -X DELETE https://wokku.dev/api/v1/apps/my-app/github \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Disconnect GitHub from my-app"*

::mobile
Tap your app → Settings → Disconnect GitHub.
:::
