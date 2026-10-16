# Service inventory

> **Current state.** This describes the live server as it runs today (Ansible
> roles and `stacks/`; CasaOS was retired 2026-10-03). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

Status as of 2026-10-15. "Managed by" tells you how to restart it (see RUNBOOK).

## systemd services (host)

| Service | Purpose | Notes |
|---|---|---|
| `docker` | container engine | `/etc/docker/daemon.json`: `default-runtime: nvidia`; `RequiresMountsFor=/DATA` (drop-in) |
| `DATA.mount`, `mnt-HDD_A.mount`, `mnt-HDD_B.mount` | the drives and the mergerfs pool | from `/etc/fstab`, `storage` role |
| ~~`casaos*`, `rclone`, `devmon@devmon`~~ | CasaOS | removed 2026-10-03 by the `deprecated` role (units, binaries, `/etc/casaos`, `/var/lib/casaos`, `udevil`) |
| `velocity` | Minecraft proxy | runs as system user `velocity` from `/opt/velocity` (sandboxed unit); managed by the `velocity` role |
| `velocity-firewall` | oneshot: applies the TCPShield firewall rules and the `raw` blocklist at boot | `Before=velocity.service`; managed by the `firewall` role |
| `unattended-upgrades` (via `apt-daily-upgrade.timer`) | automatic security updates | `base` role: Debian security + cloudflared; no automatic reboot |
| `cloudflared` | Cloudflare Tunnel client | token in `/etc/cloudflared/token`; ingress, DNS and Access in `tofu/` (`dash`, `crafty` -> nginx `127.0.0.1:8080`, Google login); updated by unattended-upgrades |
| `homelab-pull.timer` / `homelab-drift.timer` | pull agent (every 10 min) and drift check (daily 04:30) | `gitops` role; see RUNBOOK "Pull agent" |
| `sshd`, `smartd` | remote access (key-only), disk health | see NETWORK-AND-SECURITY |
| `gnome-user-share-webdav` (user unit) | GNOME "Personal File Sharing" (shows up as `apache2` on :42683) | **masked**; package intentionally left installed |

## Containers (compose stacks)

Compose files: `stacks/<name>/compose.yaml` in the repo, deployed to
`/opt/homelab/stacks/<name>/` by the `stacks` role. Data: `/srv/appdata/<name>/`.
All use `TZ=America/Los_Angeles`, `PUID`/`PGID` 1000, `restart: unless-stopped`.

| Container | Image | Port(s) | Notes |
|---|---|---|---|
| `crafty-container` | crafty-4:4.10.4 | 8111 (panel, https); **127.0.0.1:25565** | unprivileged; network `crafty_default` pinned to `172.18.0.0/16`; runs the Minecraft servers *inside* the container |
| `plex` | linuxserver/plex 1.43.4.10903-e5521bd8c-ls326 | 32400 (host network) | GPU via nvidia runtime + `/dev/dri`; data in `/srv/appdata/plex-nvidia` |
| `sonarr` | linuxserver/sonarr 3.0.10 | 8989 | still v3 |
| `radarr` | linuxserver/radarr 6.3.0 | 7878 | |
| `prowlarr` | linuxserver/prowlarr 2.5.2 | 9696 | |
| `overseerr` | linuxserver/overseerr 1.35.0 | 5055 | |
| `transmission` | linuxserver/transmission 4.1.3 | 9091 (UI), 51413 tcp+udp | login = the shared media login (SOPS, root-only `.env`) |
| `homepage` | gethomepage/homepage v2.5.0 | 3000 (LAN dashboard) | config from `stacks/homepage/config/`, mounted read-only; no app data. Networks pinned `172.30.0.0/24`, `172.30.1.0/24` |
| `nginx` | nginx 1.30.6-alpine | **127.0.0.1:8080** (host network) | web entry point for the tunnel: `dash.ethbra.com` -> Homepage, `crafty.ethbra.com` -> Crafty; any other Host gets 444. Config `stacks/nginx/config/`; restarted by the `stacks` role when it changes |
| `homepage-dockerproxy` | tecnativa/docker-socket-proxy v0.5.0 | none (internal network only) | Homepage's only Docker access: `CONTAINERS=1`, `POST=0` (read-only, writes get 403) |

The media apps reach each other at `192.168.1.22:<port>` (stored in their own
settings), not by container name or IP.

`/DATA/AppData/ollama-nvidia` and `open-webui-ollama` (on the drives) are
leftovers; Ollama was removed 2026-10-02, data kept.

## Minecraft

### Crafty-managed servers

Any of these can be the live server; the owner switches between them. **Which
one is running is not recorded here**: ask `scripts/crafty-servers.py` (it
reads Crafty's database and the container's processes). All of them use
`127.0.0.1:25565`, so only one runs at a time. Each one picks its own Java in
its Crafty execution command.

Snapshot 2026-10-15 (names and UUIDs change rarely; state changes often):

| Name | UUID | Loader / pack | Java | Auto-start |
|---|---|---|---|---|
| ATM10-8-2 | `7e6ceae2-b42d-4050-8c9d-18ae6d5ff250` | NeoForge 21.1.251, All the Mods 10 v8.2 (MC 1.21.1), 466 mods incl. PCF 1.3.1 and BlueMap 5.7 | `java` (25) | yes |
| Cam ATM10 | `1472e5eb-3e4d-4ce7-b2ac-723f83803f19` | NeoForge 21.1.209, All the Mods 10 v4.12 | 21 | no |
| rlcraft | `9669b6a3-592e-4959-92cb-84129b5f9e76` | Forge (RLCraft 2.9) | 8 | no |
| Vanilla | `796e824d-eb9b-48cb-aa8e-fdc3a2471781` | Purpur 1.21.10 | 21 | no |
| Plugins Test | `6a63dc93-96ef-44d6-9b9a-589ef5abb814` | Paper | `java` (25) | no |

**What any server needs to work behind Velocity** (`/srv/appdata/crafty/servers/<uuid>/`):

| Setting | Why |
|---|---|
| `server.properties`: `online-mode=false` | Velocity authenticates players; a backend that also does aborts the join |
| Velocity modern forwarding, same secret as Velocity | NeoForge/Forge 1.20.2+: Proxy Compatible Forge (`config/proxy-compatible-forge.toml`, `approvedProxyHosts = ["172.18.0.1"]`). Paper/Purpur: `config/paper-global.yml` `proxies.velocity` (enabled, online-mode, secret). Fabric: FabricProxy-Lite. Old Forge (e.g. 1.12 RLCraft) and plain vanilla can't do modern forwarding |
| Port 25565 in Crafty | the only port published (loopback) |

Optional per server: BlueMap (mod for NeoForge/Fabric, plugin for Paper) with
its web server on 8100, for the public map. Only the running server serves it.

### Velocity proxy (`/opt/velocity/`, managed by `ansible/roles/velocity`)

| File | Purpose |
|---|---|
| `velocity.jar` | Velocity 4.2.0 |
| `velocity.toml` | bind `192.168.1.22:25565`, modern forwarding, server `all` -> `127.0.0.1:25565`, MOTD/cap set by hand, passthrough off |
| `forwarding.secret` | shared secret (**secret**) |
| `start.sh` | JVM flags, including raised packet limits (big mod packs' sync packets exceed the default) |
| `server-icon.png` | shown in the server list (copied from a server, by hand) |
| `plugins/TCPShield-2.8.1.jar` | RealIP (works as the Velocity plugin) |
| `plugins/tcpshield/config.toml` | `only-allow-proxy-connections = true` |
| (journal) | proxy output: `journalctl -u velocity` |

## Versions to watch

| Component | Version | Note |
|---|---|---|
| Plex container | 1.41.3 | the old native Plex that wrote the migrated database was **1.42.2**; the container is older. It runs fine, but bumping the image tag is on the TODO list |
| Velocity | 4.2.0 | |
| RealIP / TCPShield plugin | 2.8.1 | |
| Proxy Compatible Forge | 1.3.1 | ~9x more downloaded than the alternative (NeoVelocity), more actively maintained |
