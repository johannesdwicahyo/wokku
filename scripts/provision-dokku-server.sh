#!/usr/bin/env bash
#
# Wokku Dokku Server Provisioning Script
# =======================================
# Provisions a fresh Ubuntu 24.04 LTS bare metal server as a hardened
# Dokku worker node managed by wokku.cloud.
#
# Tested on: Ubuntu 24.04 LTS (Noble Numbat)
# Also works: Ubuntu 22.04 LTS
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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}── $1 ──${NC}"; }

# ── Pre-flight checks ─────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || err "This script must be run as root"

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    err "This script requires Ubuntu 22.04 or 24.04. Detected: ${PRETTY_NAME:-unknown}"
  fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Wokku Dokku Server Provisioning"
echo "════════════════════════════════════════════════════════════"
echo ""
log "OS: ${PRETTY_NAME:-unknown}"
log "RAM: $(free -h | awk '/^Mem:/{print $2}')"
log "CPU: $(nproc) cores"
log "Disk: $(df -h / | awk 'NR==2{print $2}')"

# ══════════════════════════════════════════════════════════════════
section "1. System Updates"
# ══════════════════════════════════════════════════════════════════

export DEBIAN_FRONTEND=noninteractive

# Ubuntu 24.04: Prevent needrestart from prompting during apt operations
if [ -f /etc/needrestart/needrestart.conf ]; then
  sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
  log "Disabled needrestart interactive prompts"
fi
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

apt-get update -qq
apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
log "System packages updated"

# ══════════════════════════════════════════════════════════════════
section "2. Essential Packages"
# ══════════════════════════════════════════════════════════════════

apt-get install -y -qq \
  curl wget git \
  ufw fail2ban \
  htop iotop ncdu \
  unattended-upgrades apt-listchanges \
  auditd audispd-plugins \
  chrony \
  apparmor apparmor-utils \
  libpam-pwquality \
  acl \
  jq
log "Essential packages installed"

# ══════════════════════════════════════════════════════════════════
section "3. Swap"
# ══════════════════════════════════════════════════════════════════

if [ ! -f /swapfile ]; then
  fallocate -l ${SWAP_SIZE} /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  log "Created ${SWAP_SIZE} swap"
else
  log "Swap already exists, skipping"
fi

# ══════════════════════════════════════════════════════════════════
section "4. Time Synchronization"
# ══════════════════════════════════════════════════════════════════

systemctl enable chrony
systemctl start chrony
log "Chrony NTP enabled (accurate timestamps for logs and certs)"

# ══════════════════════════════════════════════════════════════════
section "5. SSH Hardening"
# ══════════════════════════════════════════════════════════════════

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Cloud-init drops 50-cloud-init.conf with `PasswordAuthentication yes` which
# sshd honours over our 99-* drop-in (first-occurrence-wins semantics). Remove
# it so our hardening takes effect.
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf

cat > /etc/ssh/sshd_config.d/99-wokku-hardening.conf <<'SSHD'
# Wokku SSH hardening
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

# Session security
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding yes
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30

# Connection limits
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable unused auth
KerberosAuthentication no
GSSAPIAuthentication no

# Logging
LogLevel VERBOSE
SSHD

# Ubuntu 24.04 uses sshd_config.d includes by default
systemctl reload ssh || systemctl reload sshd
log "SSH hardened: key-only, no password, no X11, 3 max auth tries"

# ══════════════════════════════════════════════════════════════════
section "6. Firewall (UFW)"
# ══════════════════════════════════════════════════════════════════

ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Rate limit SSH to prevent brute force
ufw limit ${SSH_PORT}/tcp comment 'SSH rate limit'

ufw --force enable
log "UFW enabled: SSH(${SSH_PORT} rate-limited), HTTP(80), HTTPS(443)"

# ══════════════════════════════════════════════════════════════════
section "7. Fail2ban"
# ══════════════════════════════════════════════════════════════════

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

# Block repeated 404s (scanners/bots hitting Dokku proxy)
[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 86400
JAIL

systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban: SSH (3 retries, 2h ban), bot scanner (5 retries, 24h ban)"

# ══════════════════════════════════════════════════════════════════
section "8. Kernel Hardening"
# ══════════════════════════════════════════════════════════════════

cat > /etc/sysctl.d/99-wokku-hardening.conf <<'SYSCTL'
# ── Network attack prevention ──
# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 65535

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcasts (smurf attack prevention)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if not needed (reduces attack surface)
# Uncomment if you don't use IPv6:
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# ── Container workload tuning ──
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# ── Memory management ──
vm.swappiness = 10
vm.overcommit_memory = 0
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# ── Shared memory protection ──
kernel.randomize_va_space = 2

# ── Core dump restrictions ──
fs.suid_dumpable = 0
SYSCTL

sysctl --system > /dev/null 2>&1
log "Kernel hardened: anti-spoofing, SYN flood protection, ICMP hardening"

# ══════════════════════════════════════════════════════════════════
section "9. File System Hardening"
# ══════════════════════════════════════════════════════════════════

# Restrict core dumps
echo "* hard core 0" >> /etc/security/limits.d/99-wokku.conf
echo "* soft core 0" >> /etc/security/limits.d/99-wokku.conf

# Secure /tmp if it's not already a separate mount
if ! mount | grep -q "on /tmp "; then
  warn "/tmp is not a separate mount — consider mounting with noexec,nosuid for production"
fi

# Restrict su to sudo group only
if [ -f /etc/pam.d/su ]; then
  sed -i 's/^#\s*auth\s*required\s*pam_wheel.so/auth required pam_wheel.so/' /etc/pam.d/su 2>/dev/null || true
fi

# Set secure permissions on cron
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly 2>/dev/null || true
chmod 600 /etc/crontab 2>/dev/null || true

log "File system hardened: no core dumps, restricted cron, restricted su"

# ══════════════════════════════════════════════════════════════════
section "10. Audit Logging"
# ══════════════════════════════════════════════════════════════════

cat > /etc/audit/rules.d/wokku.rules <<'AUDIT'
# Monitor authentication events
-w /etc/pam.d/ -p wa -k auth_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor SSH config changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# Monitor Docker daemon changes
-w /etc/docker/ -p wa -k docker_config
-w /usr/bin/docker -p x -k docker_commands
-w /usr/bin/dokku -p x -k dokku_commands

# Monitor user/group changes
-w /usr/sbin/useradd -p x -k user_changes
-w /usr/sbin/userdel -p x -k user_changes
-w /usr/sbin/usermod -p x -k user_changes
AUDIT

systemctl enable auditd
systemctl restart auditd
log "Audit logging enabled: auth, SSH, Docker, Dokku commands"

# ══════════════════════════════════════════════════════════════════
section "11. Automatic Security Updates"
# ══════════════════════════════════════════════════════════════════

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
APT

# Ensure security updates are enabled (Ubuntu 24.04 format)
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED

log "Automatic security updates enabled (no auto-reboot)"

# ══════════════════════════════════════════════════════════════════
section "12. Docker Configuration"
# ══════════════════════════════════════════════════════════════════

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'DOCKER'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 4096
    }
  }
}
DOCKER
log "Docker configured: log rotation, no-new-privileges, ulimits, live-restore"

# ══════════════════════════════════════════════════════════════════
section "13. Install Dokku"
# ══════════════════════════════════════════════════════════════════

log "Installing Dokku ${DOKKU_VERSION} (this takes 2-5 minutes)..."
wget -NqO- https://dokku.com/bootstrap.sh | DOKKU_TAG=${DOKKU_VERSION} bash
log "Dokku ${DOKKU_VERSION} installed"

# ══════════════════════════════════════════════════════════════════
section "14. Dokku Plugins"
# ══════════════════════════════════════════════════════════════════

# Database plugins
dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres
dokku plugin:install https://github.com/dokku/dokku-redis.git redis
dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
dokku plugin:install https://github.com/dokku/dokku-mariadb.git mariadb
dokku plugin:install https://github.com/dokku/dokku-mongo.git mongo

# SSL + maintenance + ACL
dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git letsencrypt
dokku plugin:install https://github.com/dokku/dokku-maintenance.git maintenance
dokku plugin:install https://github.com/dokku-community/dokku-acl.git acl

# Enable ACL per-app enforcement by default
dokku config:set --global DOKKU_ACL_ALLOW_UNCONTROLLED=0

log "Plugins: postgres, redis, mysql, mariadb, mongo, letsencrypt, maintenance, acl"

# ══════════════════════════════════════════════════════════════════
# Metrics SSH: authorize the dokku user's pubkeys to log in as root too,
# so wokku.cloud's metrics collector (which uses the dokku-user SSH key
# stored on Server.ssh_private_key) can run `docker stats` as root.
# ══════════════════════════════════════════════════════════════════
if [ -f /home/dokku/.ssh/authorized_keys ]; then
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
  # Dokku wraps each entry with command="FINGERPRINT=... NAME=..."; strip
  # the prefix so root gets an unrestricted shell (needed for docker stats).
  grep -oE 'ssh-(rsa|ed25519|dss|ecdsa)[- a-zA-Z0-9+/=@._-]+' /home/dokku/.ssh/authorized_keys \
    | while IFS= read -r pubkey; do
        [ -z "$pubkey" ] && continue
        grep -qxF "$pubkey" /root/.ssh/authorized_keys || echo "$pubkey" >> /root/.ssh/authorized_keys
      done
  log "dokku pubkeys authorized for root (unwrapped, for metrics SSH)"
fi

# ══════════════════════════════════════════════════════════════════
# Host nginx needs to read maintenance.html from /home/dokku/<app>/maintenance/
# when `dokku maintenance:enable` is on. /home/dokku is mode 750 (dokku:dokku)
# so www-data gets EACCES on traverse and nginx returns 403 instead of the
# custom 503 page. Fix: put www-data in the dokku group, then restart nginx
# (reload won't re-spawn workers with new supplementary groups).
# ══════════════════════════════════════════════════════════════════
if id www-data &>/dev/null && getent group dokku &>/dev/null; then
  usermod -aG dokku www-data
  systemctl restart nginx 2>/dev/null || true
  log "www-data added to dokku group (nginx can serve maintenance pages)"
fi

# ══════════════════════════════════════════════════════════════════
section "15. Let's Encrypt Auto-Renewal"
# ══════════════════════════════════════════════════════════════════

dokku letsencrypt:cron-job --add
log "Let's Encrypt cron job added"

# ══════════════════════════════════════════════════════════════════
section "16. AppArmor"
# ══════════════════════════════════════════════════════════════════

if command -v aa-status &> /dev/null; then
  systemctl enable apparmor
  systemctl start apparmor
  PROFILES_LOADED=$(aa-status 2>/dev/null | grep "profiles are loaded" | awk '{print $1}' || echo "0")
  log "AppArmor enabled (${PROFILES_LOADED} profiles loaded)"
else
  warn "AppArmor not available, skipping"
fi

# ══════════════════════════════════════════════════════════════════
section "17. Disable Unnecessary Services"
# ══════════════════════════════════════════════════════════════════

# Disable services not needed on a container host
for svc in cups avahi-daemon bluetooth snapd; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl disable --now "$svc" 2>/dev/null || true
    log "Disabled: $svc"
  fi
done

# ══════════════════════════════════════════════════════════════════
section "18. Login Banner"
# ══════════════════════════════════════════════════════════════════

cat > /etc/motd <<'MOTD'
╔══════════════════════════════════════════════════╗
║  Wokku Dokku Server                             ║
║  Managed by wokku.cloud                         ║
║                                                  ║
║  Unauthorized access is prohibited.              ║
║  All sessions are logged and audited.            ║
╚══════════════════════════════════════════════════╝
MOTD

log "Login banner set"

# ══════════════════════════════════════════════════════════════════
section "19. Final Security Checks"
# ══════════════════════════════════════════════════════════════════

ISSUES=0

# Check SSH key exists
if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
  warn "No SSH authorized_keys found — add your key before testing!"
  ISSUES=$((ISSUES + 1))
fi

# Verify UFW is active
if ! ufw status | grep -q "Status: active"; then
  warn "UFW is not active!"
  ISSUES=$((ISSUES + 1))
fi

# Verify fail2ban is running
if ! systemctl is-active --quiet fail2ban; then
  warn "fail2ban is not running!"
  ISSUES=$((ISSUES + 1))
fi

# Verify Dokku is installed
if ! command -v dokku &> /dev/null; then
  warn "Dokku is not installed!"
  ISSUES=$((ISSUES + 1))
fi

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
  warn "Docker is not running!"
  ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
  log "All security checks passed"
else
  warn "${ISSUES} issue(s) found — review warnings above"
fi

# ══════════════════════════════════════════════════════════════════
section "Summary"
# ══════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
log "Dokku server provisioning complete!"
echo ""
echo "  Server:        $(hostname -I | awk '{print $1}')"
echo "  OS:            ${PRETTY_NAME:-unknown}"
echo "  Dokku:         $(dokku version)"
echo "  Docker:        $(docker --version | awk '{print $3}' | tr -d ',')"
echo ""
echo "  Plugins:       postgres, redis, mysql, mariadb, mongo,"
echo "                 letsencrypt, maintenance"
echo ""
echo "  Security:"
echo "    UFW:         SSH (rate-limited), HTTP, HTTPS"
echo "    fail2ban:    SSH (3 retries/2h), bots (5 retries/24h)"
echo "    SSH:         Key-only, no password, max 3 auth tries"
echo "    Kernel:      Anti-spoofing, SYN flood, ICMP hardening"
echo "    Docker:      no-new-privileges, log rotation, ulimits"
echo "    AppArmor:    $(aa-status 2>/dev/null | grep 'profiles are loaded' || echo 'N/A')"
echo "    Audit:       auth, SSH, Docker, Dokku commands logged"
echo "    Updates:     Automatic security patches (no auto-reboot)"
echo "    NTP:         Chrony time sync"
echo ""
echo "  Swap:          ${SWAP_SIZE}"
echo "  Log rotation:  10MB x 3 per container"
echo ""
echo "  Next steps:"
echo "  ─────────────"
echo "  1. Add SSH key:"
echo "     cat ~/.ssh/id_ed25519.pub | ssh root@<ip> dokku ssh-keys:add admin"
echo ""
echo "  2. Set global domain:"
echo "     ssh root@<ip> dokku domains:set-global <name>.wokku.cloud"
echo ""
echo "  3. Add to wokku.cloud:"
echo "     Dashboard → Servers → Add Server → enter IP"
echo ""
echo "════════════════════════════════════════════════════════════"
