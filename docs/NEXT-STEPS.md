# Next steps

Where the infrastructure-as-code work stands and what comes next, in order.
The design is in [design/IAC-DESIGN.md](design/IAC-DESIGN.md); the history is in
[../PROGRESS.md](../PROGRESS.md). Update this file whenever a step is done.

Last updated: 2026-10-02 (night).

## Where we are

| Phase | State |
|---|---|
| 1. Repo, CI, SOPS, signed commits | done |
| 2a. Roles that mirror the live host | done |
| 2b. Host changes | done: secrets via SOPS, SSH key-only, Samba/xrdp/ollama/`admin` removed, Velocity in `/opt/velocity` as its own user, firewall script out of `/home`. Left: cleanup (step 1 below) |
| 3. Storage + containers out of CasaOS | pre-seed copy running overnight 2026-10-02 (step 0) |
| 4. Pull agent, drift check, Cloudflare in OpenTofu | not started |

## 0. Overnight: storage pre-seed (owner, 2026-10-02)

`scripts/storage-preseed.sh` copies data to its new locations while everything
keeps running. Copy-only: nothing at the source changes.

- App data `/DATA/AppData/<app>` -> `/srv/appdata/<app>` (~15 GB; Crafty's
  backups stay on HDD_A, ollama/open-webui and the stray `config/` are skipped)
- NVMe-branch data -> hard drives, same relative paths (~165 GB):
  `Downloads` -> HDD_A, `Media` -> HDD_B, `Documents`/`Gallery` -> HDD_A

Check the result in the morning:

```bash
journalctl -u homelab-preseed --no-pager | tail -30   # or: sudo tail -40 /var/log/homelab-preseed.log
```

Good: it ends with `pre-seed finished OK`, and the verification lines show only
a handful of changed app-data files. If it says `ABORT`, nothing was
overwritten; bring the log to the next session.

## 1. Cleanup commit (low risk)

- `unattended-upgrades` for automatic security updates (the one real gap left
  on the host), in a new `base` role
- Retire `/etc/iptables/rules.v4` (still restores Docker-era rules at boot);
  move its two `raw` drops (45.148.10.134, 4.180.183.240) into the managed
  firewall
- Remove: `cloudflared-update` timer, `plexmediaserver.list` and
  `nonfree.list.bak` apt sources, the 31 orphaned packages from the Samba
  purge (`apt autoremove`, list reviewed first)
- Docker: remove the unused `web` network and unused images (~45 GB; list
  each one for review before removing)

## 2. Prepare the cutover (code only, no downtime)

- `storage` role: mergerfs pool of HDD_A + HDD_B only, mounted at `/DATA`
  (fstab/systemd mount, by UUID), `minfreespace=50G`, `moveonenospc=true`,
  `dropcacheonclose=true`, `func.getattr=newest`, `category.create=mfs`;
  `/srv/appdata` owned and permissioned per app
- `stacks/<app>/compose.yaml` for all seven: Plex, Sonarr, Radarr, Prowlarr,
  Overseerr, Transmission, Crafty. Per IAC-DESIGN: `America/Los_Angeles`,
  pinned image versions (Plex too), app data from `/srv/appdata`, logins from
  SOPS into root-only `.env` files, Crafty unprivileged with only 8111 and
  `127.0.0.1:25565`, `name: crafty` and the `crafty_default` subnet pinned so
  PCF's `approvedProxyHosts = ["172.18.0.1"]` stays valid
- Media apps get one shared login; Crafty keeps its own (+2FA)
- A `stacks` role that deploys them and runs `docker compose up`
- Checks: ATM10's port bound to `127.0.0.1` only; ATM10's Crafty execution
  command uses Java 21
- Write the cutover runbook (step 3) into docs/current/RUNBOOK.md and review it

## 3. Cutover window (~15-30 min of downtime)

Outline (the reviewed runbook in step 2 is the real procedure):

1. Stop all containers and CasaOS's app manager
2. Final `scripts/storage-preseed.sh` pass (copies only what changed since the pre-seed)
3. Unmount the CasaOS pool; the `storage` role mounts the HDD-only pool at `/DATA`
4. Bring up each stack from the repo, one at a time, and check it
   (Plex library, *arr paths, Transmission, Crafty panel, ATM10 join through TCPShield)
5. Remove CasaOS with an Ansible task. **Never** `casaos-uninstall`: its
   prompts default to deleting all containers and `/DATA/AppData`
6. Keep `/var/lib/casaos/files` and the old `/DATA/AppData` copies until
   everything has run for a week, then delete them

## 4. Phase 4

- Pull agent (`homelab-pull.timer`): fetch, verify every new commit's
  signature against `/etc/homelab/allowed_signers`, fast-forward only, apply
- Drift timer: `ansible-playbook --check --diff` on a schedule
- Cloudflare DNS and tunnel ingress in OpenTofu

## Owner to-dos (any time)

- [x] Rotate the Cloudflare tunnel token (done 2026-10-02 23:41; 4 connections
      healthy on the new token). Steps kept below for next time.
- [ ] Crafty: set ATM10's execution command to
      `/usr/lib/jvm/java-21-openjdk-amd64/bin/java` (it runs on Java 25 today)
- [ ] Pick the media-apps login and add it with `sops secrets/svalbard.yaml`
      as `media_apps_username` / `media_apps_password`
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
