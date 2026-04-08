# Backups

Schedule automatic backups and create on-demand snapshots of your databases.

## On-Demand Backup

:::tabs
::web-ui
Go to your database → **Backups** tab → **Create Backup**.

::cli
```bash
wokku backups:create my-db
```

::api
```bash
curl -X POST https://wokku.dev/api/v1/databases/DB_ID/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"Create a backup of my-db"*

::mobile
Tap database → Backups → **Create Backup**.
:::

## Backup Destinations

Configure where backups are stored. Go to **Servers → Backup Destination**.

| Provider | Description |
|----------|-------------|
| **AWS S3** | Amazon S3 buckets |
| **Cloudflare R2** | No egress fees |
| **MinIO** | Self-hosted S3-compatible |
| **Backblaze B2** | Cheapest storage |
| **DigitalOcean Spaces** | Simple object storage |
| **Wasabi** | No egress fees |

## Scheduled Backups

Configure daily automatic backups from the server's backup destination settings. Backups run at a configurable time with configurable retention.

## View Backups

:::tabs
::web-ui
Go to database → **Backups** tab to see all backups with timestamps and sizes.

::cli
```bash
wokku backups my-db
```

::api
```bash
curl https://wokku.dev/api/v1/databases/DB_ID/backups \
  -H "Authorization: Bearer $TOKEN"
```

::mcp
Ask Claude: *"List backups for my-db"*

::mobile
Tap database → **Backups** tab.
:::

## Restore

Restore a database from a backup via the Web UI. Go to database → Backups → click **Restore** on the backup you want.
