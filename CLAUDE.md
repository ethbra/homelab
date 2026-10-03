# Homelab project notes for Claude

Read `README.md`, then `PROGRESS.md`. Update `PROGRESS.md` after any change.

## Hard rules
- **Never print or write secret values** (forwarding secret, tunnel token,
  No-IP/Crafty credentials, Plex tokens). Reference their location only. If a
  command would print one, redact it.
- **Invariant:** ATM10 (`online-mode=false`) must stay published on
  `127.0.0.1:25565` only. Check `docker inspect crafty-container` before and
  after any crafty compose edit.
- No passwordless sudo here. Give the user the exact `sudo` commands; don't try.
- Don't `pkill -f`/`pgrep -f` with a pattern that appears in your own command
  line; it matches the tool's shell and kills it. Use anchored patterns like `^java ...` or `[x]yz`.
- Don't kill ATM10's Java process directly; restart it from Crafty.
- Don't move `velocity/` or `firewall-velocity-tcpshield.sh`; installed systemd
  units point at their current paths (see README).

## Facts that save time
- IaC: Ansible lives in `ansible/`. Claude can verify roles against the live
  box without sudo: `cd ansible && ansible-playbook site.yml --check --diff
  -e ansible_become=false </dev/null | cat` (Ansible needs blocking stdio; the
  redirect and pipe provide it). Role `files/`/`templates/` are verbatim
  mirrors of live files: copy them from the box, never retype them.
- Box: Debian 12, LAN IP 192.168.1.22, containers managed by CasaOS compose
  files in `/var/lib/casaos/apps/<app>/` (root-only). After editing, use
  `sudo docker compose up -d --force-recreate`; restart does not apply changes.
- ATM10 UUID in Crafty: `1472e5eb-3e4d-4ce7-b2ac-723f83803f19`
  (`/DATA/AppData/crafty/servers/<uuid>/`).
- ATM10 is a NeoForge pack: mods only, no Bukkit plugins.
- Real-IP chain: TCPShield -> Velocity (RealIP) -> PCF on ATM10. See docs/current/ARCHITECTURE.md.
- Velocity logs: `velocity/logs/latest.log`. ATM10 logs: `.../servers/<uuid>/logs/latest.log`.
- Test Minecraft pings with `scripts/mc-status-ping.py HOST PORT`.
