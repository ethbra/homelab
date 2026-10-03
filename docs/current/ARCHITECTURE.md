# Architecture

> **Current state.** This describes the live server as it runs today (hand-managed
> and CasaOS). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

## The machine

| | |
|---|---|
| Hostname / LAN IP | `Svalbard` / `192.168.1.22` (hardcoded in two places, see below) |
| OS | Debian 12 (bookworm), kernel 6.1 |
| CPU / GPU | i7-9700K (8 cores) / GeForce RTX 2070 (8 GB), driver 535.309.01 (Debian non-free) |
| Docker | 29.x, with `nvidia` set as the **default runtime** |
| Orchestration | CasaOS (manages the containers via compose files) |
| Host Java | Temurin 25 (runs Velocity only; ATM10 uses the JVM inside the Crafty container) |

### Storage

| Path | What |
|---|---|
| `/` (nvme0n1p2, 915 GB) | OS, Docker, CasaOS state in `/var/lib/casaos` |
| `/mnt/HDD_A`, `/mnt/HDD_B` (916 GB each) | data disks |
| `/DATA` (2.7 TB) | union mount of `/var/lib/casaos/files` + `HDD_A` + `HDD_B` |
| `/DATA/AppData/<app>/` | per-app persistent data |
| `/DATA/Media/{Movies,"TV Shows",Anime}` | the Plex/Sonarr/Radarr library |
| `/mnt/HDD_A/AppData/crafty/backups` | Crafty backups (bind-mounted explicitly) |

Because `/DATA` is a union, a file under `/DATA/AppData/x` may physically live on
any of the three branches. Paths under `/mnt/HDD_*` can also show Crafty data.

## Traffic flow: Minecraft (ATM10)

```
 Player
   |  play.ethbra.com  (DNS CNAME -> TCPShield)
   v
 TCPShield edge  --- DDoS protection; hides the home IP; adds the real player IP
   |  only 198.178.119.0/24 and 104.234.6.0/25 may reach us
   v
 192.168.1.22:25565   Velocity proxy (host process, systemd: velocity.service)
   |   RealIP plugin: validates TCPShield, recovers the real player IP
   |   Mojang authentication happens HERE
   |   modern forwarding (shared secret) passes IP + UUID downstream
   v
 127.0.0.1:25565      loopback only, published by the crafty-container
   |  (Docker bridge crafty_default, gateway 172.18.0.1)
   v
 ATM10 server (NeoForge 21.1.209, MC 1.21.1) inside crafty-container
      Proxy Compatible Forge mod: accepts forwarded data only from 172.18.0.1
      with the shared secret. online-mode=false (Velocity already authenticated).
```

Key properties, all of which must hold (see NETWORK-AND-SECURITY for the why):

1. ATM10's port is published on **loopback only**.
2. Velocity binds the **specific LAN IP**, not `0.0.0.0` (a wildcard bind
   collides with Docker's `127.0.0.1:25565`).
3. The Velocity port is firewalled to TCPShield's ranges (`TCPSHIELD_MC` chain).
4. The forwarding secret is identical in Velocity and PCF.

Crafty's own status polling talks to ATM10 directly inside the container
(`127.0.0.1:25565` in its server record). It never goes through Velocity.

## Traffic flow: media stack

```
 Overseerr (5055) --> Sonarr (8989) / Radarr (7878) --> Prowlarr (9696)
                                |                          (indexers)
                                v
                         Transmission (9091, torrent 51413)
                                |
                                v
                           /DATA/Media  <---  Plex (32400, host network, GPU)
```

All run as CasaOS-managed Docker containers. Plex uses `network_mode: host`, so
it shares the host's ports directly.

## Other pieces

- **Cloudflare Tunnel** (`cloudflared.service`) gives outbound-only access to
  whatever hostnames are configured in the Cloudflare dashboard. The ingress
  rules live there, not on this machine.
- **Ollama** runs natively on `127.0.0.1:11434` (loopback only).
- **CasaOS** web UI/gateway on port 80.
- **Remote access**: SSH (22), xrdp (3389), Samba (139/445).

## Where the "source of truth" is for each thing

| Thing | Authoritative location |
|---|---|
| Container definitions (ports, mounts, GPU) | `/var/lib/casaos/apps/<app>/docker-compose.yml` (root-only) |
| Plex compose variables | `/var/lib/casaos/apps/plex-nvidia/.env` |
| ATM10 world, mods, config | `/DATA/AppData/crafty/servers/<uuid>/` |
| Velocity | `~/projects/active/velocity/` |
| Firewall (boot-time) | `firewall-velocity-tcpshield.sh` run by `velocity-firewall.service`; older saved rules in `/etc/iptables/rules.v4` |
| Tunnel ingress | Cloudflare dashboard (not on disk) |
| TCPShield backend/domain | TCPShield dashboard (not on disk) |
