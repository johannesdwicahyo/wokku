#!/usr/bin/env bash
# Wokku docker-host cleanup — run on every box with Docker (Tencent control
# plane + every Dokku data-plane host). Safe to run anytime; only touches
# stopped / dangling / unreferenced artefacts.
set -euo pipefail

CUTOFF_HOURS="${WOKKU_CLEANUP_CUTOFF_HOURS:-168}"  # default 7 days

log() { echo "wokku-docker-cleanup: $*"; }

log "starting (cutoff ${CUTOFF_HOURS}h)"

# 1. Stopped containers older than cutoff.
CONT=$(docker container prune -f --filter "until=${CUTOFF_HOURS}h" 2>/dev/null | grep -oE '[0-9.]+[KMGT]?B$' | tail -1)
log "containers pruned: ${CONT:-0B}"

# 2. Images not referenced by any container + older than cutoff.
#    `-a` is the aggressive flag — without it only dangling (<none>:<none>)
#    images are touched. On a PaaS host we keep generating tagged images,
#    and old versions accumulate — `-a` is what we want.
IMG=$(docker image prune -af --filter "until=${CUTOFF_HOURS}h" 2>/dev/null | grep -oE 'Total reclaimed space: .*' | tail -1)
log "images pruned: ${IMG:-0B}"

# 3. Volumes with no container attached. Kamal's buildx caches from
#    retired contexts were the big win here — 11 GB on first run.
VOL=$(docker volume prune -af 2>/dev/null | grep -oE 'Total reclaimed space: .*' | tail -1)
log "volumes pruned: ${VOL:-0B}"

# 4. Dangling networks (rare but free).
docker network prune -f >/dev/null 2>&1 || true

# 5. journald vacuum — the noisy twin of Docker cleanup. Keep 7 days.
journalctl --vacuum-time="${CUTOFF_HOURS}h" >/dev/null 2>&1 || true

# 6. Free -h summary (written to journal for trend-watching).
df -h / | awk 'NR==2 {printf "wokku-docker-cleanup: disk after cleanup — %s used, %s free (%s)\n", $3, $4, $5}'

log "done"
