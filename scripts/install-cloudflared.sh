#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run with sudo" >&2
  exit 1
fi

# $HOME is /root under sudo, so resolve the invoking user's home instead
REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
TOKEN_FILE="$REAL_HOME/.cloudflared/tunnel-token"

TUNNEL_TOKEN=$(grep -oP '^TUNNEL_TOKEN=\K.*' "$TOKEN_FILE" 2>/dev/null || true)
if [[ -z "$TUNNEL_TOKEN" ]]; then
  echo "Error: TUNNEL_TOKEN not found in $TOKEN_FILE" >&2
  exit 1
fi

# Install cloudflared
echo ">>> Adding Cloudflare GPG key..."
install -d -m 0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

echo ">>> Adding apt repository..."
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | tee /etc/apt/sources.list.d/cloudflared.list

echo ">>> Installing cloudflared..."
apt-get update -q && apt-get install -y cloudflared

echo ">>> Installing tunnel as systemd service..."
cloudflared service install "$TUNNEL_TOKEN"

echo ""
echo "Done! Check status with: systemctl status cloudflared"
