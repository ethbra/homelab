# Progress

Newest first. Update this whenever something is changed, decided or left open.

## Status board (2026-10-03)

| Area | State |
|---|---|
| GPU in Docker (NVIDIA toolkit, default runtime) | done |
| Plex in container, library migrated, same server identity | done |
| Plex hardware transcoding | **not available**: needs Plex Pass (free account). GPU is visible in the container (`nvidia-smi` OK), so it works the day the account has Plex Pass. CPU transcoding (`libx264`) until then |
| ATM10 backups | schedule every 2 days at 03:00, keep 5; fresh backup 2026-10-03 |
| Native Plex removed | done (package, units and `/var/lib/plexmediaserver` all gone; verified 2026-10-02). The container is the only Plex; there is no rollback copy |
| ATM10 behind Velocity + TCPShield, real IPs in logs | done, joins work |
| Velocity as a systemd service | done |
| TCPShield firewall (`TCPSHIELD_MC`) | **live and verified 2026-10-02**: chain has the two TCPShield ranges + DROP, hooked from `INPUT` for the LAN IP; unit enabled for boot, last run `success` |
| ATM10 log spam from Crafty's ping | open (cosmetic) |
| Containers and storage | **moved off CasaOS 2026-10-03**: seven stacks in `stacks/`, app data in `/srv/appdata`, `/DATA` = HDD-only pool from fstab; old copies and CasaOS removed |
| Docs (this directory) | done 2026-10-01; `docs/current/` updated for the cutover 2026-10-03 |
| Infrastructure as code | phases 1, 2a done; 2b done (cleanup applied 2026-10-03); phase 3 done 2026-10-03; phase 4 pull agent + drift check live 2026-10-04 (signed pushes to `main` deploy within ~10 min); OpenTofu next. **Next: docs/NEXT-STEPS.md** |

## Log

### 2026-10-07 - Cloudflare read, DNS record imported (plan only)
- Owner added the Cloudflare API token to `secrets/cloudflare.yaml`. It
  verifies as active and can read zone `ethbra.com` and the account's tunnels.
- Live state: one DNS record, `play.ethbra.com` CNAME -> TCPShield (DNS only).
  Written as `tofu/dns.tf` with an `import` block; `tofu init` + `plan`:
  1 to import, 0 to add/change/destroy. Not applied yet (owner applies).
- Finding: tunnel `Host` is healthy but has no ingress (remote config
  version 0) and no DNS record points at it, so it exposes nothing. Its
  future is an open decision (NEXT-STEPS).

### 2026-10-05 - agent recovered, first drift check clean
- First drift check (04:30): ok=84 changed=0, `no drift at 7d0e85c`.
- The fix commit ebaf399 was applied by the agent at 20:12 (failed=0,
  changed=4): OpenTofu 1.13.1 installed, CasaOS leftovers removed, new webhook
  URL written. Test alert reached Discord at the new URL.

### 2026-10-04 (night) - first failed automatic apply, fixed
- The agent's apply of 27caae2 (new webhook URL) failed at "CasaOS services
  are stopped and disabled": `rclone.service` (left failed, file deleted) was
  reported by service_facts as `failed` this time, not `not-found`, so the
  skip didn't apply. The agent behaved as designed: one alert, `applied` left
  at 7d0e85c, quiet until a newer commit. Because the run stopped there, the
  new webhook URL (gitops role, later in the play) was not deployed yet.
- Fix: decide by systemd's own `LoadState` (read with the systemd module),
  which is `loaded` only while a unit file exists.
- Found while checking: CasaOS also left `/lib/systemd/system/casaos.service`
  (a second copy, still `loaded`), two `*.service.buildroot` files and rclone's
  man page; added to the removal list.
- `ansible.cfg`: `no_target_syslog = True`, so module invocations ("Invoked
  with ...") no longer flood `journalctl -u homelab-pull`.

### 2026-10-04 (night) - OpenTofu skeleton
- Decided: tofu state encrypted with OpenTofu's state encryption (`enforced`
  for state and plans, pbkdf2 passphrase in SOPS) and committed as
  `tofu/terraform.tfstate`; `tofu apply` is run by hand by the owner via
  `scripts/tofu.sh`, never by the pull agent (no write-capable Cloudflare token
  on the box).
- `tofu/versions.tf` (Cloudflare provider ~> 5.27), `scripts/tofu.sh` (SOPS ->
  environment only), OpenTofu 1.13.1 added to the `base` role (official .deb,
  pinned by checksum). State passphrase generated straight into SOPS (44 chars,
  never displayed), in `secrets/cloudflare.yaml`, which is encrypted to the
  admin key only: the host's age key can't decrypt the Cloudflare secrets. `.gitignore` reworked: only `tofu/terraform.tfstate` is
  tracked.
- Waiting on: a Cloudflare API token from the owner.

### 2026-10-04 (evening) - pull agent live
- Bootstrapped: allowed_signers in `/etc/homelab`, `--tags gitops`; first run
  as root via `sudo homelab-apply`: ok=83 changed=0, applied 3feefca.
- First automatic deploy: the commit adding `alert_webhook_url` was fetched,
  verified and applied by the timer at 19:42 (applied 7d0e85c, changed=1:
  `alert.env`). `sudo homelab-alert` reached Discord.
- From now on a signed push to `main` is a deploy.

### 2026-10-04 - phase 4: pull agent and drift check (code)
- New `gitops` role: root-owned clone at `/opt/homelab/repo` (not
  `/opt/homelab`, which holds the deployed stacks), its own Ansible in
  `/opt/homelab/venv` (root must not run the pipx copy in /home), sops pinned
  by checksum (the hand-installed 3.13.3 matched the release checksum).
- `homelab-pull` (every 10 min) / `homelab-apply` (by hand): fast-forward only,
  every new commit must be `%G? = G` against `/etc/homelab/allowed_signers`,
  then the full playbook; one alert per refused or failed commit.
  `homelab-drift` (daily 04:30): check mode at the applied commit.
  `homelab-alert`: journal + Discord/Slack webhook from SOPS (optional).
- Tested against a scratch clone with stubbed Ansible: signed apply; unsigned,
  foreign-key (`U`), bad commit under a good tip, force-push all refused; failed
  apply alerts once, stays quiet, recovers with `homelab-apply`; drift parse
  for clean and drifted output.
- Decided: alerts to a Discord webhook (Slack also supported).

### 2026-10-03 (late night) - old copies deleted, CasaOS removed
- History: the cutover commit was pushed twice (66d262f with only the two
  staged file deletions, 2517edb with everything) and merged (3303366); the
  merge tree equals 2517edb, so nothing was lost.
- Found Crafty's ATM10 backup schedule disabled since 2025-11-07 (newest
  backup 11 months old). Owner took a fresh backup (22:17, 4.6 GB) before any
  deletion. HDD_B also held six Oct 2025 ATM10 backups outside Crafty's view.
- Owner chose not to wait the rollback week. Deleted: `/var/lib/casaos/files`
  (175 GB), `AppData/` on both drives except `/mnt/HDD_A/AppData/crafty/backups`
  (incl. retired ollama/open-webui data and the stray Plex `config/`).
  `/` went from 268 to 94 GB used.
- `deprecated` role: removes CasaOS's binaries, units, `/etc/casaos`,
  `/var/lib/casaos` (old compose files with a plaintext Transmission login),
  `rclone` (installed with CasaOS) and purges `udevil` (devmon).
- Plex: a forced low-res test still transcoded on the CPU (`libx264`, no
  hwaccel); the GPU is visible in the container. Cause confirmed: hardware
  transcoding needs Plex Pass and the account is free (the setting isn't shown). The ATM10 backup schedule is on (2 days, keep 5): my "off since
  2025-11" reading came from copying `crafty.sqlite` without its `-wal` file.
- `deprecated` role: skip units whose file is gone but which systemd still
  lists as `not-found` (rclone had been left `failed`).
- *arr logins set by the owner.

### 2026-10-03 (night) - cutover done
- Prerequisites: ATM10 on Java 21 (ran 21.0.10, owner joined, real IP in the
  log); media login in SOPS; stacks rendered; images pulled; the new pool's
  mount rehearsed read-only at `/mnt/pool-test`.
- Window 21:31-21:50: containers and CasaOS stopped; `--final` copy (0
  differences); old pool released; `storage_cutover_done: true`; new pool
  mounted from fstab; `--compare`: 1,314 files in both, 0 missing, 0 extra.
  CasaOS containers and networks removed; stacks up from `/opt/homelab/stacks`.
- Checked: ATM10 published on `127.0.0.1:25565` only, Crafty unprivileged,
  `crafty_default` gateway 172.18.0.1; Sonarr/Radarr updated to the new
  Transmission login (tests pass); Transmission, Prowlarr (app tests pass),
  Overseerr, Plex playback, Crafty panel; ATM10 started on Java 21 and the
  owner joined through TCPShield (real IP logged).
- Bugs found during the window, fixed: the docker role wrote its drop-in into
  a directory that didn't exist (check mode can't catch it), so step 5 ran
  twice; the cloudflared role still installed the `cloudflared-update` units
  that the deprecated role deletes (they would have flip-flopped on every full
  run). Not applied yet: the cloudflared fix needs a `-K` run.
- `config/atm10/` links pointed at `/DATA/AppData`, which now resolves to the
  stale pre-cutover copy on the drives; repointed to `/srv/appdata` (local
  only). Dead `config/iptables-rules.v4` link removed.
- Docs: ARCHITECTURE, SERVICES, RUNBOOK, NETWORK-AND-SECURITY, README,
  CLAUDE.md updated to the new layout.

### 2026-10-03 (later) - cutover prepared (code only)
- New `storage` and `stacks` roles, `stacks/<app>/compose.yaml` for the seven
  apps, CasaOS service retirement in `deprecated`, all behind
  `storage_cutover_done: false`. Checked with `--check` both ways: with the
  switch off it only renders files and tightens `/srv/appdata` modes.
  Collection `community.docker` 5.3.0 added (its compose module tested here
  against Compose v5.5.1: creates, idempotent, removes).
- `storage-preseed.sh` gained `--final` (containers must be stopped; app data
  with `--delete` so stale SQLite `-wal` files can't survive) and `--compare`
  (old vs new pool file lists).
- Runbook: docs/current/RUNBOOK.md "Storage and stacks cutover", with rollback.
- Found while preparing:
  - stopping `casaos-local-storage` kills the old pool's mergerfs (same
    cgroup), so it is stopped only after the final copy
  - the apps reach each other only via 192.168.1.22 + published ports
    (Prowlarr apps, *arr download clients, Overseerr), so container IPs and
    networks can change freely
  - ATM10 has auto-start off in Crafty and still runs plain `java` (25)
  - CasaOS also runs `rclone rcd` (no-auth unix socket) and `devmon`
  - every CasaOS container carried an injected `OPENAI_API_KEY` env var; not
    carried over
  - `/srv/appdata` and app folders were 0777 (copied from CasaOS)

### 2026-10-03 - pre-seed done, cleanup roles written
- Storage pre-seed finished OK (00:18): ~15.7 GB app data to `/srv/appdata`,
  Downloads 113 GB -> HDD_A, Media 63 GB -> HDD_B (Documents/Gallery empty).
  Verification: 0 files differ for the four data folders; 28 app-data files
  changed afterwards (expected, apps were running). HDD_A 21% used, HDD_B 16%.
- Cleanup (NEXT-STEPS step 1), code only, verified with `--check`:
  - new `base` role: `rsync` (installed by hand for the pre-seed),
    `unattended-upgrades` for Debian security + cloudflared, no auto-reboot
  - `firewall` role: the two `raw` drops from `rules.v4` moved into the managed
    script (`firewall_blocked_sources`)
  - `deprecated` role: purges `iptables-persistent`/`netfilter-persistent`,
    removes `rules.v4`, the `cloudflared-update` timer, the Plex apt source +
    key, `nonfree.list.bak`
- Docker images not used by any container (2026-10-03), for the owner to prune:
  `vcclient:latest` (13 GB, possibly a local build: not re-pullable) and
  `dannadori/vcclient:20230826_211406` (12.9 GB); superseded app versions
  (crafty-4 4.4.11/4.4.4, overseerr 1.33.2, radarr 6.1.1/5.26.2/5.7.0,
  prowlarr 2.3.5/1.37.0/1.32.2, plex 1.41.3, transmission 4.0.4);
  `nginx:latest`, `ubuntu:latest`, `python:3.12-slim`. Keep:
  `koalaman/shellcheck:v0.11.0` (pre-commit hook), `nvidia/cuda` (GPU test).
- Applied (owner, 15:22): `--check` afterwards shows changed=0; firewall
  re-ran OK, velocity/cloudflared active, `cloudflared-update` gone. Owner ran
  `apt autoremove --purge` and removed both `vcclient` images (a voice-changer
  POC; can be rebuilt if wanted). Removed the `web` network: hand-made
  (2025-10-13, no compose labels), its only endpoint was sonarr, attached by
  hand on top of `network_mode: bridge`; disconnected. Left: the other old images.
- SERVICES.md had stale rows (ollama, xrdp, Samba, native Plex, noip, all gone);
  refreshed.

### 2026-10-02 (night) - Velocity move applied, storage pre-seed, next steps
- Velocity now runs from `/opt/velocity` as user `velocity` (sandboxed unit,
  fail-closed firewall check); firewall script at `/usr/local/sbin`. Verified:
  both units active, Java process owned by `velocity`, status ping through
  TCPShield OK (max 50 players), `TCPSHIELD_MC` unchanged. CI green on 7fe8d52.
- Storage plan sized: app data to move is ~15 GB (Crafty's 67 GB of backups
  stay on HDD_A); NVMe-branch data to move to the hard drives is ~165 GB; no
  path collisions between the NVMe branch and either hard drive.
- Added `scripts/storage-preseed.sh` (copy-only pre-seed, re-runnable) and
  started it overnight. Added `docs/NEXT-STEPS.md` as the resume point.
- Rotated the Cloudflare tunnel token (dashboard -> SOPS -> `--tags cloudflared`).
  cloudflared restarted 23:41 with 4 ready connections (LAX edges). The old
  token, which had leaked into a session transcript, is invalid.

### 2026-10-02 (late, 3) - failed apply: handler ordering
- The Velocity/firewall apply failed at "Re-apply firewall" (`203/EXEC`):
  systemd still had the old firewall unit loaded, which pointed at the script
  that had just been removed from `/home`. Cause: four roles each defined a
  handler named `Reload systemd`; Ansible keeps only the last definition, so the
  reload ran after the restart. Velocity kept running on the old setup and the
  `TCPSHIELD_MC` rules stayed in place (verified), so nothing was exposed.
- Fix: restart handlers run `daemon_reload` first; handler names are unique per
  role; role `retired` renamed to `deprecated`.

### 2026-10-02 (late, 2) - Velocity to /opt, decisions
- Applied: secrets via SOPS, SSH key-only (tested: key works, password refused),
  Samba/xrdp/ollama purged, `admin` and `ollama` accounts removed. CI green.
  `admin`'s home was deleted with the account; it had not been reviewed first
  (the step's description undersold what the `access` role did).
- Code (to apply): Velocity moves to `/opt/velocity` under a `velocity` system
  user with a sandboxed unit that refuses to start unless the TCPShield rule
  exists; firewall script moves to `/usr/local/sbin`, root-owned (it ran as
  root from a user-writable path). Old Velocity dir kept as rollback.
- Deleted the installer's plaintext token copy `~/.cloudflared/tunnel-token`.
- Repo: removed `systemd/` copies and stale symlinks (roles own those files
  now); one-time installers moved to `scripts/obsolete/`.
- Found: ATM10 has been running on Java 25 (container default `java`); it
  targets Java 21. Owner sets the execution command in Crafty.
- Decided: storage layout (HDD-only pool at `/DATA`, app data on NVMe, no
  RAID for now); media apps share one login, Crafty separate.

### 2026-10-02 (late) - IaC phase 2: decisions, secrets, removals (code only)
- Root check of the mirror roles: ok=28 changed=0. Phase 2a mirror confirmed.
- Decided: remove Samba, xrdp and ollama; retire the `admin` login account
  (after the owner checks its home directory); SSH key-only. New roles
  `retired` and `access` do this. Not applied yet.
- `/DATA/Media/Shared` is **not** empty: 14 GB of photos/videos (CR2, MP4,
  2025-07-12). Removing Samba keeps them.
- Secrets move into `secrets/svalbard.yaml` (SOPS): tunnel token and Velocity
  forwarding secret. Roles render them with `no_log`/no diff; the forwarding
  secret becomes mode 0600.
- Deleted Crafty's `default-creds.txt` (stale; Crafty now has custom creds + 2FA).
- ATM10 has been stopped since 2026-10-01 15:21 (clean shutdown). The Java
  process seen today was the Vanilla server, stopped from Crafty at 20:48.
- Container decisions recorded in IAC-DESIGN (time zone, pinned images,
  credentials via SOPS, Crafty unprivileged, Crafty ports).

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
- [ ] Crafty: set ATM10's execution command to `/usr/lib/jvm/java-21-openjdk-amd64/bin/java` (it runs on Java 25 today).
- [ ] After a week of Velocity running from `/opt/velocity`: delete `~/projects/active/velocity` (rollback copy).
- [x] Back up both age private keys offline (2026-10-02: password-protected KeePass file, kept on a second PC and a flash drive).
- [ ] Finish No-IP removal: the `noip-duc` package and unit are already gone (verified 2026-10-02). Remaining: delete the DDNS key/hostnames or change the password in your noip.com account.
- [ ] **TCPShield backend is a literal IP** (checked 2026-10-02; value deliberately not recorded here), so an ISP address change takes the server offline until it is edited by hand. Spectrum residential, dynamic. Options: accept and watch for it, or use a hostname kept current by a DDNS timer (check first that the backend field accepts one; trade-off: the name would reveal the home IP to anyone who learns it). Decide before IaC phase 4.
- [x] Apply + verify the firewall (2026-10-02).
- [ ] Reserve `192.168.1.22` for this machine in the router.
- [x] ~~Confirm Plex hardware transcode~~ needs Plex Pass (free account); GPU is ready if that changes (2026-10-03).

**Soon-ish**
- [x] Rotate the Cloudflare tunnel token (done 2026-10-02).
- [x] Crafty admin password changed (custom creds + 2FA); `default-creds.txt` deleted 2026-10-02.
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
