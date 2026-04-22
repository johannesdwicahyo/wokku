#!/usr/bin/env bash
#
# Wokku Tencent (control-plane) host-state backup
# ────────────────────────────────────────────────
# Companion to scripts/dokku-host-backup.sh, but for the wokku.cloud
# control-plane host. The Postgres DB is handled by ControlPlaneBackupJob
# from inside the Rails container; this script backs up everything else
# that would be lost if the Tencent VM died:
#
#   /etc/wokku                                   — SSH gateway keys,
#                                                  known_hosts, authorized_keys
#   /var/lib/docker/volumes/wokku_storage/_data  — Active Storage uploads
#                                                  (if used)
#
# Output:
#   s3://<bucket>/hosts/<hostname>/YYYY/MM/DD/<hostname>-YYYYMMDDTHHMMSSZ.tgz
#
# Required env (all four — otherwise exits cleanly):
#   WOKKU_HOST_BACKUP_S3_BUCKET
#   WOKKU_HOST_BACKUP_S3_ENDPOINT
#   WOKKU_HOST_BACKUP_S3_ACCESS_KEY_ID
#   WOKKU_HOST_BACKUP_S3_SECRET_ACCESS_KEY
#
# Install from laptop once:
#   scp scripts/tencent-host-backup.sh deploy@<ip>:/tmp/
#   ssh deploy@<ip> 'sudo install -m 755 /tmp/tencent-host-backup.sh \
#                    /usr/local/sbin/wokku-host-backup && rm /tmp/tencent-host-backup.sh'
#   (then populate /etc/wokku/host-backup.env + enable the systemd timer)

set -euo pipefail

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

PATHS=(
  /etc/wokku
  /var/lib/docker/volumes/wokku_storage/_data
)

EXISTING=()
for p in "${PATHS[@]}"; do
  [ -e "$p" ] && EXISTING+=("$p")
done

if [ ${#EXISTING[@]} -eq 0 ]; then
  echo "wokku-host-backup: no paths exist, nothing to do." >&2
  exit 0
fi

tar czf "$TMP" --warning=no-file-changed "${EXISTING[@]}" 2>/dev/null || true
SIZE=$(stat -c%s "$TMP" 2>/dev/null || stat -f%z "$TMP")

export AWS_ACCESS_KEY_ID="$WOKKU_HOST_BACKUP_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$WOKKU_HOST_BACKUP_S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${WOKKU_HOST_BACKUP_S3_REGION:-auto}"

aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
    s3 cp "$TMP" "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/${KEY}" \
    --only-show-errors

echo "wokku-host-backup: uploaded $KEY ($SIZE bytes)"

CUTOFF=$(date -u -d "${RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
         date -u -v-"${RETENTION_DAYS}"d +%Y%m%d)

aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
    s3 ls "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/hosts/${HOSTNAME}/" --recursive 2>/dev/null | \
while read -r _ _ _ key; do
  stamp=$(echo "$key" | grep -oE '[0-9]{8}T' | head -1 | tr -d 'T')
  [ -z "$stamp" ] && continue
  if [ "$stamp" \< "$CUTOFF" ]; then
    aws --endpoint-url "$WOKKU_HOST_BACKUP_S3_ENDPOINT" \
        s3 rm "s3://${WOKKU_HOST_BACKUP_S3_BUCKET}/${key}" --only-show-errors
    echo "wokku-host-backup: pruned $key"
  fi
done
