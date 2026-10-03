# Homelab (Svalbard)

One Debian box running a media stack, a modded Minecraft server and a few
supporting services. This directory is the single place to understand it:
what runs, where its config lives, what is exposed, and what we changed and why.

Last verified: 2026-10-01.

## Start here

| I want to...                                  | Read                                                   |
|-----------------------------------------------|--------------------------------------------------------|
| See what's done / what's still open           | [PROGRESS.md](PROGRESS.md)                             |
| See where this is heading (infrastructure as code) | [docs/design/IAC-DESIGN.md](docs/design/IAC-DESIGN.md) |
| Understand how the pieces fit together        | [docs/current/ARCHITECTURE.md](docs/current/ARCHITECTURE.md)           |
| Find a service, its port, config and data     | [docs/current/SERVICES.md](docs/current/SERVICES.md)                   |
| Check ports, firewall, secrets, known risks   | [docs/current/NETWORK-AND-SECURITY.md](docs/current/NETWORK-AND-SECURITY.md) |
| Restart/update/fix something                  | [docs/current/RUNBOOK.md](docs/current/RUNBOOK.md)                     |
| Know why something is set up the way it is    | [docs/current/DECISIONS.md](docs/current/DECISIONS.md)                 |

## Directory layout

```
homelab/
  README.md  PROGRESS.md  CLAUDE.md
  docs/
    current/                 how the server runs today (the table above)
    design/                  the target infrastructure-as-code design
  scripts/                   one-time installers + the live firewall script
    install-nvidia-container-toolkit.sh
    install-cloudflared.sh
    firewall-velocity-tcpshield.sh   -> symlink (real file is ../firewall-velocity-tcpshield.sh)
    mc-status-ping.py                Minecraft status-ping tester (see RUNBOOK)
    obsolete/                        superseded scripts, kept for reference
  systemd/                   templates for units installed in /etc/systemd/system
  velocity/                  -> symlink to ../velocity (the live Velocity proxy)
  config/                    symlinks to the real, live config files (single source of truth)
    atm10/  velocity/  casaos-apps  iptables-rules.v4
  .github/workflows/ci.yml   CI: lint + secret scanning (never deploys)
  .sops.yaml                 who can decrypt files in secrets/
  .pre-commit-config.yaml    the same checks, run locally before each commit
```

The symlinks (`velocity/`, `config/`, `scripts/firewall-velocity-tcpshield.sh`)
are **local only** and gitignored: they point outside the repo, and `velocity/`
holds the forwarding secret. They go away as the IaC phases replace them with
real files.

## Why some things are symlinks, not moved

`velocity.service` and `velocity-firewall.service` are installed in
`/etc/systemd/system` and point at the **current** paths
(`~/projects/active/velocity/` and `~/projects/active/firewall-velocity-tcpshield.sh`).
Moving those files would break boot-time startup. They are linked in here
instead. To relocate them for real, move the files, edit the unit files in
`systemd/`, then `sudo cp` them over and `sudo systemctl daemon-reload`.

The files under `config/` are links to the live files, so editing through
either path edits the same file. Files under `/var/lib/casaos/apps/` are
root-only, so use `sudo cat` to read them.

## Rules for this directory

- **No plaintext secrets in here.** Docs say *where* a secret lives, never its
  value. Secrets that the repo must carry go in `secrets/`, encrypted with SOPS
  (see the design doc). gitleaks checks this in pre-commit and CI.
- **No home WAN IP** in the repo; this repo is meant to be published.
- Anything that changes a port, firewall rule, bind address or secret gets a
  line in [PROGRESS.md](PROGRESS.md) and, if it changes exposure, an update to
  [docs/current/NETWORK-AND-SECURITY.md](docs/current/NETWORK-AND-SECURITY.md).
- Other projects (`neet2neat`) and `archive/` are separate and not covered here.
