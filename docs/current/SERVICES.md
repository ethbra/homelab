# Service inventory

> **Current state.** This describes the live server as it runs today (Ansible
> roles and `stacks/`; CasaOS was retired 2026-10-03). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

Status as of 2026-10-03. "Managed by" tells you how to restart it (see RUNBOOK).

## systemd services (host)

| Service | Purpose | Notes |
|---|---|---|
| `docker` | container engine | `/etc/docker/daemon.json`: `default-runtime: nvidia`; `RequiresMountsFor=/DATA` (drop-in) |
| `DATA.mount`, `mnt-HDD_A.mount`, `mnt-HDD_B.mount` | the drives and the mergerfs pool | from `/etc/fstab`, `storage` role |
| ~~`casaos*`, `rclone`, `devmon@devmon`~~ | CasaOS | removed 2026-10-03 by the `deprecated` role (units, binaries, `/etc/casaos`, `/var/lib/casaos`, `udevil`) |
| `velocity` | Minecraft proxy | runs as system user `velocity` from `/opt/velocity` (sandboxed unit); managed by the `velocity` role |
| `velocity-firewall` | oneshot: applies the TCPShield firewall rules and the `raw` blocklist at boot | `Before=velocity.service`; managed by the `firewall` role |
| `unattended-upgrades` (via `apt-daily-upgrade.timer`) | automatic security updates | `base` role: Debian security + cloudflared; no automatic reboot |
| `cloudflared` | Cloudflare Tunnel client | token in `/etc/cloudflared/token`; ingress set in the Cloudflare dashboard; updated by unattended-upgrades |
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

The media apps reach each other at `192.168.1.22:<port>` (stored in their own
settings), not by container name or IP.

`/DATA/AppData/ollama-nvidia` and `open-webui-ollama` (on the drives) are
leftovers; Ollama was removed 2026-10-02, data kept.

## Minecraft

### Crafty-managed servers

| Name | Type | Notes |
|---|---|---|
| **Cam ATM10** | NeoForge 21.1.209, MC 1.21.1 | **All the Mods 10 v4.12**, 448 mod jars, UUID `1472e5eb-3e4d-4ce7-b2ac-723f83803f19`, `-Xms16G -Xmx16G` |
| rlcraft, Vanilla (Purpur 1.21.10), Plugins Test (Paper) | | stopped; **all four Crafty records use `127.0.0.1:25565`, so only one can run at a time** |

ATM10 files worth knowing (all under `/srv/appdata/crafty/servers/<uuid>/`,
linked from `config/atm10/`):

| File | Why it matters |
|---|---|
| `server.properties` | `online-mode=false` is **required** behind the proxy |
| `config/proxy-compatible-forge.toml` | forwarding mode/secret and `approvedProxyHosts = ["172.18.0.1"]` |
| `config/bcc-common.toml` | pack name/version (this is where "4.12" comes from) |
| `user_jvm_args.txt` | heap/GC flags and the `-Dlog4j2.configurationFile=` line (currently ineffective) |
| `log4j2-custom.xml` | log filter for Crafty's ping noise (currently not applied by the server) |

Mods added by us: `proxy-compatible-forge-1.3.1.jar`.

### Velocity proxy (`/opt/velocity/`, managed by `ansible/roles/velocity`)

| File | Purpose |
|---|---|
| `velocity.jar` | Velocity 4.2.0 |
| `velocity.toml` | bind `192.168.1.22:25565`, modern forwarding, server `all` -> `127.0.0.1:25565`, MOTD/cap set by hand, passthrough off |
| `forwarding.secret` | shared secret (**secret**) |
| `start.sh` | JVM flags, including raised packet limits for the big mod pack |
| `server-icon.png` | copied from ATM10, shown in the server list |
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
