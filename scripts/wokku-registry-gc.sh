#!/usr/bin/env bash
# Kamal's local Docker registry (kamal-docker-registry) accumulates image
# blobs on every deploy. Running `garbage-collect` inside the registry
# drops blobs no longer referenced by any tag, shrinking registry_data.
#
# --delete-untagged=true removes manifests with no tags at all (the cheap
# win; blobs become unreferenced and get swept). Without it only blobs
# are GC'd and untagged-manifest storage lingers.
#
# Tencent (control plane) only — Dokku hosts don't run kamal-docker-registry.

set -euo pipefail

if ! docker ps --format '{{.Names}}' | grep -qx kamal-docker-registry; then
  echo "wokku-registry-gc: kamal-docker-registry not running, skip"
  exit 0
fi

docker exec kamal-docker-registry \
  registry garbage-collect \
  --delete-untagged=true \
  /etc/docker/registry/config.yml 2>&1 \
  | tail -5

echo "wokku-registry-gc: done $(date -Iseconds)"
