# Progress

Newest first. Update this whenever something is changed, decided or left open.

## Status board (2026-10-01)

| Area | State |
|---|---|
| GPU in Docker (NVIDIA toolkit, default runtime) | done |
| Plex in container, library migrated, same server identity | done |
| Plex hardware transcoding confirmed (`(hw)` in dashboard) | **not yet verified** |
| Native Plex removed | done (package, units and `/var/lib/plexmediaserver` all gone; verified 2026-10-02). The container is the only Plex; there is no rollback copy |
| ATM10 behind Velocity + TCPShield, real IPs in logs | done, joins work |
| Velocity as a systemd service | done |
| TCPShield firewall (`TCPSHIELD_MC`) | **live and verified 2026-10-02**: chain has the two TCPShield ranges + DROP, hooked from `INPUT` for the LAN IP; unit enabled for boot, last run `success` |
| ATM10 log spam from Crafty's ping | open (cosmetic) |
| Docs (this directory) | done 2026-10-01 |
| Infrastructure as code | phase 1 done; phase 2a (mirror roles) in progress: docker, nvidia_toolkit, cloudflared, firewall, velocity give an empty check-mode diff. See docs/design/IAC-DESIGN.md |

## Log

### 2026-10-02 (night) - IaC phase 2a: first mirror roles
- Read-only host inventory taken (non-root by Claude, root-only parts by the
  owner with a reviewed script). Output kept outside the repo.
- Installed `ansible-core` 2.19.13 and `ansible-lint` 26.9.0 via pipx (user level).
- Added `ansible/` with roles `docker`, `nvidia_toolkit`, `cloudflared`,
  `firewall`, `velocity`. Live files copied verbatim into the roles.
  Check mode against the live box: ok=28 changed=0 (run without sudo).
- The live firewall script now lives in the repo as a template
  (`roles/firewall/templates/`), deployed to its existing path.
- CI gained an `ansible` job (syntax check + ansible-lint, production profile).
- High CPU earlier this evening: VS Code's file search (`rg --files --follow`)
  crawling `/` from a window with no folder open (`/proc`, `/sys`, the 2.7 TB
  mergerfs pool). Not a server problem. Fix: open a folder, and set
  `"search.followSymlinks": false`.
- Inventory corrections to `docs/current/` (to fold in when 2b lands): GPU is an
  RTX 2070 **SUPER**; Plex runs `linuxserver/plex:latest` (1.43.4) as PUID/PGID
  1000 (the `.env` 911 values are unused); Velocity logs to `velocity.log`
  (systemd), not `logs/latest.log`; `cloudflared-update.timer` is disabled.

### 2026-10-02 (evening) - verification pass
- Firewall: started `velocity-firewall`; `TCPSHIELD_MC` is live (ACCEPT
  198.178.119.0/24 and 104.234.6.0/25, then DROP) and hooked from `INPUT`.
- `noip-duc` and `plexmediaserver` are not installed (the `apt purge` calls
  failed with "Unable to locate package" because they were already gone).
  `/var/lib/plexmediaserver` no longer exists.
- Router (Orbi RBR50): Internet setup is dynamic from the ISP; the DNS servers
  it uses (209.18.47.61/62) belong to Charter/Spectrum (ARIN), the ISP, so
  they are not suspicious. Static-IP mode was tried and dropped the
  connection; reverted to dynamic. Router details are not recorded here.
- TCPShield backend is a literal IP (see the open item below).
- Both age private keys backed up offline (KeePass, two locations).

### 2026-10-02 (later) - IaC phase 1 done
- Repo published: https://github.com/ethbra/homelab (public). Both commits
  signed (SSH key) and shown as Verified; CI green (lint + gitleaks, full history).
- SOPS round-trip verified with both age keys (admin + host).
- GitHub settings: ruleset `protect-main` on the default branch (require
  signed commits, block force-push, block deletion; no bypass actors),
  workflow token read-only, Actions can't approve PRs, approval required for
  all outside contributors' workflows, secret scanning + push protection on.
- Commits are made and signed by the owner only; Claude stages changes.
- Still to do: back up both age private keys offline.

### 2026-10-02 - IaC phase 1 scaffold
- Decided: the repo will own all config (pull model: the server fetches and
  applies signed commits; GitHub only validates). CasaOS will be retired.
  Design in `docs/design/IAC-DESIGN.md`.
- Found: `/DATA` (mergerfs) is mounted by `casaos-local-storage`, not fstab,
  and ~175 GB of it lives in `/var/lib/casaos/files`. CasaOS must be removed
  last, never with `casaos-uninstall` (prompts default to deleting all
  containers and `/DATA/AppData`).
- Moved the existing docs to `docs/current/` with a "current state" banner;
  links updated. Redacted the home WAN IP from NETWORK-AND-SECURITY.
- `git init` (no commits yet). Symlinks `velocity/`, `config/` and the firewall
  script link are gitignored (they point outside the repo; one holds a secret).
- Added `.sops.yaml` (placeholder recipients), `.yamllint.yaml`,
  `.pre-commit-config.yaml`, CI (`yamllint`, `shellcheck`, gitleaks on full
  history, SOPS check), `scripts/check-sops-encrypted.sh`, `secrets/README.md`.
  Verified locally: yamllint, shellcheck, gitleaks clean.
- `install-cloudflared.sh`: `mkdir -p --mode` -> `install -d -m` (shellcheck SC2174).

### 2026-10-01 (later) - cleanup
- **No-IP removed:** deleted `archive/noip-duc_3.3.0/`, `archive/startup/run.sh`
  (plaintext credentials), the trashed tarball and 21 matching lines from
  `~/.bash_history`. The `noip-duc` service was already disabled and
  `all.ddnskey.com` no longer pointed at this machine. Still to do: `sudo apt purge noip-duc`
  and clean up the noip.com account. (`~/Desktop/Things to do.txt` still mentions
  it in a to-do line; left alone.)
- **apache2 on :42683 explained and closed:** GNOME file sharing
  (`gnome-user-share-webdav`), WebDAV of an empty `~/Public` with no password.
  Stopped and masked; package kept on purpose (see NETWORK-AND-SECURITY risk 5).
- **Router:** owner confirmed the only static forward is TCP 25565 ->
  192.168.1.22:25565. Found that UPnP/NAT-PMP is additionally opening Plex
  (WAN 17511) and Transmission (51413).

### 2026-10-01 - ATM10 behind Velocity, docs
- Added **Velocity 4.2.0** at `~/projects/active/velocity/` with the TCPShield
  RealIP plugin; installed `velocity.service`; wrote `start.sh`.
- Crafty compose: published ATM10 on `127.0.0.1:25565` only
  (`host_ip: "127.0.0.1"`); recreated `crafty-container`.
- Velocity binds `192.168.1.22:25565` (wildcard bind collided with Docker).
- Installed **Proxy Compatible Forge 1.3.1** on ATM10 with the shared forwarding
  secret and `approvedProxyHosts = ["172.18.0.1"]`; removed NeoVelocity (it had
  been added first and conflicted).
- ATM10 `online-mode=false`.
- Raised Velocity packet limits (`max-plugin-message-payload-size.clientbound`,
  `max-known-packs`) after the 448-mod sync packet (1.83 MB) exceeded the default.
- First successful join through TCPShield; ATM10 logs the real player IP.
- Server list: passthrough disabled (the compatibility mod appends a stray
  packet Velocity rejects); MOTD/icon/cap set in Velocity.
- Wrote `firewall-velocity-tcpshield.sh` + `velocity-firewall.service`
  (unit is installed; **verify the live rules**).
- Tried a log4j filter to hide Crafty's ping noise: rules verified in isolation
  but the running server doesn't apply `-Dlog4j2.configurationFile`. Cause
  unknown (couldn't read the live JVM properties). Left in place, harmless.
- Created this `homelab/` hub and docs.
- ATM10 is **All the Mods 10 v4.12** (MC 1.21.1, NeoForge 21.1.209).

### 2026-09-25 to 09-30 - GPU and Plex
- Fixed two bugs in `install-nvidia-container-toolkit.sh` (`curl -fsSL`,
  `gpg --dearmor --yes`); installed the toolkit from NVIDIA's apt repo
  (signed-by keyring); set `nvidia` as Docker's default runtime.
- Plex compose (CasaOS `plex-nvidia`): removed the nonexistent `/dev/dvb`
  device, added `.env`, changed the media mount target to `/DATA/Media`.
- Found two Plex installs fighting over port 32400 (native + container, host
  network). The real library was the native one; migrated its full config into
  the container (`cp -a`, owner 911:911). Server identity and claim preserved.
- Found Plex needs https for non-local clients.

## Open items / TODO

**Do soon**
- [x] Back up both age private keys offline (2026-10-02: password-protected KeePass file, kept on a second PC and a flash drive).
- [ ] Finish No-IP removal: the `noip-duc` package and unit are already gone (verified 2026-10-02). Remaining: delete the DDNS key/hostnames or change the password in your noip.com account.
- [ ] **TCPShield backend is a literal IP** (checked 2026-10-02; value deliberately not recorded here), so an ISP address change takes the server offline until it is edited by hand. Spectrum residential, dynamic. Options: accept and watch for it, or use a hostname kept current by a DDNS timer (check first that the backend field accepts one; trade-off: the name would reveal the home IP to anyone who learns it). Decide before IaC phase 4.
- [x] Apply + verify the firewall (2026-10-02).
- [ ] Reserve `192.168.1.22` for this machine in the router.
- [ ] Confirm Plex hardware transcode works (native Plex is already removed).

**Soon-ish**
- [ ] Rotate the Cloudflare tunnel token (it was printed into a session transcript).
- [ ] Confirm the Crafty admin password was changed; delete `default-creds.txt`.
- [ ] Verify SSH is key-only, no root login; decide on xrdp exposure.
- [x] ~~Bump the Plex image~~ already on 1.43.4 via `:latest` (2026-10-02); pin a version when the stack moves into the repo.
- [ ] ~~`sudo netfilter-persistent save`~~ Skip: the IaC firewall role will own all rules and retire `rules.v4` (see IAC-DESIGN). Saving now would also snapshot Docker's own rules.

**Future features**
- [ ] **Storage hosting / remote file access.** Design properly later (the GNOME WebDAV share was an unfinished start and is now off). Needs: auth, encryption in transit, how it's reached from outside (Cloudflare Tunnel vs VPN), and which folders are exposed.
- [ ] **Infrastructure as code repo** (see the IaC discussion of 2026-10-01).

**Nice to have**
- [ ] Silence Crafty's ping noise in the ATM10 log (needs the log4j property to actually load, or a PCF-side option).
- [ ] Decide what to do with the unused Crafty servers (rlcraft, Vanilla, Plugins Test): all share `127.0.0.1:25565`.
- [ ] Remove leftover `/DATA/AppData/ollama-nvidia` and `open-webui-ollama` if unused.
- [x] Put `homelab/` under git (2026-10-02; public at github.com/ethbra/homelab).
- [ ] Document the Cloudflare tunnel's public hostnames here once checked in the dashboard.
- [ ] Check that Crafty's dashboard still shows ATM10 stats (player count/version) after the next restart.

## Not covered here
- `~/projects/active/neet2neat` (separate project, own `PROGRESS.md`)
- `~/projects/archive/*` (now only MCChecker)
