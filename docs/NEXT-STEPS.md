# Next steps

Where the infrastructure-as-code work stands and what comes next, in order.
The design is in [design/IAC-DESIGN.md](design/IAC-DESIGN.md); the history is in
[../PROGRESS.md](../PROGRESS.md). Update this file whenever a step is done.

Last updated: 2026-10-03 (night).

## Where we are

| Phase | State |
|---|---|
| 1. Repo, CI, SOPS, signed commits | done |
| 2a. Roles that mirror the live host | done |
| 2b. Host changes | done: secrets via SOPS, SSH key-only, Samba/xrdp/ollama/`admin` removed, Velocity in `/opt/velocity` as its own user, firewall script out of `/home`. Cleanup applied 2026-10-03 |
| 3. Storage + containers out of CasaOS | **done 2026-10-03**: cutover, old copies deleted, CasaOS removed |
| 4. Pull agent, drift check, Cloudflare in OpenTofu | not started |

## 0. Storage pre-seed: done 2026-10-03

`scripts/storage-preseed.sh` finished OK at 00:18: app data to `/srv/appdata`,
NVMe-branch data to the hard drives, all four data folders verified identical.
Re-running it later copies only what changed (that is cutover step 3.2).

## 1. Cleanup: done 2026-10-03

Written and checked (`--check` shows only these changes):

- `base` role: `rsync`, `unattended-upgrades` (Debian security + cloudflared,
  no automatic reboot)
- `firewall` role: the two `raw` drops (45.148.10.134, 4.180.183.240) now come
  from the managed script
- `deprecated` role: purge `iptables-persistent`/`netfilter-persistent`, remove
  `/etc/iptables/rules.v4`, the `cloudflared-update` timer, the Plex apt
  source + key, `nonfree.list.bak`

Apply and verify:

```bash
cd ~/projects/active/homelab/ansible
ansible-playbook site.yml -K --tags base,firewall,deprecated
sudo iptables -t raw -S PREROUTING | grep -E '45.148.10.134|4.180.183.240'  # each once
sudo iptables -L TCPSHIELD_MC -n                                            # unchanged
systemctl is-active velocity-firewall velocity cloudflared
systemctl list-timers --all | grep -c cloudflared-update                     # 0
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -i 'allowed origins'
```

One-off, by hand (not role-managed state):

- [x] `sudo apt autoremove --purge` (2026-10-03)
- [x] `vcclient` images removed (2026-10-03)
- [x] Docker `web` network removed (2026-10-03)
- [ ] Docker: remove the other unused images (optional; list in PROGRESS
  2026-10-03)

## 2. Prepare the cutover: done 2026-10-03 (code)

- `storage` role: drives by UUID (`nofail`), HDD-only mergerfs pool at
  `/DATA`, `/srv/appdata` tightened to 0755. Docker gets
  `RequiresMountsFor=/DATA`: if the pool is missing, containers stay down
  instead of seeing an empty `/DATA`
- `stacks/<app>/compose.yaml` for all seven, pinned versions, one time zone,
  same ports and container paths as today; Overseerr moves to the default
  bridge; Crafty unprivileged, panel 8111 + `127.0.0.1:25565` only, network
  `172.18.0.0/16` pinned
- `stacks` role: renders to `/opt/homelab/stacks`, Transmission's login from
  SOPS into a root-only `.env`, `docker compose up` in order, then asserts
  ATM10 is loopback-only and on Java 21
- `deprecated` role: stops and disables CasaOS's services (and its `rclone`
  and `devmon`) after the cutover; files stay a week for rollback
- `scripts/storage-preseed.sh --final` / `--compare` for the window
- Everything is behind `storage_cutover_done` (host_vars, `false` today)

## 3. Cutover and cleanup: done 2026-10-03

The window ran 21:31-21:50 (docs/current/RUNBOOK.md, "Storage and stacks
cutover"): `/DATA` is the HDD-only pool from fstab (1,314 files, none missing),
all seven stacks run from `stacks/` with data in `/srv/appdata`, CasaOS's
services are disabled. Every app was checked by the owner; ATM10 runs on
Java 21 behind TCPShield with real IPs.

Cleanup, done the same night (owner chose not to wait the rollback week):

- [x] Fresh ATM10 backup first (`2026-10-03_22-17-55.zip`): the backup schedule
      had been off since 2025-11-07, so the newest backup was 11 months old
- [x] Old copies deleted: `/var/lib/casaos/files` (175 GB), `AppData/` on both
      drives except `/mnt/HDD_A/AppData/crafty/backups`; included the retired
      ollama/open-webui data and six Oct 2025 ATM10 backups on HDD_B that
      Crafty never saw (older than the ten on HDD_A)
- [x] CasaOS files removed by the `deprecated` role (needs the owner's `-K` run)

Also open:
- [x] Sonarr/Radarr/Prowlarr UI logins set (2026-10-03)
- [ ] **Crafty: turn ATM10's "Backup" schedule back on** (Schedules tab; off since 2025-11-07)
- [ ] Plex hardware transcoding: tonight's playback was direct stream (video copied), so `(hw)` is untested; the last real transcode (2026-09-26) used `libx264` on the CPU. Check Settings -> Transcoder -> hardware acceleration (Plex Pass), force a lower quality, look for `(hw)` in Settings -> Dashboard

## 4. Phase 4

- Pull agent (`homelab-pull.timer`): fetch, verify every new commit's
  signature against `/etc/homelab/allowed_signers`, fast-forward only, apply
- Drift timer: `ansible-playbook --check --diff` on a schedule
- Cloudflare DNS and tunnel ingress in OpenTofu

## Owner to-dos (any time)

- [x] Rotate the Cloudflare tunnel token (done 2026-10-02 23:41; 4 connections
      healthy on the new token). Steps kept below for next time.
- [x] Crafty: ATM10's execution command uses Java 21 (2026-10-03)
- [x] Media-apps login in SOPS (2026-10-03)
- [ ] After a week of Velocity running from `/opt/velocity` (from 2026-10-02):
      delete `~/projects/active/velocity`
- [ ] Move the photos/videos in `/DATA/Media/Shared` somewhere deliberate
- [ ] noip.com: delete the stale DDNS key/hostnames

### Rotating the Cloudflare tunnel token

1. Cloudflare dashboard -> Zero Trust -> Networks -> Tunnels -> select the
   tunnel -> refresh/rotate its token. This invalidates the old one. Copy the
   new token (the long `eyJ...` string) to the clipboard only.
2. Put it in SOPS. Paste straight into the editor, nowhere else:
   ```bash
   cd ~/projects/active/homelab && EDITOR=nano sops secrets/svalbard.yaml
   ```
   Replace the value of `cloudflared_tunnel_token` (keep the key name; plain
   value, no quotes needed). Save and exit; sops re-encrypts on save.
3. Apply (writes `/etc/cloudflared/token` and restarts cloudflared):
   ```bash
   cd ansible && ansible-playbook site.yml -K --tags cloudflared
   ```
4. Verify: `systemctl is-active cloudflared` and
   `journalctl -u cloudflared -n 20 --no-pager | grep -i 'registered tunnel connection'`
   (expect connections registered after the restart), and that the dashboard
   shows the tunnel **Healthy**.
5. Commit and push the re-encrypted `secrets/svalbard.yaml`. The diff shows
   only that `cloudflared_tunnel_token` changed, not its value.

## Open decisions

- Alerting channel for drift and pull failures (ntfy, email, Discord webhook)
- OpenTofu state: local with built-in encryption, or a remote backend
- TCPShield backend: keep the literal IP, or a DDNS hostname (see PROGRESS)
- License for the public repo
- Redundancy: SnapRAID if a third drive is ever added

## Resuming a session

```bash
cd ~/projects/active/homelab && git pull && git log --oneline -5
cd ansible && ansible-playbook site.yml --check --diff -K   # expect changed=0
```
