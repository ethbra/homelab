# Runbook

> **Current state.** This describes the live server as it runs today (hand-managed
> and CasaOS). The planned infrastructure-as-code setup is in
> [../design/IAC-DESIGN.md](../design/IAC-DESIGN.md). This doc changes only when a migration
> phase actually lands.

Commands marked `sudo` need your password. Paths are relative to
`~/projects/active/homelab/` unless absolute.

## Everyday

| Task | Command |
|---|---|
| Restart Velocity | `sudo systemctl restart velocity` |
| Velocity status / log | `systemctl status velocity --no-pager` / `journalctl -u velocity -f` |
| Restart ATM10 | **Crafty web UI** (https://192.168.1.22:8111). Don't kill the Java process by hand; Crafty loses track of it |
| ATM10 log | `tail -f /DATA/AppData/crafty/servers/1472e5eb-3e4d-4ce7-b2ac-723f83803f19/logs/latest.log` |
| Re-apply the firewall now | `sudo systemctl restart velocity-firewall` |
| Containers at a glance | `docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'` |
| Who connected, with what IP? | `grep "logged in with entity" <ATM10 latest.log>` (should show the **player's** IP) and `grep "has connected" velocity/logs/latest.log` |

## Changing a container's config (CasaOS apps)

```
sudo cat /var/lib/casaos/apps/<app>/docker-compose.yml     # read
sudo nano /var/lib/casaos/apps/<app>/docker-compose.yml    # edit
cd /var/lib/casaos/apps/<app> && sudo docker compose up -d --force-recreate
docker inspect <container> --format '{{json .HostConfig.PortBindings}}'   # verify
```

Gotchas learned the hard way:
- **A restart does not pick up runtime, mount or port changes.** Docker pins
  these when the container is *created*. Use `--force-recreate`.
- **The CasaOS dashboard's restart button didn't pick up edits** to the compose
  file. Use the command above.
- Running compose by hand skips the variables CasaOS normally injects. Plex
  needs `/var/lib/casaos/apps/plex-nvidia/.env` (`AppID=plex-nvidia`,
  `PUID=911`, `PGID=911`) or its config mount silently resolves to the wrong
  folder (`/DATA/AppData/config`).
- A `devices:` entry for hardware that isn't present (e.g. `/dev/dvb`) stops the
  container from being created at all.

## Verify the Minecraft chain end to end

```
# 1. ATM10 answers directly (loopback). Expect "1.21.1", 9001 max players
python3 scripts/mc-status-ping.py 127.0.0.1 25565

# 2. Through TCPShield -> Velocity. Expect Velocity's MOTD / "Velocity" version name
python3 scripts/mc-status-ping.py play.ethbra.com 25565

# 3. The real test: join from a client via play.ethbra.com, then
#    check the ATM10 log shows your real public IP, not 172.18.0.1
```

You **cannot** ping Velocity at `192.168.1.22:25565` from the LAN. RealIP and
the firewall deliberately drop anything not from TCPShield.

## Minecraft changes

**Add a mod:** ATM10 is NeoForge, so it takes *mods* in `mods/`, not Bukkit
plugins. Stop the server in Crafty, drop the jar in, start it. For a mod that
must also exist on clients, make sure players have the same one.

**Rotate the forwarding secret:**
1. `sops secrets/svalbard.yaml` and set a new random `velocity_forwarding_secret`;
   apply with `ansible-playbook site.yml -K --tags velocity`.
2. Put the same string in `config/atm10/proxy-compatible-forge.toml` (`secret`).
3. Restart ATM10 (Crafty) and `sudo systemctl restart velocity`.

**Update Velocity:** put the new jar in `/opt/velocity/` and its sha256 in
`ansible/roles/velocity/defaults/main.yml`, then apply (keep `velocity.toml`,
`forwarding.secret`, `plugins/`), then `sudo systemctl restart velocity`.

**If the LAN IP changes** (or you're moving machines): update `bind` in
`lan_ip` in `ansible/inventory/host_vars/svalbard.yml` (used by both `velocity.toml`
and the firewall script), apply, re-run
the script, restart Velocity. Better: reserve the IP in your router.

**Edit systemd units:** edit the copy in `systemd/`, then
`sudo cp systemd/<unit> /etc/systemd/system/ && sudo systemctl daemon-reload`.

## Plex

- Web UI from another machine needs **https**: `https://192.168.1.22:32400/web`
  (accept the certificate warning). Plain http only works on localhost.
- GPU check: `docker exec plex ls /dev/nvidia0`; in Plex, play something that
  forces a transcode and look for `(hw)` in the dashboard.
- Container GPU smoke test: `docker run --rm --gpus all ubuntu nvidia-smi`.
- **Pending cleanup:** the old native Plex is stopped and disabled but still
  installed. When you're happy with the container:
  `sudo apt purge plexmediaserver`. Its data in `/var/lib/plexmediaserver` stays
  until you delete it, and is your rollback.

## Troubleshooting (symptoms we actually hit)

| Symptom | Cause | Fix |
|---|---|---|
| Join fails: "Unable to connect you to all", Velocity log: `Backend server is online-mode!` | ATM10 has `online-mode=true` | set `online-mode=false`, restart ATM10 |
| Join fails: "internal server connection error", Velocity: `PluginMessagePacket was too big` | the mod-sync packet from 448 mods exceeds Velocity's default limit | keep `-Dvelocity.max-plugin-message-payload-size.clientbound=16777216` (and `max-known-packs=600`) in `velocity/start.sh` |
| Velocity won't start: `Can't bind to /0.0.0.0:25565 ... Address already in use` | Docker holds `127.0.0.1:25565`, which blocks a wildcard bind | bind the specific LAN IP in `velocity.toml` |
| Players kicked / stats weird after adding two forwarding mods | NeoVelocity and PCF both hook login | keep **only** PCF |
| ATM10 log full of `[pcf/]: Exception in PacketDecoder for /127.0.0.1` | Crafty's status ping closes early; PCF logs it | harmless; see PROGRESS for the log-filter attempt. Don't set Crafty's "Server IP" to the LAN IP (that is Velocity, and Crafty would show ATM10 offline) |
| Server list shows "Velocity" / 0 of 9001 instead of ATM10's data | passthrough can't work: the pack's compatibility mod appends a stray packet Velocity rejects | expected; MOTD and icon are set by hand in `velocity.toml` and `server-icon.png` |
| Plex unreachable over http on the LAN | Plex enforces secure connections for non-local clients | use https |
| Plex container loops with `Address in use` | the native `plexmediaserver` is running (both want 32400, host network) | stop/disable the native one |
| Container has no `/dev/nvidia*` after a restart | runtime is pinned at creation | `--force-recreate` |
| Edited compose but nothing changed | restart != recreate | see "Changing a container's config" |

## Storage and stacks cutover (IaC phase 3)

Moves `/DATA` from CasaOS's pool (NVMe + both drives) to a pool of the two
hard drives owned by fstab, app data to `/srv/appdata`, and the seven
containers from CasaOS to `stacks/` (deployed to `/opt/homelab/stacks`).
Downtime: ~15-30 min, all apps and ATM10. Nothing at the old locations is
changed or deleted, so rollback (below) is always open.

The switch is `storage_cutover_done` in `ansible/inventory/host_vars/svalbard.yml`.
While it is `false` the storage role leaves the CasaOS pool alone and the
stacks role only renders files.

### Before the window (any day, no downtime)

1. **Crafty: put ATM10 on Java 21.** Panel -> ATM10 -> Config -> execution
   command: replace the leading `java` with
   `/usr/lib/jvm/java-21-openjdk-amd64/bin/java` (keep the rest). Restart ATM10
   from the panel and join once. The stacks role checks this after the move.
2. **Media login in SOPS.** `cd ~/projects/active/homelab && EDITOR=nano sops secrets/svalbard.yaml`,
   add `media_apps_username` and `media_apps_password` (no `'` in either).
   Transmission switches to this login at the cutover.
3. **Render the stacks** (no containers are touched; also tightens
   `/srv/appdata` and its app folders from 0777 to 0755):
   ```bash
   cd ~/projects/active/homelab/ansible
   ansible-playbook site.yml -K --tags storage,stacks
   ```
4. **Pre-pull images** (Plex moves from `:latest` to a pinned tag):
   ```bash
   for s in prowlarr overseerr sonarr radarr transmission plex crafty; do
     sudo docker compose --project-directory /opt/homelab/stacks/$s pull -q; done
   ```
5. **Rehearse the new pool's mount**, read-only, next to the live one:
   ```bash
   sudo mkdir -p /mnt/pool-test
   sudo mount -t fuse.mergerfs -o ro,nofail,allow_other,cache.files=partial,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=50G,func.getattr=newest,fsname=mergerfs-test,x-systemd.requires-mounts-for=/mnt/HDD_A,x-systemd.requires-mounts-for=/mnt/HDD_B /mnt/HDD_A:/mnt/HDD_B /mnt/pool-test
   ls /mnt/pool-test            # Downloads, Media, ... as in /DATA
   sudo umount /mnt/pool-test && sudo rmdir /mnt/pool-test
   ```
   If the mount fails, stop here and bring the error to the next session.

### The window

Keep a second terminal open on the box. Every command is run from
`~/projects/active/homelab` unless it `cd`s.

1. **Stop ATM10 from the Crafty panel** and wait until it shows stopped.
2. **Stop the containers, then CasaOS, except its storage service** (it holds
   the old pool; stopping it unmounts `/DATA`):
   ```bash
   docker stop prowlarr overseerr sonarr radarr transmission plex crafty-container
   sudo systemctl stop casaos casaos-app-management casaos-gateway casaos-user-service casaos-message-bus rclone devmon@devmon
   docker ps                    # expect nothing running
   ```
3. **Final copy** (only what changed since the pre-seed; app data with
   `--delete`; records the old pool's file list):
   ```bash
   sudo scripts/storage-preseed.sh --final
   ```
   Expect `--final finished OK` and `0 file(s)` in every verification line.
4. **Release the old pool:**
   ```bash
   sudo systemctl stop casaos-local-storage
   sudo umount /DATA 2>/dev/null; findmnt /DATA    # expect no output
   sudo ls -A /DATA                                # expect empty
   findmnt /mnt/HDD_A; findmnt /mnt/HDD_B          # both still mounted
   ```
   If `/DATA` is not empty, stop and look: mergerfs won't mount over it.
5. **Flip the switch and mount the new pool.** Set `storage_cutover_done: true`
   in `ansible/inventory/host_vars/svalbard.yml`, then:
   ```bash
   cd ansible && ansible-playbook site.yml -K --tags storage,docker,deprecated
   findmnt /DATA                                   # SOURCE mergerfs, FSTYPE fuse.mergerfs
   cd .. && sudo scripts/storage-preseed.sh --compare
   ```
   `--compare` must say `missing ... 0`. Files "only in the new pool" are ones
   deleted from the NVMe after the pre-seed (old downloads); note them and
   tidy up later. Missing files: **roll back**.
6. **Remove the CasaOS containers and networks** (their compose files stay in
   `/var/lib/casaos/apps` for rollback):
   ```bash
   docker rm prowlarr overseerr sonarr radarr transmission plex crafty-container
   docker network rm crafty_default overseerr_default
   ```
7. **Bring up the stacks** (in order; stops at the first failure; then checks
   ATM10's loopback binding and Java 21):
   ```bash
   cd ansible && ansible-playbook site.yml -K --tags stacks
   docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
   docker network inspect crafty_default --format '{{json .IPAM.Config}}'   # 172.18.0.1 gateway
   ```
8. **Check each app:**
   - Prowlarr `:9696`, Overseerr `:5055`: open, settings intact.
   - Sonarr `:8989`, Radarr `:7878`: series/movies present, not "missing".
     **Settings -> Download Clients -> Transmission: enter the new media login**
     (it changed in step 7), Test, Save.
   - Transmission `:9091`: log in with the new media login; torrents listed.
   - Plex: library plays a file; a forced transcode shows `(hw)`.
   - Crafty `:8111`: log in, **start ATM10**, wait for "Done", then:
     `scripts/mc-status-ping.py 127.0.0.1 25565`, and join through
     `play.ethbra.com`; the ATM10 log shows your real IP.
9. **Full check run**, then commit and push `host_vars` with the switch on:
   ```bash
   cd ansible && ansible-playbook site.yml --check --diff -K    # expect changed=0
   ```

### Rollback

Possible at any point until the old copies are deleted (a week later).
Anything the apps wrote after step 7 is lost.

```bash
for s in prowlarr overseerr sonarr radarr transmission plex crafty; do
  sudo docker compose --project-directory /opt/homelab/stacks/$s down; done
sudo rm /etc/systemd/system/docker.service.d/homelab-storage.conf
sudo systemctl daemon-reload   # before the umount: Docker must no longer require /DATA
sudo umount /DATA
sudo nano /etc/fstab           # delete the /DATA line and the two /mnt/HDD_* lines Ansible added
sudo systemctl daemon-reload
sudo systemctl start casaos-local-storage && findmnt /DATA   # old pool back (/var/lib/casaos/files:...)
sudo systemctl start casaos casaos-app-management casaos-gateway casaos-user-service casaos-message-bus rclone devmon@devmon
for a in prowlarr overseerr sonarr radarr transmission plex-nvidia crafty; do
  (cd /var/lib/casaos/apps/$a && sudo docker compose up -d); done
```
Then set `storage_cutover_done: false` again (don't commit the `true`).

### After a week

Delete `/var/lib/casaos/files` and the old `/DATA/AppData` copies on the
drives (except `/mnt/HDD_A/AppData/crafty/backups`, which is live), and
remove CasaOS's files with an Ansible change. Update the "current" docs.

## Working with Claude in this environment

- The Claude session has **no passwordless sudo**. It prints the privileged
  commands and you run them.
- Never paste secrets into a session; transcripts are stored in `~/.claude/`.
