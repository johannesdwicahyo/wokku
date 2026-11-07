---
title: GitHub Auto-Deploy
summary: Connect a GitHub repository so every push to your deploy branch deploys automatically.
last_updated: 2026-11-07
---

You'll install the Wokku GitHub App, pick a repo and branch, and then just push to GitHub.

## Connect a repository

:::tabs
::web-ui
1. Open your app → **Deploy** tab → **GitHub**.
2. First time only: click **Install GitHub App** and give it access to your repo.
3. Pick the repository, then the branch.

::cli
The Wokku GitHub App must already have access to the repo (install it once from the dashboard).

```bash
wokku github:repos                                   # repos the app can see
wokku github:connect my-app your-org/your-repo --branch main
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/github_connect \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"repo": "your-org/your-repo", "branch": "main"}'
```

::mcp
Ask Claude: *"Connect my-app to your-org/your-repo on main."*
:::

Connecting doesn't deploy by itself. The next push to the branch does.

## How it works

1. You push to the connected branch.
2. GitHub notifies Wokku.
3. Wokku builds and deploys that commit. Follow it on the **Deploy** tab.

## Change the deploy branch

:::tabs
::web-ui
On the **Apps** list, open the app's panel and edit **Branch**.

::cli
```bash
wokku apps:update my-app --branch develop
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deploy_branch": "develop"}'
```
:::

## Disconnect

:::tabs
::web-ui
**Deploy** tab → **GitHub** box → **Disconnect**.

::cli
```bash
wokku github:disconnect my-app
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/github_disconnect \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Disconnect GitHub from my-app."*
:::

You can still deploy with `git push wokku main` after disconnecting.

## See also

- [Preview deploys for pull requests](/docs/guides/preview-deploys)
- [Create & Deploy](/docs/apps/deploy)
