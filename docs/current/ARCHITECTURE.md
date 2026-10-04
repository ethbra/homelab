# Architecture

> **Current state.** This describes the live server as it runs today (Ansible
> roles and `stacks/`; CasaOS was retired 2026-10-03). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

## The machine

| | |
|---|---|
| Hostname / LAN IP | `Svalbard` / `192.168.1.22` (hardcoded in two places, see below) |
| OS | Debian 12 (bookworm), kernel 6.1 |
| CPU / GPU | i7-9700K (8 cores) / GeForce RTX 2070 (8 GB), driver 535.309.01 (Debian non-free) |
| Docker | 29.x, with `nvidia` set as the **default runtime** |
| Orchestration | Docker Compose: `stacks/<app>/compose.yaml`, deployed to `/opt/homelab/stacks` by the `stacks` role |
| Host Java | Temurin 25 (runs Velocity only; ATM10 uses the JVM inside the Crafty container) |

### Storage

| Path | What |
|---|---|
| `/` (nvme0n1p2, 915 GB) | OS, Docker |
| `/srv/appdata/<app>/` (on `/`) | per-app persistent data, outside FUSE (Plex's is `plex-nvidia`) |
| `/mnt/HDD_A`, `/mnt/HDD_B` (916 GB each) | data disks, mounted by UUID from fstab (`nofail`) |
| `/DATA` (1.8 TB) | mergerfs pool of `HDD_A` + `HDD_B` only (fstab; `storage` role) |
| `/DATA/Media/{Movies,"TV Shows",Anime}` | the Plex/Sonarr/Radarr library |
| `/DATA/Downloads` | Transmission |
| `/mnt/HDD_A/AppData/crafty/backups` | Crafty backups (bind-mounted directly, outside the pool) |

New files go to the drive with the most free space (`category.create=mfs`,
`minfreespace=50G`). Docker has `RequiresMountsFor=/DATA`: if the pool can't
mount (a drive missing), the box boots but no container starts, so no app sees
an empty `/DATA`.

`/DATA/AppData` holds only `crafty/backups` (on HDD_A, bind-mounted directly).
The pre-cutover copies were deleted 2026-10-03.

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

All are compose stacks in `stacks/`. Plex uses `network_mode: host`, so it
shares the host's ports directly; the others are on the default bridge and
reach each other via `192.168.1.22:<port>`.

## Other pieces

- **Cloudflare Tunnel** (`cloudflared.service`) gives outbound-only access to
  whatever hostnames are configured in the Cloudflare dashboard. The ingress
  rules live there, not on this machine.
- **Remote access**: SSH (22, key-only).

## Where the "source of truth" is for each thing

| Thing | Authoritative location |
|---|---|
| Container definitions (ports, mounts, GPU) | `stacks/<app>/compose.yaml` -> `/opt/homelab/stacks/<app>/` |
| Container secrets (Transmission login) | `secrets/svalbard.yaml` (SOPS) -> root-only `/opt/homelab/stacks/<app>/.env` |
| Storage pool, drive mounts | `ansible/roles/storage` -> `/etc/fstab` |
| ATM10 world, mods, config | `/srv/appdata/crafty/servers/<uuid>/` |
| Velocity | `ansible/roles/velocity` -> `/opt/velocity/` |
| Firewall (boot-time) | `ansible/roles/firewall` -> `/usr/local/sbin/homelab-tcpshield-firewall`, run by `velocity-firewall.service` (TCPShield chain + `raw` blocklist) |
| Tunnel ingress | Cloudflare dashboard (not on disk) |
| TCPShield backend/domain | TCPShield dashboard (not on disk) |
