# Preview Deploys for Pull Requests

Get a live, isolated URL for every pull request — review real running code
before it merges. Wokku spins one up on PR open and tears it down on close.

:::callout note
PR previews are a **Pro** feature and require [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
connected to your app. See [Plans](/docs/billing/plans).
:::

## How it works

When you open a PR against your deploy branch, Wokku builds that branch into a
**temporary preview app** at its own URL (e.g. `my-app-pr-42.wokku.app`). Wokku
comments the URL on the PR. When the PR is merged or closed, the preview is
destroyed automatically.

## Enable previews

1. Connect the repo via [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
2. App → **Settings** → enable **PR Previews**
3. Open a pull request — Wokku builds it and comments the live URL

## What a preview gets

- Its own container(s) built from the PR branch
- A copy of the parent app's **config vars** (so it boots the same way)
- Its own subdomain with automatic SSL

:::callout warn
Previews share **add-ons** with the parent app by default (same `DATABASE_URL`).
Don't run destructive migrations or seed scripts from a preview against a
production database — point previews at a disposable database if your workflow
writes data.
:::

## Clean up

Previews self-destroy when the PR closes. To remove one manually:

:::tabs
::cli
```bash
wokku previews my-app                       # list active previews
wokku previews:destroy my-app --pr 42       # tear one down
```
:::

## Troubleshooting

- **No preview appeared** — confirm the app is Pro, GitHub is connected, and previews are enabled.
- **No PR comment** — Wokku needs permission to comment; re-check the GitHub connection.
- **Preview can't reach data** — it inherits the parent's config/add-ons; verify those are set.

## Next steps

- [GitHub Auto-Deploy](/docs/apps/github-autodeploy) · [Roll back a bad deploy](/docs/guides/rollback)
