# Service inventory

> **Current state.** This describes the live server as it runs today (hand-managed
> and CasaOS). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

Status as of 2026-10-01. "Managed by" tells you how to restart it (see RUNBOOK).

## systemd services (host)

| Service | Purpose | Notes |
|---|---|---|
| `docker` | container engine | `/etc/docker/daemon.json`: `default-runtime: nvidia` |
| `casaos*` | CasaOS (gateway on :80, app management, storage) | manages the containers below |
| `velocity` | Minecraft proxy | runs as system user `velocity` from `/opt/velocity` (sandboxed unit); managed by the `velocity` role |
| `velocity-firewall` | oneshot: applies the TCPShield firewall rules at boot | `Before=velocity.service`; enabled, but was `inactive` on 2026-10-01 (not yet started this boot) |
| `iptables` (netfilter-persistent) | restores `/etc/iptables/rules.v4` at early boot | saved 2026-09-18; still contains the *old* Docker-based 25565 rules |
| `cloudflared` | Cloudflare Tunnel client | token in `/etc/cloudflared/token`; ingress set in the Cloudflare dashboard |
| `ollama` | local LLM server | loopback only, `127.0.0.1:11434` |
| `sshd`, `xrdp`, `smbd`/`nmbd`, `smartd` | remote access, file sharing, disk health | see NETWORK-AND-SECURITY |
| `plexmediaserver` | **old native Plex** | stopped + disabled; still installed pending removal |
| `noip-duc` | No-IP DDNS client | **being removed**: disabled, never running; `sudo apt purge noip-duc` pending |
| `gnome-user-share-webdav` (user unit) | GNOME "Personal File Sharing" (shows up as `apache2` on :42683) | **masked**; package intentionally left installed |

## Containers (CasaOS compose apps)

Compose files: `/var/lib/casaos/apps/<name>/docker-compose.yml` (root-only).
Data: `/DATA/AppData/<name>/`.

| Container | Image | Port(s) | Notes |
|---|---|---|---|
| `crafty-container` | crafty-4:4.10.4 | 8111 (panel, https), 8112, 8100; 19132/udp (Bedrock); **127.0.0.1:25565** | `privileged: true`; memory limit ~31 GiB; runs the Minecraft servers *inside* the container |
| `plex` (app `plex-nvidia`) | linuxserver/plex 1.41.3 | 32400 (host network) | GPU via nvidia runtime; has a `.env` (`AppID`, `PUID`, `PGID`) |
| `sonarr` | linuxserver/sonarr | 8989 | |
| `radarr` | linuxserver/radarr | 7878 | |
| `prowlarr` | linuxserver/prowlarr | 9696 | |
| `overseerr` | linuxserver/overseerr | 5055 | own network `overseerr_default` |
| `transmission` | linuxserver/transmission | 9091 (UI), 51413 tcp+udp | |

`/DATA/AppData/ollama-nvidia` and `open-webui-ollama` exist but have no
running containers (leftovers; Ollama now runs natively).

## Minecraft

### Crafty-managed servers

| Name | Type | Notes |
|---|---|---|
| **Cam ATM10** | NeoForge 21.1.209, MC 1.21.1 | **All the Mods 10 v4.12**, 448 mod jars, UUID `1472e5eb-3e4d-4ce7-b2ac-723f83803f19`, `-Xms16G -Xmx16G` |
| rlcraft, Vanilla (Purpur 1.21.10), Plugins Test (Paper) | | stopped; **all four Crafty records use `127.0.0.1:25565`, so only one can run at a time** |

ATM10 files worth knowing (all under `/DATA/AppData/crafty/servers/<uuid>/`,
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
