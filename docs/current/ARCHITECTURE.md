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
| CPU / GPU | i7-9700K (8 cores) / GeForce RTX 2070 SUPER (8 GB, Turing, compute 7.5), driver branch **580** from NVIDIA's CUDA apt repo, pinned (see "GPU driver" below). Until the cutover in RUNBOOK "NVIDIA driver" is done, the box still runs 535.309.01 (Debian non-free) |
| Docker | 29.x, with `nvidia` set as the **default runtime** |
| Orchestration | Docker Compose: `stacks/<app>/compose.yaml`, deployed to `/opt/homelab/stacks` by the `stacks` role |
| Host Java | Temurin 25 (runs Velocity only; Minecraft servers use the JVMs inside the Crafty container, chosen per server) |

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

## Traffic flow: Minecraft (whichever server Crafty runs)

```
 Player
   |  play.ethbra.com  (SRV _minecraft._tcp.play -> mc.ethbra.com, CNAME -> TCPShield;
   |                    the client sends "mc.ethbra.com" in its handshake)
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
 the live server inside crafty-container (scripts/crafty-servers.py says which)
      accepts Velocity modern forwarding with the shared secret (NeoForge: the
      PCF mod, also only from 172.18.0.1; Paper: built in).
      online-mode=false (Velocity already authenticated).
```

Key properties, all of which must hold (see NETWORK-AND-SECURITY for the why):

1. The Minecraft port (25565) is published on **loopback only**, whichever
   server is running.
2. Velocity binds the **specific LAN IP**, not `0.0.0.0` (a wildcard bind
   collides with Docker's `127.0.0.1:25565`).
3. The Velocity port is firewalled to TCPShield's ranges (`TCPSHIELD_MC` chain).
4. The forwarding secret is identical in Velocity and the server's forwarding
   config (PCF or Paper).

Crafty's own status polling talks to the server directly inside the container
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

## GPU driver

The `nvidia_toolkit` role owns the whole GPU stack:

| Piece | Source | Notes |
|---|---|---|
| Driver (`nvidia-driver`, `nvidia-driver-cuda`, `nvidia-kernel-dkms`) | NVIDIA's CUDA repo for Debian 12 (`/etc/apt/sources.list.d/nvidia-cuda.list`, key in `/etc/apt/keyrings/`) | proprietary kernel module, built by DKMS for every installed kernel |
| Branch pin | `nvidia-driver-pinning-580` (NVIDIA's package; `/etc/apt/preferences.d/nvidia-driver-pin`) | priority 1000 on `580*`, so `apt upgrade` never changes branch. Branch is `nvidia_toolkit_driver_branch` |
| Kernel headers | `linux-headers-amd64` | without it, kernels from unattended-upgrades come with no headers and DKMS can't build the module |
| Container toolkit | nvidia.github.io (`nvidia-container-toolkit.list`) | independent of the driver branch. The CUDA repo also has an older copy, which apt ignores (lower version) |

Why 580: Ollama 0.40 needs driver >= 550 and bundles CUDA 12.8 and 13.0
runners; 13.0 needs >= 580. 580 is NVIDIA's long-term support branch
(end of life mid-2028). See DECISIONS.

Updates: unattended-upgrades only takes Debian origins, so driver updates
within 580 are a manual `sudo apt upgrade` followed by a reboot. Kernel updates are
still automatic. The role's "module matches the installed driver" check (run
by every apply and the daily drift check) fails if the newest installed
kernel has no matching module, which is what a reboot would boot into.

Secure Boot is off (firmware in Setup Mode), so the unsigned DKMS module
loads. If Secure Boot is ever turned on, enroll DKMS's key first:
`sudo mokutil --import /var/lib/dkms/mok.pub`, then reboot and confirm in MOK manager.

## Other pieces

- **Cloudflare Tunnel** `Host` (`cloudflared.service`) gives outbound-only
  access to whatever hostnames the tunnel's ingress names. Two halves:
  OpenTofu (`tofu/`) declares what Cloudflare should do (DNS records, the
  tunnel's ingress, Access policies); `cloudflared` on this machine is the
  connector that dials out to Cloudflare and carries the traffic to local
  ports. The tunnel is remotely managed (token mode), so `cloudflared` picks
  up ingress changes from Cloudflare without a restart. No hostnames yet.
- **Remote access**: SSH (22, key-only).

## Where the "source of truth" is for each thing

| Thing | Authoritative location |
|---|---|
| Container definitions (ports, mounts, GPU) | `stacks/<app>/compose.yaml` -> `/opt/homelab/stacks/<app>/` |
| Container secrets (Transmission login) | `secrets/svalbard.yaml` (SOPS) -> root-only `/opt/homelab/stacks/<app>/.env` |
| Storage pool, drive mounts | `ansible/roles/storage` -> `/etc/fstab` |
| Minecraft servers (worlds, mods/plugins, config) | `/srv/appdata/crafty/servers/<uuid>/` (Crafty's database lists them; `scripts/crafty-servers.py`) |
| Velocity | `ansible/roles/velocity` -> `/opt/velocity/` |
| Firewall (boot-time) | `ansible/roles/firewall` -> `/usr/local/sbin/homelab-tcpshield-firewall`, run by `velocity-firewall.service` (TCPShield chain + `raw` blocklist) |
| DNS (`ethbra.com`) | `tofu/dns.tf` (OpenTofu, applied by hand with `scripts/tofu.sh`) |
| Tunnel ingress, Access | `tofu/tunnel.tf`, `tofu/access.tf` (OpenTofu, applied by hand) |
| TCPShield backend/domain | TCPShield dashboard (not on disk) |
