#!/usr/bin/env bash
# One-shot VPS setup for PandaNet. Tested target: Ubuntu 24.04 minimal, 1 vCPU / 1 GB.
# Run as root from inside the deploy/ directory:  bash setup.sh api.example.com
set -euo pipefail
DOMAIN="${1:?usage: setup.sh <api.domain.tld>}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg ufw sqlite3

# Node >= 22.5 (node:sqlite) via NodeSource — Ubuntu's own nodejs package is too old.
if ! command -v node >/dev/null 2>&1 || \
   ! node -e 'process.exit(+process.versions.node.split(".")[0] >= 22 ? 0 : 1)'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
node --version

# Caddy from its official repo (not in Ubuntu's default repos). Terminates TLS and
# proxies both HTTP and WebSocket traffic to the app with zero extra config.
if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi

# App user + layout
id -u pandanet &>/dev/null || useradd --system --home /opt/pandanet --shell /usr/sbin/nologin pandanet
mkdir -p /opt/pandanet/data
cp ../server.js ../mp.js ../client-sdk.js ../demo.html /opt/pandanet/
chown -R pandanet:pandanet /opt/pandanet

# Secrets — generated once, kept out of git. PROXY_KEY is what the platform's
# proxy presents in X-Proxy-Key; hand it to the platform operator over a secure
# channel when enabling platform-mediated mode.
if [ ! -f /opt/pandanet/env ]; then
  cat > /opt/pandanet/env <<EOF
ADMIN_KEY=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
SEED_KEY=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
PROXY_KEY=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
EOF
  chmod 600 /opt/pandanet/env
  chown pandanet:pandanet /opt/pandanet/env
fi

# systemd + Caddy. Restart (not just enable) so a re-run of this script picks
# up freshly copied code instead of leaving the old process serving.
cp pandanet.service /etc/systemd/system/
sed "s/api.example.com/${DOMAIN}/" Caddyfile > /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl enable pandanet
systemctl restart pandanet
systemctl reload caddy || systemctl restart caddy

# Firewall: SSH + HTTP(S) only; the app port stays loopback-only.
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw --force enable

# Nightly backup (SQLite online backup + 14-day rotation) + the restore helper
cp backup.sh restore.sh /opt/pandanet/ && chmod +x /opt/pandanet/backup.sh /opt/pandanet/restore.sh
cat > /etc/cron.d/pandanet-backup <<'EOF'
15 4 * * * root /opt/pandanet/backup.sh
EOF

echo
echo "Done. Verify:"
echo "  systemctl status pandanet --no-pager"
echo "  curl -s https://${DOMAIN}/api/health"
