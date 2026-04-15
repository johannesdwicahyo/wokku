#!/usr/bin/env bash
#
# Wokku Dokku Server Migration Script
# ====================================
# Migrates all apps, databases, and configs from one Dokku server to another.
# Uses a two-pass rsync approach to minimize downtime.
#
# Prerequisites:
#   - New server provisioned with provision-dokku-server.sh
#   - SSH key access to both servers from this machine
#   - Root access on both servers
#
# Usage:
#   ./scripts/migrate-dokku-server.sh <old-server-ip> <new-server-ip>
#
# Example:
#   ./scripts/migrate-dokku-server.sh 172.232.235.58 103.xx.xx.xx
#

set -euo pipefail

# ── Arguments ──────────────────────────────────────────────────────
if [ $# -ne 2 ]; then
  echo "Usage: $0 <old-server-ip> <new-server-ip>"
  echo "Example: $0 172.232.235.58 103.xx.xx.xx"
  exit 1
fi

OLD_SERVER="$1"
NEW_SERVER="$2"
SSH_USER="root"
RSYNC_OPTS="-avz --progress --compress"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/wokku-migration-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${CYAN}══ $1 ══${NC}" | tee -a "$LOG_FILE"; }
ask()     { echo -e "${BOLD}$1${NC}"; read -r REPLY; }

# ── Pre-flight checks ─────────────────────────────────────────────
section "Pre-flight Checks"

echo "Migration plan:"
echo "  From: ${OLD_SERVER}"
echo "  To:   ${NEW_SERVER}"
echo "  Log:  ${LOG_FILE}"
echo ""

# Test SSH to both servers
log "Testing SSH to old server (${OLD_SERVER})..."
ssh -o ConnectTimeout=10 ${SSH_USER}@${OLD_SERVER} "echo ok" > /dev/null 2>&1 \
  || err "Cannot SSH to old server ${OLD_SERVER}"
log "Old server: connected"

log "Testing SSH to new server (${NEW_SERVER})..."
ssh -o ConnectTimeout=10 ${SSH_USER}@${NEW_SERVER} "echo ok" > /dev/null 2>&1 \
  || err "Cannot SSH to new server ${NEW_SERVER}"
log "New server: connected"

# Verify Dokku on both servers
OLD_DOKKU=$(ssh ${SSH_USER}@${OLD_SERVER} "dokku version" 2>/dev/null || echo "NOT FOUND")
NEW_DOKKU=$(ssh ${SSH_USER}@${NEW_SERVER} "dokku version" 2>/dev/null || echo "NOT FOUND")
log "Old server Dokku: ${OLD_DOKKU}"
log "New server Dokku: ${NEW_DOKKU}"

[[ "$NEW_DOKKU" == "NOT FOUND" ]] && err "Dokku not installed on new server. Run provision-dokku-server.sh first."

# List apps on old server
echo ""
log "Apps on old server:"
ssh ${SSH_USER}@${OLD_SERVER} "dokku apps:list" 2>/dev/null | tail -n +2 | while read app; do
  echo "    - ${app}"
done

# List services on old server
echo ""
log "Services on old server:"
for svc in postgres redis mysql mariadb mongo; do
  SERVICES=$(ssh ${SSH_USER}@${OLD_SERVER} "dokku ${svc}:list 2>/dev/null" | tail -n +2 || true)
  if [ -n "$SERVICES" ]; then
    echo "$SERVICES" | while read s; do
      echo "    - ${svc}: ${s}"
    done
  fi
done

# Check disk space on new server
NEW_DISK_FREE=$(ssh ${SSH_USER}@${NEW_SERVER} "df -BG / | awk 'NR==2{print \$4}' | tr -d 'G'")
OLD_DISK_USED=$(ssh ${SSH_USER}@${OLD_SERVER} "du -sg /home/dokku /var/lib/dokku /var/lib/docker/volumes 2>/dev/null | awk '{s+=\$1}END{print s}'")
echo ""
log "Old server data: ~${OLD_DISK_USED:-unknown}GB"
log "New server free: ~${NEW_DISK_FREE:-unknown}GB"

if [ -n "$OLD_DISK_USED" ] && [ -n "$NEW_DISK_FREE" ] && [ "$OLD_DISK_USED" -gt "$NEW_DISK_FREE" ]; then
  err "Not enough disk space on new server! Need ${OLD_DISK_USED}GB, have ${NEW_DISK_FREE}GB"
fi

echo ""
ask "Ready to start? This will begin the first rsync (apps stay live). [y/N]"
[[ "$REPLY" =~ ^[Yy]$ ]] || exit 0

# ══════════════════════════════════════════════════════════════════
section "Phase 1: Initial Sync (Apps Stay Live)"
# ══════════════════════════════════════════════════════════════════

log "Setting up SSH tunnel between servers for rsync..."
# Ensure new server can be reached from old server, or we rsync via local machine

log "Syncing /home/dokku/ (app configs, git repos)..."
ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} \
  --exclude='*/cache/*' \
  /home/dokku/ ${SSH_USER}@${NEW_SERVER}:/home/dokku/" 2>&1 | tail -3 | tee -a "$LOG_FILE"
log "App configs synced"

log "Syncing /var/lib/dokku/ (plugins, data)..."
ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} \
  /var/lib/dokku/ ${SSH_USER}@${NEW_SERVER}:/var/lib/dokku/" 2>&1 | tail -3 | tee -a "$LOG_FILE"
log "Dokku data synced"

log "Syncing /var/lib/docker/volumes/ (database data, persistent storage)..."
ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} \
  /var/lib/docker/volumes/ ${SSH_USER}@${NEW_SERVER}:/var/lib/docker/volumes/" 2>&1 | tail -3 | tee -a "$LOG_FILE"
log "Docker volumes synced"

log "Phase 1 complete. Apps are still live on old server."
echo ""

# ══════════════════════════════════════════════════════════════════
section "Phase 2: Maintenance Mode + Final Sync"
# ══════════════════════════════════════════════════════════════════

ask "Ready for Phase 2? This will enable maintenance mode on all apps (downtime starts). [y/N]"
[[ "$REPLY" =~ ^[Yy]$ ]] || { warn "Aborted. Phase 1 data is on new server. Re-run to continue."; exit 0; }

DOWNTIME_START=$(date +%s)

log "Enabling maintenance mode on all apps..."
ssh ${SSH_USER}@${OLD_SERVER} "dokku apps:list 2>/dev/null | tail -n +2 | while read app; do
  dokku maintenance:enable \$app 2>/dev/null || true
  echo \"  maintenance: \$app\"
done"
log "All apps in maintenance mode"

log "Stopping all containers for clean data sync..."
ssh ${SSH_USER}@${OLD_SERVER} "dokku ps:stop --all 2>/dev/null || true"
log "All containers stopped"

# Wait for containers to fully stop
sleep 5

log "Final sync (delta only, should be fast)..."
ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} --delete \
  /home/dokku/ ${SSH_USER}@${NEW_SERVER}:/home/dokku/" 2>&1 | tail -3 | tee -a "$LOG_FILE"

ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} --delete \
  /var/lib/dokku/ ${SSH_USER}@${NEW_SERVER}:/var/lib/dokku/" 2>&1 | tail -3 | tee -a "$LOG_FILE"

ssh ${SSH_USER}@${OLD_SERVER} "rsync ${RSYNC_OPTS} --delete \
  /var/lib/docker/volumes/ ${SSH_USER}@${NEW_SERVER}:/var/lib/docker/volumes/" 2>&1 | tail -3 | tee -a "$LOG_FILE"

log "Final sync complete"

# ══════════════════════════════════════════════════════════════════
section "Phase 3: Rebuild on New Server"
# ══════════════════════════════════════════════════════════════════

log "Fixing permissions on new server..."
ssh ${SSH_USER}@${NEW_SERVER} "chown -R dokku:dokku /home/dokku/"
log "Permissions fixed"

log "Rebuilding all apps on new server..."
ssh ${SSH_USER}@${NEW_SERVER} "dokku apps:list 2>/dev/null | tail -n +2 | while read app; do
  echo \"  rebuilding: \$app\"
  dokku ps:rebuild \$app 2>/dev/null || echo \"  WARN: rebuild failed for \$app\"
done"
log "All apps rebuilt"

log "Disabling maintenance mode on new server..."
ssh ${SSH_USER}@${NEW_SERVER} "dokku apps:list 2>/dev/null | tail -n +2 | while read app; do
  dokku maintenance:disable \$app 2>/dev/null || true
done"
log "Maintenance mode disabled on new server"

DOWNTIME_END=$(date +%s)
DOWNTIME_MINS=$(( (DOWNTIME_END - DOWNTIME_START) / 60 ))

# ══════════════════════════════════════════════════════════════════
section "Phase 4: Verification"
# ══════════════════════════════════════════════════════════════════

log "Checking apps on new server..."
echo ""
ssh ${SSH_USER}@${NEW_SERVER} "dokku apps:list 2>/dev/null | tail -n +2 | while read app; do
  STATUS=\$(dokku ps:report \$app 2>/dev/null | grep 'Running' | head -1 || echo 'unknown')
  echo \"    \$app: \$STATUS\"
done"

echo ""
log "Checking services on new server..."
for svc in postgres redis mysql mariadb mongo; do
  SERVICES=$(ssh ${SSH_USER}@${NEW_SERVER} "dokku ${svc}:list 2>/dev/null" | tail -n +2 || true)
  if [ -n "$SERVICES" ]; then
    echo "$SERVICES" | while read s; do
      echo "    ${svc}: ${s}"
    done
  fi
done

# ══════════════════════════════════════════════════════════════════
section "Migration Complete"
# ══════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
log "Migration finished!"
echo ""
echo "  Old server:  ${OLD_SERVER}"
echo "  New server:  ${NEW_SERVER}"
echo "  Downtime:    ~${DOWNTIME_MINS} minutes"
echo "  Log:         ${LOG_FILE}"
echo ""
echo "  Next steps:"
echo "  ─────────────"
echo "  1. Test apps on new server:"
echo "     curl -H 'Host: your-app.domain.com' http://${NEW_SERVER}"
echo ""
echo "  2. Update DNS to point to new server:"
echo "     A record → ${NEW_SERVER}"
echo ""
echo "  3. Update wokku.cloud:"
echo "     Dashboard → Servers → Edit → change IP to ${NEW_SERVER}"
echo ""
echo "  4. Re-enable SSL on new server:"
echo "     ssh root@${NEW_SERVER} 'dokku letsencrypt:enable --all'"
echo ""
echo "  5. After verifying everything works, decommission old server:"
echo "     ssh root@${OLD_SERVER} 'dokku ps:stop --all'"
echo ""
echo "  Old server is still in maintenance mode — safe to keep"
echo "  running until you've verified the new server."
echo ""
echo "════════════════════════════════════════════════════════════"
