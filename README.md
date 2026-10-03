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
  ansible/                   host configuration: the source of truth for everything it manages
    site.yml                 the playbook; roles/ holds one role per service
  secrets/                   SOPS-encrypted values (tunnel token, forwarding secret)
  scripts/
    mc-status-ping.py        Minecraft status-ping tester (see RUNBOOK)
    check-sops-encrypted.sh  used by pre-commit and CI
    obsolete/                superseded scripts (the roles replaced them), kept for reference
  config/                    local-only symlinks to live files not yet managed (ATM10, CasaOS)
  .github/workflows/ci.yml   CI: lint, Ansible checks, secret scanning (never deploys)
  .sops.yaml                 who can decrypt files in secrets/
  .pre-commit-config.yaml    the same checks, run locally before each commit
```

`config/` is local only and gitignored: it links to live files that no role
manages yet (ATM10's config, CasaOS's compose files). Each link goes away when
its phase moves that config into the repo.

## Changing something that a role manages

Velocity, the TCPShield firewall, cloudflared, Docker's daemon config, SSH and
the NVIDIA toolkit are managed by `ansible/`. Change them in the repo, then
apply (see docs/current/RUNBOOK.md). Editing the live file by hand works until
the next run, which puts the repo's version back. Files under `/var/lib/casaos/apps/` are
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
