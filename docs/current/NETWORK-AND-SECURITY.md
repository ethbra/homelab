# Network and security

> **Current state.** This describes the live server as it runs today (hand-managed
> and CasaOS). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

> Verified from the machine on 2026-10-01 **without root**. Anything marked
> "verify" needs `sudo` or a look at the router/Cloudflare/TCPShield dashboards,
> none of which can be inspected from here.

## Identity of the network

| | |
|---|---|
| LAN IP | `192.168.1.22` |
| Home WAN IP | dynamic (value deliberately not recorded in this repo; check with `curl -4 ifconfig.me`). **No DDNS is running** (No-IP removed 2026-10-01) |
| Router: static port-forward | **only** TCP `25565` -> `192.168.1.22:25565` (confirmed by owner, 2026-10-01) |
| Router: dynamic (UPnP / NAT-PMP) | **Plex** asks the router for WAN port `17511` and reports itself reachable from the internet (seen in its log 2026-10-01); **Transmission** has `port-forwarding-enabled: true` for peer port `51413`. These are *not* static forwards, so they won't show up in a forward list. Check the router's UPnP table, or turn UPnP off |
| Public Minecraft hostname | `play.ethbra.com` -> CNAME to TCPShield |
| TCPShield source ranges | `198.178.119.0/24`, `104.234.6.0/25` (IPv4 only; list at https://tcpshield.com/v4/) |
| Docker bridges | `docker0` 172.17/16, `crafty_default` 172.18.0.0/16 (gw `172.18.0.1`), others 172.19, 172.21 |

## Listening ports

Bind column matters: `0.0.0.0` = reachable from the whole LAN (and the
internet if the router forwards it); `127.0.0.1` = this machine only.

| Port | Proto | Bind | What | Intended exposure |
|---|---|---|---|---|
| **25565** | tcp | `192.168.1.22` | **Velocity** (public Minecraft entry) | TCPShield only (firewall + RealIP) |
| **25565** | tcp | `127.0.0.1` | **ATM10** via Docker | **loopback only, never widen** |
| 19132 | udp | all | Crafty Bedrock port | LAN; only matters if a Bedrock server runs |
| 8111 | tcp | all | Crafty panel (https) | LAN |
| 8112, 8100 | tcp | all | Crafty (8123 / 8100 inside) | LAN |
| 32400 | tcp | all | Plex (host network; needs HTTPS from non-localhost) | LAN. **Also reachable from the internet on WAN :17511 via UPnP** (see above) |
| 32410-32414, 1901 | udp | all | Plex discovery/GDM | LAN |
| 32401, 32600, 34975 | tcp | loopback | Plex internals | local |
| 8989 / 7878 / 9696 | tcp | all | Sonarr / Radarr / Prowlarr | LAN |
| 5055 | tcp | all | Overseerr | LAN (or via Cloudflare Tunnel; check the dashboard) |
| 9091, 51413 | tcp (+51413 udp) | all | Transmission UI / peer port | UI: LAN. 51413 is requested from the router by UPnP |
| 80 | tcp | all | CasaOS gateway | LAN |
| 22 | tcp | all | SSH | LAN (not statically forwarded) |
| 3389 | tcp | all | xrdp (remote desktop) | LAN (not statically forwarded) |
| 139, 445 / 137-138 udp | | all | Samba / NetBIOS | LAN |
| 11434 | tcp | loopback | Ollama | local |
| 20241 | tcp | loopback | cloudflared metrics (probably) | local |
| 631 | tcp | loopback | CUPS printing | local |

Regenerate this table with:
`ss -tulnpH | sort -k5` and `docker ps --format '{{.Names}}\t{{.Ports}}'`.

## Trust boundaries (Minecraft)

1. **Internet -> TCPShield.** Only TCPShield's ranges are meant to reach Velocity.
2. **TCPShield -> Velocity.** Enforced twice: the `TCPSHIELD_MC` iptables chain
   (network layer) and RealIP `only-allow-proxy-connections = true`
   (application layer). A direct LAN connection to Velocity is dropped on
   purpose; that is why you can't status-ping it from inside the network.
3. **Velocity -> ATM10.** Loopback only. ATM10 accepts forwarded identity only
   from `172.18.0.1` (Docker's gateway as seen from inside the container)
   **and** with the shared secret.

### The invariant that protects everything

> **ATM10 runs with `online-mode=false`. It is only safe because it is
> unreachable except through Velocity.**

If the crafty compose file ever publishes 25565 on `0.0.0.0` (or anything
beyond `127.0.0.1`), anyone can log in as any player name, including an op.
Before any change to the crafty compose ports, confirm with:

```
docker inspect crafty-container --format '{{json .HostConfig.PortBindings}}'
# 25565/tcp must show "HostIp":"127.0.0.1"
```

### Why `approvedProxyHosts` is `172.18.0.1` and not `127.0.0.1`

Inside the container, a connection that arrives through Docker's published
port appears to come from the bridge gateway, not from `127.0.0.1`. (Crafty's
own pings *do* appear as `127.0.0.1` because they start inside the container.)
If the `crafty_default` network is ever recreated its gateway can change; if
players suddenly can't join with a PCF "not approved" style error, re-check it:
`docker network inspect crafty_default --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'`.

## Firewall

Live script: `scripts/firewall-velocity-tcpshield.sh`, run at boot by
`velocity-firewall.service` (ordered before `velocity.service`).

What it does (idempotent):
- builds chain `TCPSHIELD_MC`: ACCEPT TCPShield ranges, DROP everything else
- hooks it from `INPUT` for `tcp -d 192.168.1.22 --dport 25565`
- removes the obsolete Docker-era rules for 25565 from `DOCKER-USER`
- fetches TCPShield's live range list, falling back to the two known ranges
- loopback traffic is unaffected (the hook matches only the LAN destination IP)

Saved rules at `/etc/iptables/rules.v4` (saved 2026-09-18, restored at boot by
`iptables.service`) still contain:
- the **old** `DOCKER-USER` TCPShield rules for 25565 (the new script removes
  them after boot; harmless to leave)
- `raw` table drops for **45.148.10.134** and **4.180.183.240** (blocked at some
  point; reason not recorded; keep unless you know otherwise)
- Docker's own container-isolation rules
- default policies: `INPUT ACCEPT`, `FORWARD DROP`

> **Status 2026-10-02:** verified live. `velocity-firewall` ran with result
> `success`, `TCPSHIELD_MC` holds the two TCPShield ranges plus a final DROP,
> and `INPUT` hooks it for `-d 192.168.1.22 -p tcp --dport 25565`. Re-check with
> `sudo iptables -L TCPSHIELD_MC -n` and `sudo iptables -S INPUT | grep TCPSHIELD`.
> `netfilter-persistent save` is not needed: the unit re-applies the chain at
> every boot, and the IaC firewall role will replace `rules.v4`.

## Secrets: where they live (values are never written here)

| Secret | Location | Notes |
|---|---|---|
| Velocity forwarding secret | `velocity/forwarding.secret` **and** `proxy-compatible-forge.toml` in the ATM10 config | must match; rotate both together, restart both |
| Cloudflare tunnel token | `/etc/cloudflared/token` (used by the service) and `~/.cloudflared/tunnel-token` (installer input) | it was printed into a Claude session transcript during setup; consider rotating in the Cloudflare dashboard |
| Crafty admin login | initial password was written to `/DATA/AppData/crafty/config/default-creds.txt` | verify it was changed, then delete that file |
| ~~No-IP DDNS login~~ | removed 2026-10-01 (script, source, trash and shell-history lines deleted) | the password appeared in a session transcript: **delete the DDNS key/hostnames or change the password in your noip.com account** |
| Plex claim / token | inside the Plex config (`Preferences.xml`) | |

## Known risks and recommended follow-ups

Ordered roughly by importance.

1. **UPnP opens ports dynamically (accepted 2026-10-01).** The only *static*
   forward is 25565; Plex (WAN 17511) and Transmission (51413) open their own
   via UPnP/NAT-PMP. The owner is fine with this. To revert later: Plex
   Settings > Remote Access, Transmission `port-forwarding-enabled: false`, or
   turn UPnP off on the router.
2. **No dynamic DNS now.** Fine while the WAN IP is stable. If the ISP changes
   it, players are cut off until the TCPShield backend IP is updated by hand.
   The TCPShield backend is a literal IP (checked 2026-10-02). To get automatic
   updates it would need to be a hostname, if TCPShield accepts one; use your
   DNS provider's DDNS (e.g. Cloudflare), not No-IP. A hostname that resolves
   to the home IP reveals that IP to anyone who learns the name.
   Also delete the stale DDNS key/hostnames in the noip.com account.
3. **No host-level default-deny.** `INPUT` policy is ACCEPT; only the Minecraft
   port is filtered. Reasonable for a LAN box behind NAT, but combine with (2).
4. **SSH / xrdp hardening not verified.** Confirm key-only SSH and no root login
   (`sudo sshd -T | grep -E 'passwordauth|permitroot|pubkeyauth'`); consider
   limiting xrdp to the LAN.
5. ~~Unknown `apache2` listener on :42683~~ **Resolved 2026-10-01.** It was
   GNOME "Personal File Sharing" (`gnome-user-share-webdav.service`, an
   unauthenticated WebDAV share of the empty `~/Public`). The user service is
   now masked (`~/.config/systemd/user/gnome-user-share-webdav.service -> /dev/null`).
   The package is deliberately **not** purged: removing `gnome-user-share` also
   removes the `gnome-core` and `task-gnome-desktop` meta-packages, and a later
   `apt autoremove` could then strip the desktop.
6. **Hardcoded LAN IP** in `velocity.toml` (`bind`) and in the firewall script
   (`BIND_IP`). If the DHCP lease changes, Velocity fails to bind and the rules
   stop matching. Fix: reserve `192.168.1.22` for this machine in the router.
7. **Crafty `privileged: true`** gives that container near-root on the host.
   It is also where ATM10 runs. Keep the panel (8111) off the internet.
8. **Plex image older than the database** (1.41.3 vs the 1.42.2 that wrote it).
9. **Log-spam filter not applied** (cosmetic): see PROGRESS.
