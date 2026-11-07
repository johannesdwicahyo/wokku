---
title: Preview Deploys for Pull Requests
summary: Get a live URL for every pull request, created when the PR opens and removed when it closes.
last_updated: 2026-11-07
---

You'll turn on PR previews for an app connected to GitHub, then open a pull request to get its own URL.

## Before you start

The app must be connected with [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

## Turn previews on

:::tabs
::web-ui
App → **Deploy** tab → **Previews** → tick **Enable PR previews**, save.

::cli
```bash
wokku previews:settings my-app --on
```

::api
```bash
curl -X PATCH https://wokku.cloud/api/v1/apps/my-app/preview_settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"preview_enabled": true}'
```
:::

Then open a pull request. Wokku builds the PR branch at `https://my-app-pr-42.wokku.app` (42 is the PR number) and comments the URL on the PR.

## Data

A preview gets a copy of the app's environment variables, **including `DATABASE_URL`**, so it talks to the same database as your app. The **Database strategy** setting is saved, but previews don't get their own database yet.

:::callout warning
Don't run migrations or seed scripts in a preview, and don't click through flows that write data you care about. If that's a risk for your app, leave previews off.
:::

## Limits and cleanup

- Up to 3 previews run at once per team. Past that, Wokku comments on the PR instead of building.
- A preview is destroyed when its PR is merged or closed. Idle previews sleep after 7 days and are destroyed after 30.

Remove one by hand:

:::tabs
::web-ui
**Deploy** tab → **Previews** → **Destroy** next to the preview.

::cli
```bash
wokku previews my-app              # list
wokku previews:destroy my-app 42   # tear down PR #42
```

::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/apps/my-app/previews/42 \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Destroy the PR 42 preview of my-app."*
:::

## Troubleshooting

- **No preview appeared**: check previews are on, the PR is on the connected repo, and your team has fewer than 3 previews.
- **No PR comment**: re-check the GitHub App still has access to the repo.

## Next steps

- [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
- [Roll back a bad deploy](/docs/guides/rollback)
