#!/usr/bin/env bash
#
# Wokku Dokku Server Provisioning Script
# =======================================
# Run this on a fresh Ubuntu 22.04+ bare metal server to set it up as a
# Dokku worker node managed by wokku.cloud.
#
# Usage:
#   ssh root@<server-ip> 'bash -s' < scripts/provision-dokku-server.sh
#
# Or copy to the server and run:
#   scp scripts/provision-dokku-server.sh root@<server-ip>:/root/
#   ssh root@<server-ip> 'bash /root/provision-dokku-server.sh'
#
# After provisioning, add the server to wokku.cloud dashboard:
#   Dashboard → Servers → Add Server → enter IP and SSH key
#

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────
DOKKU_VERSION="v0.37.2"
SWAP_SIZE="4G"
SSH_PORT=22
WOKKU_USER="dokku"  # Wokku connects as the dokku user

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── Pre-flight checks ─────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || err "This script must be run as root"
[ -f /etc/os-release ] && . /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "This script is tested on Ubuntu. Proceeding anyway..."

log "Starting Wokku Dokku server provisioning..."
log "OS: ${PRETTY_NAME:-unknown}"
log "RAM: $(free -h | awk '/^Mem:/{print $2}')"
log "Disk: $(df -h / | awk 'NR==2{print $2}')"

# ── 1. System updates ─────────────────────────────────────────────
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# ── 2. Swap (important for bare metal with high RAM utilization) ──
if [ ! -f /swapfile ]; then
  log "Creating ${SWAP_SIZE} swap..."
  fallocate -l ${SWAP_SIZE} /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  # Tune swappiness for server workloads
  sysctl vm.swappiness=10
  echo "vm.swappiness=10" >> /etc/sysctl.conf
  log "Swap configured"
else
  log "Swap already exists, skipping"
fi

# ── 3. Essential packages ─────────────────────────────────────────
log "Installing essential packages..."
apt-get install -y -qq \
  curl wget git ufw fail2ban \
  htop iotop ncdu \
  unattended-upgrades apt-listchanges

# ── 4. Security hardening ─────────────────────────────────────────
log "Configuring firewall (UFW)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp    # SSH
ufw allow 80/tcp             # HTTP
ufw allow 443/tcp            # HTTPS
ufw --force enable
log "UFW enabled: SSH(${SSH_PORT}), HTTP(80), HTTPS(443)"

log "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
JAIL
systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban configured (5 retries, 1 hour ban)"

log "Hardening SSH..."
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
systemctl reload sshd
log "SSH hardened: root key-only, no password auth"

# ── 5. Automatic security updates ─────────────────────────────────
log "Enabling automatic security updates..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
log "Unattended upgrades enabled"

# ── 6. Docker log rotation ────────────────────────────────────────
log "Configuring Docker log rotation..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKER'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
DOCKER
log "Docker log rotation: max 10MB x 3 files per container"

# ── 7. Install Dokku ──────────────────────────────────────────────
log "Installing Dokku ${DOKKU_VERSION} (this takes 2-5 minutes)..."
wget -NqO- https://dokku.com/bootstrap.sh | DOKKU_TAG=${DOKKU_VERSION} bash
log "Dokku ${DOKKU_VERSION} installed"

# ── 8. Install Dokku plugins ──────────────────────────────────────
log "Installing Dokku plugins..."

# Database plugins
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
dokku plugin:install https://github.com/dokku/dokku-redis.git redis
dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
dokku plugin:install https://github.com/dokku/dokku-mariadb.git mariadb
dokku plugin:install https://github.com/dokku/dokku-mongo.git mongo

# SSL
dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt

# Maintenance mode
dokku plugin:install https://github.com/dokku/dokku-maintenance.git maintenance

log "All plugins installed"

# ── 9. Configure Let's Encrypt ────────────────────────────────────
log "Configuring Let's Encrypt auto-renewal..."
dokku letsencrypt:cron-job --add
log "Let's Encrypt cron job added"

# ── 10. System tuning for container workloads ─────────────────────
log "Tuning kernel parameters..."
cat >> /etc/sysctl.conf <<'SYSCTL'

# Wokku: Container workload tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
SYSCTL
sysctl -p
log "Kernel parameters tuned"

# ── 11. Set up limits for containers ──────────────────────────────
log "Configuring container resource defaults..."
# Docker restart policy for all future containers
# (Dokku handles this per-app, but this is a safety net)

# ── 12. Summary ───────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
log "Dokku server provisioning complete!"
echo ""
echo "  Server IP:     $(hostname -I | awk '{print $1}')"
echo "  Dokku version: $(dokku version)"
echo "  Plugins:       postgres, redis, mysql, mariadb, mongo, letsencrypt, maintenance"
echo "  Firewall:      UFW (SSH, HTTP, HTTPS)"
echo "  Security:      fail2ban, key-only SSH, auto security updates"
echo "  Docker logs:   10MB x 3 per container"
echo "  Swap:          ${SWAP_SIZE}"
echo ""
echo "  Next steps:"
echo "  1. Add your SSH public key:  cat ~/.ssh/id_ed25519.pub | ssh root@<ip> dokku ssh-keys:add admin"
echo "  2. Set global domain:        ssh root@<ip> dokku domains:set-global <server-name>.wokku.cloud"
echo "  3. Add to wokku.cloud:       Dashboard → Servers → Add Server"
echo ""
echo "════════════════════════════════════════════════════════════"
