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
| 4. Pull agent, drift check, Cloudflare in OpenTofu | pull agent + drift check **live 2026-10-04** (pushes to `main` deploy); OpenTofu next |

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
- [x] ATM10 backup schedule: every 2 days at 03:00, keep 5 (my earlier "off" reading came from a stale DB copy)
- [x] Plex hardware transcoding: not available, the account is on the free
      plan (Plex requires Plex Pass; the setting doesn't appear). The GPU is
      visible in the container, so it would work with Plex Pass. Transcodes run
      on the CPU; prefer direct play

## 3b. Remove migration scaffolding (after ~2026-10-09)

Roles stay as long as what they manage exists; one-time migration code goes:

- [ ] `storage_cutover_done`: always true now; drop the variable and its
      `when:` conditions (storage, docker, stacks, deprecated roles)
- [ ] Velocity move: after deleting `~/projects/active/velocity`, drop
      `velocity_legacy_dir`, `firewall_legacy_script` and the jar-copy task
- [ ] `scripts/storage-preseed.sh` -> `scripts/obsolete/` (or delete)
- [ ] `deprecated` role: keep for a few months, then prune entries whose
      removal has held (on a fresh install they do nothing)

## 4. Phase 4

- [x] Pull agent + drift check: `gitops` role (code, 2026-10-04). Logic tested
      against a scratch repo: signed commits apply; unsigned, foreign-key,
      bad-commit-under-a-good-tip and force-push are refused with one alert;
      a failed apply alerts once and recovers with `homelab-apply`
- [x] Bootstrapped 2026-10-04: first root run `changed=0` (applied 3feefca);
      first automatic deploy 7d0e85c (the webhook commit) at 19:42
- [x] Discord alerts working (`alert_webhook_url` in SOPS)
- [ ] First drift check: 2026-10-05 04:30 (`journalctl -u homelab-drift`)
- [ ] Cloudflare DNS and tunnel ingress in OpenTofu:
  - [x] `tofu/` skeleton: provider pinned, state + plan encryption enforced,
        passphrase generated into `secrets/cloudflare.yaml` (admin key only);
        `scripts/tofu.sh` wrapper; OpenTofu 1.13.1 in the `base` role
  - [ ] Owner: Cloudflare API token -> `secrets/cloudflare.yaml` as `cloudflare_api_token`
  - [ ] Read the live DNS records and tunnel ingress; write them as resources
        with `import` blocks; `scripts/tofu.sh plan` must show only imports
  - [ ] First apply (imports only), commit the encrypted state
  - [ ] Later: `tofu validate` in CI
- [ ] Later: agent also requires green CI for the commit (GitHub status API)

## POCs (parked)

- Jellyfin as an eighth stack next to Plex (free NVIDIA transcoding), with
  `/DATA/Media` read-only; Jellyseerr would replace Overseerr if it stays
- vcclient (GPU voice changer), removed 2026-10-03; rebuild if wanted

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

- ~~Alerting channel~~ decided 2026-10-04: Discord webhook (Slack supported)
- ~~OpenTofu state~~ decided 2026-10-04: encrypted (enforced), committed; applied by hand
- TCPShield backend: keep the literal IP, or a DDNS hostname (see PROGRESS)
- License for the public repo
- Redundancy: SnapRAID if a third drive is ever added

## Resuming a session

```bash
cd ~/projects/active/homelab && git pull && git log --oneline -5
cd ansible && ansible-playbook site.yml --check --diff -K   # expect changed=0
```
