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
- Anything an Ansible role manages (Velocity, firewall, cloudflared, SSH,
  Docker daemon config) is changed in `ansible/`, never by hand on the box.

## Facts that save time
- IaC: Ansible lives in `ansible/`. Claude can verify roles against the live
  box without sudo: `cd ansible && ansible-playbook site.yml --check --diff
  -e ansible_become=false </dev/null | cat` (Ansible needs blocking stdio; the
  redirect and pipe provide it). Role `files/`/`templates/` are verbatim
  mirrors of live files: copy them from the box, never retype them.
  Without sudo it can't read root-only or service-owned files (`/opt/velocity`,
  the tunnel token); those tasks show as changed/failed there, so the owner's
  `-K` run is authoritative.
- Ansible handler names are global across roles: keep them unique, and restart
  handlers use `daemon_reload: true` so changed units are loaded first.
- Box: Debian 12, LAN IP 192.168.1.22, containers managed by CasaOS compose
  files in `/var/lib/casaos/apps/<app>/` (root-only). After editing, use
  `sudo docker compose up -d --force-recreate`; restart does not apply changes.
- ATM10 UUID in Crafty: `1472e5eb-3e4d-4ce7-b2ac-723f83803f19`
  (`/DATA/AppData/crafty/servers/<uuid>/`).
- ATM10 is a NeoForge pack: mods only, no Bukkit plugins.
- Real-IP chain: TCPShield -> Velocity (RealIP) -> PCF on ATM10. See docs/current/ARCHITECTURE.md.
- Velocity: `/opt/velocity`, runs as user `velocity`; logs via `journalctl -u velocity`.
  ATM10 logs: `.../servers/<uuid>/logs/latest.log`.
- ATM10 must run on **Java 21** (`/usr/lib/jvm/java-21-openjdk-amd64/bin/java`
  in Crafty's execution command); the container's default `java` is 25.
- Test Minecraft pings with `scripts/mc-status-ping.py HOST PORT`.
