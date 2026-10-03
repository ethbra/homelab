# Infrastructure as code: design

> **Target state.** This describes where the server is heading, not how it runs
> today. For the live system see [../current/](../current/). The docs there are
> updated as each phase below actually lands; [PROGRESS.md](../../PROGRESS.md)
> records each step.

Status: phase 1 done (2026-10-02); phase 2a (mirror) in progress.

## Goals

1. **The repo is the source of truth.** Every file on the box that matters is
   either produced by this repo or listed here as a manual step. Nothing is
   edited by hand on the server.
2. **One place.** Host config, container stacks, scripts, secrets (encrypted),
   cloud DNS and docs live in this one repo. No config split across CasaOS,
   home directories and dashboards.
3. **Secure by construction.** No inbound ports for deployment, no plaintext
   secrets in git, nothing applied that you didn't sign.
4. **Provable.** CI shows the repo is valid; a drift check shows the live
   machine still matches it.
5. **Publishable.** The repo can be public without exposing secrets or the
   home WAN IP.

Non-goals for now: NixOS / full declarative OS (needs a reinstall), Kubernetes,
codifying stateful app data (worlds, Plex library, Crafty's database).

## Stack

| Layer | Tool | Covers |
|---|---|---|
| Host | Ansible | packages (NVIDIA toolkit, cloudflared), Docker daemon config, storage pool, systemd units, firewall, SSH hardening, Velocity |
| Containers | Docker Compose, deployed by Ansible | Plex, Sonarr, Radarr, Prowlarr, Overseerr, Transmission, Crafty |
| Secrets | SOPS + age | forwarding secret, tunnel token, API tokens |
| Cloud | OpenTofu + Cloudflare provider | DNS records, tunnel public hostnames |
| Validation | GitHub Actions (GitHub-hosted runners only) | yamllint, shellcheck, gitleaks, SOPS check; later ansible-lint, `docker compose config`, `tofu validate` |
| Deploy | pull agent on the box (systemd timer) | fetch, verify signatures, apply |
| Drift | systemd timer | `ansible-playbook --check --diff` |

## Deployment: the pull model

```
 you (working copy: ~/projects/active/homelab)
   edit -> signed commit -> git push
                              |
                              v
                          GitHub (public)
                              |  CI validates. CI never deploys and holds no server credentials.
                              |
          outbound HTTPS only |  (the server pulls; nothing connects in)
                              v
 server: homelab-pull.timer
   1. git fetch origin main into /opt/homelab (root-owned clone)
   2. refuse anything that is not a fast-forward of the last applied commit
   3. verify EVERY new commit is signed by a key in /etc/homelab/allowed_signers
   4. decrypt secrets with /etc/homelab/age.key (in memory, via Ansible)
   5. ansible-playbook site.yml   (logs to the journal)
   6. record the applied commit in /var/lib/homelab/applied
```

Why pull and not push (GitHub Actions or a webhook pushing to the server):

- **No inbound exposure.** A webhook needs a public endpoint; a push deploy
  needs SSH open to GitHub's runners. Pull only makes outbound requests.
- **GitHub is not the key to the server.** No deploy key or secret values are
  stored in GitHub. A GitHub account takeover can push commits, but the
  server applies only commits signed by your key (step 3).
- **No self-hosted runner.** On a public repo, pull requests from forks could
  run code on a self-hosted runner.

Details that matter:

- **The allowed-signers file lives outside the repo** (`/etc/homelab/allowed_signers`,
  root-owned). If it were read from the repo, an attacker's commit could add
  their own key to it and approve itself.
- **Every commit in the range is verified**, not only the tip. Merge commits
  made in the GitHub UI are signed by GitHub's key, so changes land by pushing
  signed commits to `main` (fast-forward), not by merging through the web UI.
- **Fast-forward only.** A force-push that rewrites history stops the agent;
  it alerts and waits for a human.
- **Manual apply:** `sudo homelab-apply` runs the same steps immediately,
  instead of waiting for the timer.
- **Bootstrap:** before the agent exists, the first run is
  `sudo ansible-playbook -i ansible/inventory ansible/site.yml` from the
  working copy. The playbook then installs the agent itself.
- **Optional, later:** the agent can also require a green CI status for the
  commit (GitHub's commit-status API works unauthenticated on public repos).

## Secrets: SOPS + age

Secret values are committed **encrypted**. A file in `secrets/` looks like:

```yaml
velocity_forwarding_secret: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
cloudflare_tunnel_token: ENC[AES256_GCM,data:...,type:str]
sops:
  age:
    - recipient: age1...
  mac: ENC[...]
```

Key names stay readable, so diffs show *which* secret changed; the values do
not. Each file is encrypted to every recipient in `.sops.yaml`:

| Key | Private key location | Used for |
|---|---|---|
| admin | `~/.config/sops/age/keys.txt` (mode 600) | editing secrets (`sops secrets/x.yaml`) |
| host | `/etc/homelab/age.key` (root, mode 400) | decryption by the pull agent at apply time |

Both private keys are also kept **offline** (password manager or printed/USB).
Lose every copy and the encrypted values are unrecoverable (re-create them at
the source and re-encrypt). The public keys in `.sops.yaml` are safe to publish.

Rules:

- Decrypted values exist only in memory during an Ansible run, and in the
  final rendered config files on the box (root- or service-owned, mode 600/640).
- **Git history is permanent.** If a private key ever leaks, every secret ever
  committed must be treated as exposed: rotate the *secrets* themselves, then
  rotate the key (`sops updatekeys`).
- Enforced by gitleaks + a SOPS check, both in pre-commit and in CI.
- GitHub Actions secrets are used only for things CI itself needs (e.g. a
  read-only Cloudflare token for `tofu plan` in phase 4). None today.

## Commit signing

SSH signing (no GPG needed):

- Signing key: `~/.ssh/id_ed25519` (with a passphrase); `commit.gpgsign = true`.
- The public key is added to GitHub as a **signing** key (commits show "Verified").
- The same public key goes in `/etc/homelab/allowed_signers` on the server.

## GitHub repository settings

- 2FA on the account.
- Ruleset on `main`: require signed commits, block force-pushes and deletion.
  *Not* "require status checks": that would also block the direct signed
  pushes this workflow relies on. The green-CI gate belongs in the pull agent
  instead (see "Optional, later" above).
- Actions: GitHub-hosted runners only; workflow permissions read-only;
  actions pinned to commit SHAs.
- Public is fine once phase 1's checks pass on the full history.

## What is public, and what isn't

| Item | In repo? |
|---|---|
| Secret values | encrypted only |
| Home WAN IP | **never** |
| LAN IP, internal ports | yes, as Ansible variables (RFC1918; reveals little) |
| `play.ethbra.com`, TCPShield ranges | yes (already public) |
| Which services run, LAN-only port map | yes (deliberate) |
| Router config, TCPShield dashboard, Plex claim | not code: documented as manual steps |

## Target repo layout

```
homelab/
  README.md  PROGRESS.md  CLAUDE.md
  .sops.yaml  .gitignore  .yamllint.yaml  .pre-commit-config.yaml
  .github/workflows/ci.yml
  docs/
    current/          how the server runs today (shrinks to "how it runs" as phases land)
    design/           this doc
  secrets/            SOPS-encrypted values only
  ansible/
    ansible.cfg
    inventory/        svalbard (ansible_connection: local) + group_vars
    site.yml
    roles/
      base/           packages, users, SSH hardening, unattended upgrades
      storage/        disks, mergerfs pool for /DATA
      docker/         engine, daemon.json (nvidia default runtime), toolkit
      firewall/       one managed ruleset (replaces the script + rules.v4)
      cloudflared/    package + token
      velocity/       /opt/velocity, service user, config, plugins (checksummed)
      stacks/         deploys stacks/* and runs `docker compose up`
      crafty_edges/   ATM10 config files, JVM args, extra mods (checksummed)
      gitops/         pull agent, drift timer, homelab-apply
  stacks/<app>/compose.yaml
  tofu/               Cloudflare DNS + tunnel ingress
  scripts/            small helpers (status ping, checks)
```

## Storage

**Decided 2026-10-02:** hard drives only in the pool, app data on the NVMe,
`/DATA` kept as the mount point, no RAID for now (a third drive isn't planned;
revisit SnapRAID if one is added).

Today `/DATA` is a mergerfs pool of `/var/lib/casaos/files` (on the NVMe,
~175 GB used), `/mnt/HDD_A` and `/mnt/HDD_B`, and it is **mounted by
`casaos-local-storage`**, not by fstab. Target:

- The `storage` role owns the pool: disks by UUID, mergerfs from apt,
  mounted at `/DATA` (Plex's library stores `/DATA/Media` paths) with
  `minfreespace=50G`, `moveonenospc=true`, `dropcacheonclose=true`,
  `func.getattr=newest`, `category.create=mfs`.
- **Branches: `/mnt/HDD_A` and `/mnt/HDD_B` only.** The NVMe branch
  (`/var/lib/casaos/files`, about 176 GB) leaves the pool: with a 1 MB
  `minfreespace` it could otherwise fill the root filesystem.
- **App data moves to `/srv/appdata` on the NVMe**, outside FUSE (faster, and
  safer for the apps' SQLite databases). About 93 GB, today spread across all
  three branches.
- The move happens once, in a maintenance window with the containers stopped:
  `rsync -aHAX`, verified before anything old is removed. Because the app data
  paths change, it is done together with moving the stacks out of CasaOS.
- Containers start only after the pool is mounted
  (`RequiresMountsFor=/DATA` on the compose units).
- Storage hosting (remote file access, a future feature) is designed in this
  repo from the start, on top of this role.

## Leaving CasaOS

CasaOS today owns the compose files (`/var/lib/casaos/apps/<app>`) and the
`/DATA` mount. Order of exit:

1. Storage role takes over `/DATA` (above). After this, CasaOS owns nothing
   critical.
2. Stacks move one at a time: `docker compose down` in the CasaOS directory,
   `up` from `/opt/homelab/stacks/<app>`, same volume paths (no data moves).
   Lowest risk first: prowlarr, overseerr, sonarr, radarr, transmission,
   plex, crafty.
3. CasaOS is removed by an Ansible task (stop and disable the six `casaos*`
   services and `devmon@devmon`, remove binaries and units). **Not** by
   `casaos-uninstall`: its prompts default to deleting *all* containers,
   images and `/DATA/AppData`.

Things CasaOS currently does implicitly, which the compose files must state:

- Plex: `PUID`/`PGID` and the config path (CasaOS injects `AppID`; without it
  the config mount resolves to the wrong folder).
- Crafty: pin `name: crafty` and the `crafty_default` network's subnet and
  gateway (`172.18.0.1`). PCF's `approvedProxyHosts` trusts that gateway; if
  the network is recreated with a different subnet, joins fail.
- **ATM10 loopback invariant** becomes an automated assertion: the playbook
  fails if 25565 is published on anything but `127.0.0.1`.

## Decisions for the container stacks (phase 3)

Made 2026-10-02:

- **Time zone:** `America/Los_Angeles` everywhere (today the stacks mix
  `Europe/London`, `US/Pacific` and `America/Los_Angeles`).
- **Images pinned to versions**, Plex included. Plex went to `:latest` only
  while chasing what turned out to be the HTTP/HTTPS link issue.
- **No plaintext credentials in compose files.** App logins come from
  `secrets/` via SOPS and are rendered into root-only `.env` files at deploy
  time. One shared login for the media apps (Sonarr, Radarr, Prowlarr,
  Transmission); Crafty has its own (plus 2FA). The *arr apps store
  credentials in their own databases, so their login is set once in each UI
  from the SOPS value; Transmission's comes from the environment.
- **ATM10 runs on Java 21**, named explicitly in Crafty's execution command
  (the container's default `java` is 25, and that is what ATM10 used until
  2026-10-02). The Crafty role asserts it.
- **Crafty runs unprivileged.** `privileged: true` was a workaround for an old
  Java problem; it is removed during the move and ATM10 is tested afterwards.
- **Crafty publishes only** the panel (8111) and ATM10 on `127.0.0.1:25565`.
  Its other ports (8100, 8112, 19132/udp) are dropped; 25566 and up stay
  unpublished (Crafty reserves them for extra servers).

## Crafty and ATM10

Crafty is stateful and UI-driven, so only the edges are code:

- pinned pack version (All the Mods 10 v4.12) and NeoForge version
- `server.properties` keys that matter (`online-mode=false`, port)
- PCF config (secret from SOPS, `approvedProxyHosts`)
- `user_jvm_args.txt`
- extra mods added by us (PCF) with SHA-256 checksums

Never in the repo: the world, the pack's 448 jars, Crafty's database, backups.

## Not code (manual, with a checklist)

- Router: static forward TCP 25565, DHCP reservation for the server, UPnP setting
- TCPShield dashboard: backend address, domain
- Plex claim / account sign-in
- Offline key backups
- Cloudflare tunnel ingress until phase 4

## Phases

| # | Phase | Exit criteria |
|---|---|---|
| 1 | **Skeleton and proof** | repo under git; first signed commit; pre-commit installed; SOPS round-trip works with both keys; gitleaks clean on full history; CI green after first push |
| 2a | **Host baseline: mirror** | Ansible roles describe today's host exactly, defects included; `--check --diff` against the live box is **empty** |
| 2b | **Host baseline: change** | planned changes, one reviewed commit each: secrets from SOPS (done in code), SSH key-only, retire Samba/xrdp/ollama and the old `admin` account, Velocity to `/opt/velocity`, storage role takes over `/DATA`, cleanup |
| 3 | **Containers** | all seven stacks run from `stacks/`; CasaOS removed; `docs/current/` rewritten to match |
| 4 | **Cloudflare + GitOps** | DNS/tunnel in OpenTofu (state encrypted, not in git); pull agent and drift timer running |
| 5 | **Storage hosting** | designed and built in the repo |

Phase 2 is the largest. Writing roles that match the live system exactly
(empty diff) is what makes later phases safe.

### How phase 2 is done

- **Mirror first, change second.** A 2a role must produce an empty diff
  against the live box, even where the live state is wrong (e.g. a secret
  file's mode). Fixes come afterwards as their own commits, so every change
  to the machine is a visible, reviewable diff and nothing changes by accident
  while the code is being written.
- **Verbatim mirrors.** Files under a role's `files/` and `templates/` are
  copied from the live box byte for byte (only variables like the LAN IP are
  substituted). The whitespace fixers in pre-commit skip them for that reason.
- **Scope is what we manage, not the whole OS.** Packages, units and configs
  for the services in this repo. The desktop, GNOME and incidental packages
  are out of scope; drift detection covers managed resources only.
- **Disruptive restarts are opt-in.** Handlers that would restart Docker
  (every container) or Velocity (every player) only print a reminder unless
  the run sets `-e allow_disruptive_restarts=true`.
- **Binaries stay out of git.** Jars are verified against pinned SHA-256
  checksums instead.
- **Checking:** `ansible-playbook site.yml --check --diff -K` from `ansible/`.
  Without `-K` (no sudo) it still checks everything except root-only reads.

## Documentation standard

- `docs/current/` describes the live system. It changes when a phase lands,
  never in anticipation.
- `docs/design/` describes the target. When a phase lands, the parts it
  covers move from "target" to "current".
- `PROGRESS.md` logs every change; decisions get a short record in
  `docs/current/DECISIONS.md` once they are live.

## Open questions

(Decided: Ansible is `ansible-core` 2.19 via pipx, pinned in CI and in this doc.)

- **Alerting channel** for pull failures and drift (ntfy, email, Discord webhook).
- **Firewall tool:** keep iptables (matches today) or move to nftables with
  Docker-aware rules. Decide in phase 2.
- **OpenTofu state:** local on the box with OpenTofu's built-in state
  encryption, or a remote backend (e.g. Cloudflare R2).
- **License** for the public repo.
