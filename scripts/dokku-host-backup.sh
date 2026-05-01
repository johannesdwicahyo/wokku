#!/usr/bin/env bash
#
# Wokku Dokku host-state backup
# ──────────────────────────────
# Nightly backup of everything that lives on the Dokku host *outside* the
# tenant database services — those are handled by Wokku's BackupJob flow
# (dumps via `dokku <svc>:export`) and land at dbs/<server>/… in R2. This
# script covers the rest: per-app Dokku config, TLS certs, custom nginx
# snippets, and — most importantly — any persistent volume mounts the
# tenant attached via `dokku storage:mount`.
#
# Output:
#   s3://<bucket>/hosts/<hostname>/YYYY/MM/DD/<hostname>-YYYYMMDDTHHMMSSZ.tgz
#
# Requires (all four must be set; otherwise exits cleanly):
#   WOKKU_HOST_BACKUP_S3_BUCKET
#   WOKKU_HOST_BACKUP_S3_ENDPOINT
#   WOKKU_HOST_BACKUP_S3_ACCESS_KEY_ID
#   WOKKU_HOST_BACKUP_S3_SECRET_ACCESS_KEY
#
# Optional:
#   WOKKU_HOST_BACKUP_HOSTNAME  (overrides `hostname -s`)
#   WOKKU_HOST_BACKUP_RETENTION_DAYS  (default 30)
#
# Installed by provision-dokku-server.sh into /usr/local/sbin and run by
# a systemd timer (see /etc/systemd/system/wokku-host-backup.{service,timer}).

set -euo pipefail

# ── config from env ───────────────────────────────────────────────
for v in WOKKU_HOST_BACKUP_S3_BUCKET WOKKU_HOST_BACKUP_S3_ENDPOINT \
         WOKKU_HOST_BACKUP_S3_ACCESS_KEY_ID WOKKU_HOST_BACKUP_S3_SECRET_ACCESS_KEY; do
  if [ -z "${!v:-}" ]; then
    echo "wokku-host-backup: $v not set, skipping." >&2
    exit 0
  fi
done

HOSTNAME="${WOKKU_HOST_BACKUP_HOSTNAME:-$(hostname -s)}"
RETENTION_DAYS="${WOKKU_HOST_BACKUP_RETENTION_DAYS:-30}"
NOW_UTC=$(date -u +%Y%m%dT%H%M%SZ)
DATE_PATH=$(date -u +%Y/%m/%d)
KEY="hosts/${HOSTNAME}/${DATE_PATH}/${HOSTNAME}-${NOW_UTC}.tgz"
TMP=$(mktemp -t "wokku-host-backup-XXXXXX.tgz")

trap 'rm -f "$TMP"' EXIT

# ── paths we back up ──────────────────────────────────────────────
# Exclude tenant service data (/var/lib/dokku/services/**/data) — those are
# already dumped by the Rails-side BackupJob and tarring them would double
# the volume for no gain.
PATHS=(
  /etc/wokku
  /home/dokku
  /var/lib/dokku/data/storage
  /var/lib/dokku/plugins/available
  /var/lib/dokku/config
)

EXISTING=()
for p in "${PATHS[@]}"; do
  [ -e "$p" ] && EXISTING+=("$p")
done

if [ ${#EXISTING[@]} -eq 0 ]; then
  echo "wokku-host-backup: none of the expected paths exist, nothing to do." >&2
  exit 0
fi

# ── tar up ────────────────────────────────────────────────────────
# Dereference symlinks inside /home/dokku/<app>/tls/ so LE cert renewals
# via the letsencrypt plugin restore cleanly.
tar czf "$TMP" \
  --exclude='/var/lib/dokku/services/*/*/data' \
  --warning=no-file-changed \
  "${EXISTING[@]}" 2>/dev/null || true

SIZE=$(stat -c%s "$TMP" 2>/dev/null || stat -f%z "$TMP")

# ── upload via awscli (installed at provision time) ───────────────
export AWS_ACCESS_KEY_ID="$WOKKU_HOST_BACKUP_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$WOKKU_HOST_BACKUP_S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${WOKKU_HOST_BACKUP_S3_REGION:-auto}"

aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
    s3 cp "$TMP" "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/${KEY}" \
    --only-show-errors

echo "wokku-host-backup: uploaded $KEY ($SIZE bytes)"

# ── prune old ─────────────────────────────────────────────────────
CUTOFF=$(date -u -d "${RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
         date -u -v-"${RETENTION_DAYS}"d +%Y%m%d)

aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
    s3 ls "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/hosts/${HOSTNAME}/" --recursive 2>/dev/null | \
while read -r _ _ _ key; do
  # Each line: "YYYY-MM-DD HH:MM:SS  SIZE  hosts/<host>/YYYY/MM/DD/<host>-YYYYMMDDTHHMMSSZ.tgz"
  stamp=$(echo "$key" | grep -oE '[0-9]{8}T' | head -1 | tr -d 'T')
  [ -z "$stamp" ] && continue
  if [ "$stamp" \< "$CUTOFF" ]; then
    aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
        s3 rm "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/${key}" --only-show-errors
    echo "wokku-host-backup: pruned $key"
  fi
done
