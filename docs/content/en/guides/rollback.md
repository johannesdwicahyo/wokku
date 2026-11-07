---
title: Roll Back a Bad Deploy
summary: Go back to a previous release when a deploy breaks your app.
last_updated: 2026-11-07
---

You'll find the last good release and roll back to it.

## 1. Find the release

:::tabs
::web-ui
App → **Deploy** tab → **Releases** lists each release with its version and commit.

::cli
```bash
wokku releases my-app            # versions and descriptions
wokku releases my-app --json     # includes each release's ID
wokku releases:info my-app RELEASE_ID
```

::api
```bash
curl https://wokku.cloud/api/v1/apps/my-app/releases \
  -H "Authorization: Bearer $TOKEN"
```
:::

## 2. Roll back

:::tabs
::web-ui
Click **Rollback** on the release you want.

::cli
```bash
wokku rollback my-app RELEASE_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/apps/my-app/releases/RELEASE_ID/rollback \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Roll back my-app to the previous release."*
:::

The rollback shows up as a new release ("Rollback to vN").

## What a rollback does

- **Restores the code** of that release. It's fast when the release's image is still stored; otherwise Wokku rebuilds from the stored source.
- **Keeps your current environment variables.** It doesn't restore old config. Change it with [Environment Variables](/docs/apps/config) if needed.
- **Doesn't undo database migrations.** Restore from a [backup](/docs/databases/backups) if a migration damaged data.

Very old releases may no longer have a stored image or source. The rollback then fails with a message, and you'll need a fresh deploy.

:::callout tip
Write migrations to be backward-compatible (add first, remove later) so rolling back the code stays safe.
:::

## Roll forward

Fixed the bug? Deploy again. The fix becomes the newest release.

## Next steps

- [Backups](/docs/databases/backups)
- [Production Readiness](/docs/apps/best-practices)
