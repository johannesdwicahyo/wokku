---
title: Backups & Restore
summary: Nightly backups for dedicated databases, on-demand backups, downloads and restores.
last_updated: 2026-11-07
---

Check your database's backups, take one now, download it, or restore it.

## What gets backed up

| Database | Automatic backups |
|---|---|
| Dedicated Postgres, MySQL, MariaDB, MongoDB, Redis | Nightly. Wokku keeps at least the last 7 daily backups. |
| Shared Postgres, MariaDB | None. A final snapshot is taken when you remove the add-on. |
| Shared Redis | Never backed up. |

Backups are encrypted, and Wokku manages where they're stored.

:::callout tip
Need backups for a shared database? [Upgrade it to dedicated](/docs/databases/create-link#upgrade-to-dedicated). Your data moves over.
:::

## List backups

:::tabs
::web-ui
Click **Databases** in the sidebar → your database → **Backups**.

::cli
```bash
wokku databases          # find the database name
wokku backups my-db
```

::api
```bash
curl https://wokku.cloud/api/v1/databases/my-db/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"List backups for my-db"* (tool `wokku_list_backups`).
:::

## Back up now

:::tabs
::web-ui
On the **Backups** tab, click **Backup now**.

::cli
```bash
wokku backups:capture my-db
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/databases/my-db/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Back up my-db now"* (tool `wokku_create_backup`).
:::

## Download a backup

:::tabs
::web-ui
On the **Backups** tab, click **Download** next to a completed backup.

::cli
```bash
wokku backups:download my-db BACKUP_ID my-db.dump
```

Leave out the file name to print a short-lived download URL instead.

::api
```bash
curl https://wokku.cloud/api/v1/databases/my-db/backups/BACKUP_ID/download \
  -H "Authorization: Bearer $TOKEN"
```

Returns a download URL that expires after 5 minutes.

::mcp
Ask Claude: *"Give me a download link for the latest backup of my-db"* (tool `wokku_get_backup_download_url`).
:::

## Restore a backup

:::callout warning
A restore **overwrites** the database. Anything written since the backup is lost.
:::

:::tabs
::web-ui
On the **Backups** tab, click **Restore** next to a backup, then **Yes, restore now**.

::cli
```bash
wokku backups:restore my-db BACKUP_ID
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/databases/my-db/backups/BACKUP_ID/restore \
  -H "Authorization: Bearer $TOKEN"
```

The restore runs in the background.

::mcp
Ask Claude: *"Restore my-db from backup BACKUP_ID"* (tool `wokku_restore_backup`).
:::

Redis backups can't be restored from the dashboard. Download the backup and contact support.

## Self-hosting

Running Wokku on your own server? You choose where backups go (S3, R2, Backblaze B2 and other S3-compatible storage). See [Self-hosting](/docs/oss/overview).
