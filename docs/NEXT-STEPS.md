# Next steps

Where the infrastructure-as-code work stands and what comes next, in order.
The design is in [design/IAC-DESIGN.md](design/IAC-DESIGN.md); the history is in
[../PROGRESS.md](../PROGRESS.md). Update this file whenever a step is done.

Last updated: 2026-10-15.

## Where we are

| Phase | State |
|---|---|
| 1. Repo, CI, SOPS, signed commits | done |
| 2a. Roles that mirror the live host | done |
| 2b. Host changes | done: secrets via SOPS, SSH key-only, Samba/xrdp/ollama/`admin` removed, Velocity in `/opt/velocity` as its own user, firewall script out of `/home`. Cleanup applied 2026-10-03 |
| 3. Storage + containers out of CasaOS | **done 2026-10-03**: cutover, old copies deleted, CasaOS removed |
| 4. Pull agent, drift check, Cloudflare in OpenTofu | pull agent + drift check **live 2026-10-04** (pushes to `main` deploy); DNS and tunnel in OpenTofu (2026-10-12, 2026-10-15), validated in CI; first hostname next |

## 0-3. Done

Pre-seed, cleanup, cutover off CasaOS (2026-10-03) and removal of the
migration scaffolding (2026-10-13). The details are in
[../PROGRESS.md](../PROGRESS.md) and git history.

Left over:

- [ ] Docker `min-api-version: "1.24"` (`ansible/roles/docker/defaults`) was
      only for CasaOS's old client; drop it. Changes `daemon.json`, so Docker
      restarts: needs `-e allow_disruptive_restarts=true` and a quiet moment
- [ ] `deprecated` role: keep for a few months, then prune entries whose
      removal has held (on a fresh install they do nothing)
- [ ] Docker: remove the other unused images (optional; list in PROGRESS
      2026-10-03)

## 4. Phase 4

- [x] Pull agent + drift check: `gitops` role (code, 2026-10-04). Logic tested
      against a scratch repo: signed commits apply; unsigned, foreign-key,
      bad-commit-under-a-good-tip and force-push are refused with one alert;
      a failed apply alerts once and recovers with `homelab-apply`
- [x] Bootstrapped 2026-10-04: first root run `changed=0` (applied 3feefca);
      first automatic deploy 7d0e85c (the webhook commit) at 19:42
- [x] Discord alerts working (`alert_webhook_url` in SOPS)
- [x] First drift check 2026-10-05 04:30: `no drift at 7d0e85c`
- [x] First failed automatic apply (27caae2, CasaOS unit check) handled as
      designed and fixed by the next push (ebaf399 applied 2026-10-05 20:12)
- [ ] Cloudflare DNS and tunnel ingress in OpenTofu:
  - [x] `tofu/` skeleton: provider pinned, state + plan encryption enforced,
        passphrase generated into `secrets/cloudflare.yaml` (admin key only);
        `scripts/tofu.sh` wrapper; OpenTofu 1.13.1 in the `base` role
        (installed by the agent 2026-10-05)
  - [x] Owner: Cloudflare API token -> `secrets/cloudflare.yaml` as `cloudflare_api_token`
  - [x] Read the live DNS records and tunnel ingress (2026-10-07). The zone
        has one record, `play.ethbra.com` (CNAME to TCPShield), now in
        `tofu/dns.tf` with an `import` block; `scripts/tofu.sh plan`:
        1 to import, 0 to add/change/destroy. The tunnel `Host` is
        dashboard-managed but has **no ingress** (remote config version 0,
        no DNS record points at it): it is connected and serves nothing
  - [x] Owner: first apply (imports only), then commit `tofu/terraform.tfstate`
        (encrypted) and `tofu/.terraform.lock.hcl` (0e75a43; plan on
        2026-10-12: no changes)
  - [x] Tunnel's future decided (2026-10-13): **keep** it and the
        `cloudflared` role; hostnames and policies go into tofu
  - [x] Import the tunnel into tofu: `tofu/tunnel.tf` (2026-10-15),
        `cloudflare_zero_trust_tunnel_cloudflared` (`Host`) and its
        `_config` (no ingress yet), with `import` blocks; plan: 2 to
        import, 0 to add/change/destroy. The token stays in SOPS and the
        `cloudflared` role, not in tofu
  - [x] Owner: apply (imports only) and commit (d4f2722, CI green);
        plan on 2026-10-15: no changes
  - [ ] Web entry point (decided 2026-10-15; design in
        [design/WEB-ENTRY.md](design/WEB-ENTRY.md)): nginx behind the
        tunnel, Access with Google login; public `dash`, `crafty` and the
        BlueMap map on `play.ethbra.com`. Plex, the -arrs and Transmission
        never go through the tunnel. In order:
    - [ ] `stacks/homepage/` on the LAN (`192.168.1.22:3000`), read-only
          docker socket proxy: written and tested 2026-10-15; deploys on
          push (pull agent). Then: open it, check tiles and status
    - [ ] Later: API-key widgets (Sonarr/Radarr/Prowlarr/Plex/Overseerr
          keys in SOPS as `HOMEPAGE_VAR_*` via `stacks_env`)
    - [ ] `stacks/nginx/` on `127.0.0.1:8080`: `dash`, `crafty`,
          `default_server` 444
    - [x] Owner (2026-10-15): token permissions added (Access: Apps and
          Policies Edit; Organizations, Identity Providers, and Groups Edit;
          verified by API); team domain `ethbra.cloudflareaccess.com`;
          Google OAuth client, `google_oauth_client_id`/`_secret` in
          `secrets/cloudflare.yaml`
    - [ ] Tofu: Google IdP + Access apps (`homelab`, `*.ethbra.com` safety
          net), then ingress + proxied DNS for `dash`, `crafty`
    - [ ] BlueMap mod on ATM10; Crafty compose `127.0.0.1:8100` (ATM10 port
          check before/after); nginx `play` block
    - [x] Owner: `mc.ethbra.com` added in TCPShield (2026-10-15)
    - [ ] Tofu: `mc` CNAME + SRV
          `_minecraft._tcp.play`; test a join; then `play` to the tunnel
          with an Access bypass app
  - [x] `tofu fmt`/`validate` in CI (2026-10-13; no secrets needed)
- [ ] Later: agent also requires green CI for the commit (GitHub status API)

## POCs (parked)

- Local DNS for the nice names on the LAN (e.g. AdGuard Home); the Orbi
  can't host custom records
- Jellyfin as an eighth stack next to Plex (free NVIDIA transcoding), with
  `/DATA/Media` read-only; Jellyseerr would replace Overseerr if it stays
- vcclient (GPU voice changer), removed 2026-10-03; rebuild if wanted

## Owner to-dos (any time)

- [x] Rotate the Cloudflare tunnel token (done 2026-10-02 23:41; 4 connections
      healthy on the new token). Steps kept below for next time.
- [x] Crafty: ATM10's execution command uses Java 21 (2026-10-03)
- [x] Media-apps login in SOPS (2026-10-03)
- [x] Deleted `~/projects/active/velocity` (2026-10-13)
- [x] `/DATA/Media/Shared` dealt with and removed (2026-10-13)
- [x] noip.com: DDNS key/hostnames deleted (2026-10-13)
- [x] `192.168.1.22` reserved in the router (2026-10-13)

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
- ~~Cloudflare tunnel~~ decided 2026-10-13: keep; ingress and policies in tofu
- ~~What goes behind the tunnel~~ decided 2026-10-15: `dash`, `crafty` (Google
  login via Access) and the public BlueMap on `play.ethbra.com` (game via SRV),
  all through nginx; Plex, the -arrs, Transmission LAN only. See
  [design/WEB-ENTRY.md](design/WEB-ENTRY.md)
- Container control (start/stop) from a dashboard: later, a separate tool
- Router (Orbi RBR50): not manageable as code (no API/provider). Its expected
  state (reservation, the one forward, UPnP) stays in NETWORK-AND-SECURITY.
  Open: turn UPnP off? Revisit as code only if it is replaced by
  OpenWrt/OPNsense
- License for the public repo
- Redundancy: SnapRAID if a third drive is ever added

## Resuming a session

```bash
cd ~/projects/active/homelab && git pull && git log --oneline -5
cd ansible && ansible-playbook site.yml --check --diff -K   # expect changed=0
```
