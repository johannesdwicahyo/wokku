#!/usr/bin/env bash
# One-command Wokku self-host install (Ubuntu/Debian, x86_64):
#
#   curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/install.sh | sudo bash
#
# Installs the control plane (docker compose) AND the app runtime on this
# box (Docker Swarm, local registry, Caddy, nixpacks, wokkud agent), then
# points you at the dashboard to create your admin account. Idempotent —
# safe to re-run. To connect ADDITIONAL servers later, use the one-line
# command the dashboard shows under admin → servers.
set -euo pipefail

# Everything runs inside main(), called on the last line: with
# `curl … | sudo bash` the script itself arrives on stdin, and any command
# that reads stdin (docker compose exec did) would swallow the rest of it —
# bash then exits 0 halfway through. A function is parsed whole first.
main() {

REPO_URL="${WOKKU_REPO_URL:-https://github.com/johannesdwicahyo/wokku}"
INSTALL_DIR="${WOKKU_INSTALL_DIR:-/opt/wokku}"

[ "$(id -u)" = "0" ] || { echo "run with sudo"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
log() { printf "\n→ %s\n" "$*"; }

# Fail fast with a clear message instead of a half-installed box.
preflight() {
  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null || true
  case "${ID:-}" in ubuntu|debian) ;; *) echo "Wokku supports Ubuntu or Debian (found: ${PRETTY_NAME:-unknown})."; exit 1 ;; esac
  [ "$(uname -m)" = "x86_64" ] || { echo "Wokku currently needs an x86_64 (amd64) server (found: $(uname -m))."; exit 1; }
  local mem_mb disk_gb
  mem_mb=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))
  [ "$mem_mb" -ge 1800 ] || { echo "Wokku needs at least 2 GB of RAM (this server has ${mem_mb} MB)."; exit 1; }
  disk_gb=$(( $(df -Pk / | awk 'NR==2{print $4}') / 1024 / 1024 ))
  if [ -d "$INSTALL_DIR" ]; then
    # Update: only the new image has to fit. (10 GB blocked updates on a
    # 20 GB VPS once images, build cache and swap had grown — 2026-11-17.)
    [ "$disk_gb" -ge 2 ] || { echo "Updating Wokku needs at least 2 GB of free disk (this server has ${disk_gb} GB free)."; echo "  Free space with: docker builder prune -f && docker image prune -f"; exit 1; }
  else
    [ "$disk_gb" -ge 10 ] || { echo "Wokku needs at least 10 GB of free disk (this server has ${disk_gb} GB free)."; exit 1; }
  fi
  if [ ! -d "$INSTALL_DIR" ] && command -v ss >/dev/null && ss -ltnH '( sport = :80 or sport = :443 )' | grep -q .; then
    echo "Ports 80/443 are already in use (another web server?). Wokku needs them for its router."; exit 1
  fi
}
log "checking this server"
preflight

log "docker + git"
command -v docker >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq docker.io docker-compose-v2 >/dev/null; }
systemctl enable --now docker >/dev/null 2>&1 || true
command -v git >/dev/null 2>&1 || apt-get install -y -qq git >/dev/null

if [ -d "$INSTALL_DIR/.git" ]; then
  log "updating ${INSTALL_DIR}"
  git -C "$INSTALL_DIR" pull -q
elif [ -d "$INSTALL_DIR" ]; then
  log "using existing ${INSTALL_DIR} (not a git checkout — left as-is)"
else
  log "fetching wokku into ${INSTALL_DIR}"
  git clone -q --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
[ -f docker-compose.yml ] || {
  echo "${INSTALL_DIR} exists but is not a wokku checkout (no docker-compose.yml)."
  echo "Remove it or set WOKKU_INSTALL_DIR to a different path, then re-run."
  exit 1
}

PUBLIC_IP=$(curl -fsS -4 -m 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
# Interpolated into .env and a rails runner string — accept only IP shapes.
[[ "$PUBLIC_IP" =~ ^[0-9a-fA-F:.]+$ ]] || { echo "could not determine this host's public IP"; exit 1; }
if [ ! -f .env ]; then
  log "generating .env (secret key, canonical domain)"
  # <ip>.sslip.io resolves to the ip with zero DNS setup, so Caddy can get
  # a real certificate immediately; point a domain later by editing .env.
  umask 077
  cat > .env <<EOF
SECRET_KEY_BASE=$(openssl rand -hex 64)
WOKKU_CANONICAL_DOMAIN=${WOKKU_CANONICAL_DOMAIN:-${PUBLIC_IP}.sslip.io}
# Only someone with this token can create the admin account at /setup.
WOKKU_SETUP_TOKEN=$(openssl rand -hex 16)

# Email (password resets, team invites, alerts). Without SMTP_ADDRESS no
# email is sent. Any SMTP provider works; then: docker compose up -d
# SMTP_ADDRESS=smtp.example.com
# SMTP_PORT=587
# SMTP_USERNAME=
# SMTP_PASSWORD=
# MAIL_FROM=Wokku <noreply@your-domain>
EOF
fi
# Installs from before the setup token existed: add one (only matters
# until the admin account is created).
grep -q '^WOKKU_SETUP_TOKEN=' .env || echo "WOKKU_SETUP_TOKEN=$(openssl rand -hex 16)" >> .env

log "downloading the control plane"
if docker compose pull -q web; then
  docker compose up -d
else
  log "prebuilt image unavailable — building from source instead (takes several minutes)"
  docker compose up -d --build
fi

log "waiting for the control plane to come up"
for _ in $(seq 1 100); do
  curl -fs -o /dev/null -m 2 http://127.0.0.1:3000/up && break
  sleep 3
done
curl -fsS -o /dev/null -m 2 http://127.0.0.1:3000/up || {
  echo "The control plane didn't start within 5 minutes. Logs: cd ${INSTALL_DIR} && docker compose logs web"; exit 1
}
# An update leaves the previous control-plane image untagged; remove only
# those (Wokku's own label), never anything else on the server.
docker image prune -f --filter "label=org.opencontainers.image.title=wokku" >/dev/null 2>&1 || true

log "registering this box as the first server"
TOKEN=$(docker compose exec -T web bin/rails runner \
  "s = Server.find_or_create_by!(name: \"main\") { |x| x.host = \"${PUBLIC_IP}\" }; puts s.ingest_token" \
  2>/dev/null | tail -1)
[ -n "$TOKEN" ] || { echo "could not mint an ingest token"; exit 1; }

log "installing the wokku runtime on this box (swarm, registry, caddy, nixpacks, wokkud)"
# Same box: the agent talks to the control plane over loopback, not via
# Caddy (which this very step installs).
curl -fsSL http://127.0.0.1:3000/install/wokkud.sh | WOKKU_CONTROL_URL=http://127.0.0.1:3000 bash -s -- "$TOKEN"

DOMAIN=$(grep '^WOKKU_CANONICAL_DOMAIN=' .env | cut -d= -f2)

# Does the public DOMAIN reach THIS box? Only our stack serves Rails'
# health page (a green body) at https://DOMAIN/up — a provider's proxy
# can redirect http->https too, so a redirect proves nothing. Typical miss:
# a budget VPS on a SHARED public IP (SSH on a high port) where the
# provider routes 80/443 by domain. Warn, don't fail: hairpin-NAT quirks
# can false-alarm. -k: Caddy may still be issuing the certificate.
log "checking that ${DOMAIN} reaches this server"
reached=""
for _ in $(seq 1 9); do  # ≤45s: route applies in ~15s, cert issues in the background
  body=$(curl -sk -m 4 "https://${DOMAIN}/up" 2>/dev/null || true)
  case "$body" in *green*) reached=1; break ;; esac
  sleep 1
done
if [ -z "$reached" ]; then
  cat <<EOF

  ! http://${DOMAIN} does not reach this server's router yet.
    If your provider SHARES one public IP between VPSes (common on budget
    VPS: SSH on a non-22 port, a private address on this box), add
    ${DOMAIN} in the provider's panel (VPS details → Domain / port 80+443
    forwarding). Otherwise check that ports 80 and 443 are open to the
    internet. HTTPS starts working as soon as the domain reaches this box.
EOF
fi
# Fresh install → the one-time setup link; an update → just the new version.
if docker compose exec -T web bin/rails runner 'exit(User.exists? ? 0 : 1)' >/dev/null 2>&1; then
  log "done — Wokku updated to $(docker compose exec -T web printenv WOKKU_VERSION | tr -d '\r'). Open https://${DOMAIN}"
else
  SETUP_TOKEN=$(grep '^WOKKU_SETUP_TOKEN=' .env | cut -d= -f2)
  log "done — open https://${DOMAIN}/setup?token=${SETUP_TOKEN} to create your admin account and deploy."
  echo "  (only this link can create the admin account; it stops working once the admin exists)"
fi
}

main "$@"
