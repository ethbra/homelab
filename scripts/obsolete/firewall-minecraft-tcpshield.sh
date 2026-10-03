#!/usr/bin/env bash
set -euo pipefail

# Restricts port 25565 (Minecraft, published via Docker) to TCPShield's
# network only. Docker-published ports bypass the normal INPUT chain, so
# these rules must live in DOCKER-USER, which Docker always evaluates first.

PORT=25565
TCPSHIELD_RANGES=(198.178.119.0/24 104.234.6.0/25)

if [[ $EUID -ne 0 ]]; then
  echo "Error: run with sudo" >&2
  exit 1
fi

# Ensure DOCKER-USER exists (Docker creates it, but be defensive)
iptables -N DOCKER-USER 2>/dev/null || true

# Remove any prior rules we added for this port, so re-running is safe
while iptables -C DOCKER-USER -p tcp --dport "$PORT" -j DROP 2>/dev/null; do
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -j DROP
done
for range in "${TCPSHIELD_RANGES[@]}"; do
  while iptables -C DOCKER-USER -p tcp --dport "$PORT" -s "$range" -j ACCEPT 2>/dev/null; do
    iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$range" -j ACCEPT
  done
done

# Insert in order: allow TCPShield ranges, then drop everything else on this port.
# Inserted at the top (-I) in reverse order so ACCEPT ends up before DROP.
iptables -I DOCKER-USER -p tcp --dport "$PORT" -j DROP
for range in "${TCPSHIELD_RANGES[@]}"; do
  iptables -I DOCKER-USER -p tcp --dport "$PORT" -s "$range" -j ACCEPT
done

echo "Done. Current DOCKER-USER rules for port $PORT:"
iptables -L DOCKER-USER -n --line-numbers | grep -E "Chain|$PORT"

echo ""
echo "NOTE: these rules do not survive a reboot by default."
echo "To persist them, install iptables-persistent:"
echo "  sudo apt-get install -y iptables-persistent"
echo "  sudo netfilter-persistent save"
