#!/usr/bin/env bash
# wokkud/deploy/install.sh — build locally, install the agent on a host.
# Usage: deploy/install.sh <ssh-host> <ingest-token> <control-url>
#   deploy/install.sh root@your-host "$TOKEN" https://paas.example.com
set -euo pipefail

HOST="${1:?usage: install.sh <ssh-host> <ingest-token> <control-url>}"
TOKEN="${2:?missing ingest token (shown when connecting a server)}"
URL="${3:?missing control-plane URL (the agent phones home here)}"
cd "$(dirname "$0")/.."

echo "→ building linux/amd64…"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "-X main.Version=$(git rev-parse --short HEAD)" -o /tmp/wokkud .

echo "→ installing on ${HOST}…"
scp /tmp/wokkud "${HOST}:/usr/local/bin/wokkud.new"
scp deploy/wokkud.service "${HOST}:/etc/systemd/system/wokkud.service"
ssh "${HOST}" "mkdir -p /etc/wokkud && umask 077 && printf 'WOKKUD_URL=%s\nWOKKUD_TOKEN=%s\n' '${URL}' '${TOKEN}' > /etc/wokkud/env"
echo "→ ensuring local registry, nixpacks, GC cron…"
# Registry: serves wokkud-built images to `git:from-image` (which always
# pulls) and keeps rollback tags alive across dokku's post-deploy rmi.
# Delete API on: Rails prunes tags via the HTTP API.
ssh "${HOST}" 'docker inspect wokku-registry >/dev/null 2>&1 || docker run -d --restart=always --name wokku-registry \
  -p 127.0.0.1:5000:5000 \
  -e REGISTRY_STORAGE_DELETE_ENABLED=true \
  -v /var/lib/wokku-registry:/var/lib/registry \
  registry:2'
# Pinned + checksummed (multi-tenant build host — no curl|bash supply chain).
# Upgrading: bump both values; sha from the GitHub release asset.
NIXPACKS_VERSION="1.41.0"
NIXPACKS_SHA256="0f55de7874507b9cf7502113120bd96f2ab6979f78d10eaf2eb2ade9207b3af6"
ssh "${HOST}" "command -v nixpacks >/dev/null 2>&1 || {
  curl -sL -o /tmp/nixpacks.tar.gz https://github.com/railwayapp/nixpacks/releases/download/v${NIXPACKS_VERSION}/nixpacks-v${NIXPACKS_VERSION}-x86_64-unknown-linux-musl.tar.gz
  echo '${NIXPACKS_SHA256}  /tmp/nixpacks.tar.gz' | sha256sum -c -
  tar -xzf /tmp/nixpacks.tar.gz -C /usr/local/bin nixpacks && rm /tmp/nixpacks.tar.gz
}"
# GC now lives in wokkud itself (registry.RunGCTicker, main.go) — busy-guarded
# against a concurrent build, unlike the old cron. Remove the legacy
# cron.weekly unit (live on jkt-01 since Jul 8, running --delete-untagged with
# no guard — the exact race the ticker exists to prevent) so upgraded hosts
# converge onto the ticker only.
ssh "${HOST}" 'rm -f /etc/cron.weekly/wokku-registry-gc'
# Caddy: the wokku router (Track B B1). Pinned + checksummed like nixpacks.
# Bootstrap config is admin-API-only — wokkud pushes the real config
# (shadow ports 8080/8443) on its first heartbeat after this install.
# Note: caddy's official checksums.txt ships SHA-512 (not SHA-256, despite
# the filename) — verified against the downloaded tarball; hence sha512sum.
CADDY_VERSION="2.11.4"
CADDY_SHA512="8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9"
ssh "${HOST}" "command -v caddy >/dev/null 2>&1 || {
  curl -sL -o /tmp/caddy.tar.gz https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz
  echo '${CADDY_SHA512}  /tmp/caddy.tar.gz' | sha512sum -c -
  tar -xzf /tmp/caddy.tar.gz -C /usr/local/bin caddy && rm /tmp/caddy.tar.gz
}"
scp deploy/wokku-caddy.service "${HOST}:/etc/systemd/system/wokku-caddy.service"
ssh "${HOST}" "mkdir -p /etc/wokku/caddy/certs && chmod 700 /etc/wokku/caddy /etc/wokku/caddy/certs
  [ -f /etc/wokku/caddy/config.json ] || printf '%s\n' '{\"admin\":{\"listen\":\"127.0.0.1:2019\"}}' > /etc/wokku/caddy/config.json
  systemctl daemon-reload && systemctl enable --now wokku-caddy"
# restart, not `enable --now`: --now is a no-op when the unit is already
# running, silently leaving the OLD binary live (bit us on the 4c rollout).
ssh "${HOST}" "mv /usr/local/bin/wokkud.new /usr/local/bin/wokkud && systemctl daemon-reload && systemctl enable wokkud && systemctl restart wokkud && sleep 2 && systemctl --no-pager status wokkud | head -5"
echo "✓ wokkud installed. Verify a heartbeat landed within ~30s."
