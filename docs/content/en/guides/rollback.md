# Roll Back a Bad Deploy

Shipped something broken? Roll back to a previous release in seconds. Wokku keeps
every release, so reverting is instant — no rebuild.

## See your releases

:::tabs
::web-ui
App → **Activity / Releases** shows each deploy with its version and commit.

::cli
```bash
wokku releases my-app
```
:::

Each release is an immutable snapshot of the built image + config at deploy time.

## Roll back

:::tabs
::web-ui
On the **Releases** list, click **Roll back** on the release you want to restore.

::cli
```bash
# roll back to the immediately previous release
wokku rollback my-app

# or to a specific version
wokku rollback my-app --version 42
```

::mcp
Ask Claude: *"Roll back my-app to the previous release"*
:::

A rollback re-runs the chosen release's image — **no rebuild**, so it's fast.

## What a rollback does and doesn't do

- ✅ Restores the **application code** of the chosen release.
- ⚠️ **Does not undo database migrations.** If the bad deploy ran a destructive
  migration, rolling back the code won't restore the schema/data — restore from
  a [backup](/docs/databases/backups) if needed.
- ✅ Restores the config that shipped with that release.

:::callout warn
Write migrations to be **backward-compatible** (additive first, destructive
later) so a code rollback stays safe. This is the single biggest thing that
makes rollbacks painless.
:::

## Roll forward

Found and fixed the bug? Just deploy again — the fix becomes the newest release.
There's no special "un-rollback" step.

## Troubleshooting

- **Rollback didn't fix it** — the issue may be data/migration, not code. Check a backup restore.
- **Can't find the good release** — `wokku releases my-app` lists them with versions; pick the last known-good.

## Next steps

- [Backups](/docs/databases/backups) · [Production Readiness](/docs/apps/best-practices)
