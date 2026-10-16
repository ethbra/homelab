# Web entry point: nginx, Cloudflare Access, Homepage, BlueMap: design

> **Target state.** Nothing here is live yet. For the live system see
> [../current/](../current/); [../NEXT-STEPS.md](../NEXT-STEPS.md) tracks the
> steps and [PROGRESS.md](../../PROGRESS.md) records them as they land.

Status: live 2026-10-15 (`dash`, `crafty` behind Access; public map on `play.ethbra.com`; game via SRV).

## Decisions (owner, 2026-10-15)

1. **Reachable from outside, through the tunnel `Host`:** `dash` (Homepage),
   `crafty` (Crafty panel) and the BlueMap web map. Nothing else.
2. **Never through the tunnel:** Plex, Overseerr, Sonarr, Radarr, Prowlarr,
   Transmission. They stay LAN-only, as today. They get no nginx server
   block, no tunnel rule and no DNS record.
3. **Subdomains, not paths** (`crafty.ethbra.com`, not `dash.ethbra.com/crafty`).
   Most of these apps can't run under a path prefix (Crafty and Overseerr don't
   support it well or at all), and rewriting links and websockets is fragile.
   The dashboard is still the front door: its tiles link to the subdomains.
4. **One entry point, one login:** Cloudflare Access with **Google login** in
   front of `dash` and `crafty`. One Access application, so one sign-in covers
   both.
5. **Everything stays locally accessible** on `192.168.1.22:<port>` without
   Cloudflare, including Homepage.
6. **The map is public** (no login) and lives on **`play.ethbra.com`**, the
   same name players use for the game. The game moves to an SRV record (below).
7. **Container control** (start/stop) is later and a separate tool. Homepage's
   read-only Docker view (status, stats) is enough for now.

## Shape

```
Internet ── Cloudflare (Access: Google) ── tunnel ── cloudflared ── nginx 127.0.0.1:8080
                                                                      ├─ dash.ethbra.com   -> Homepage  127.0.0.1:3000
                                                                      ├─ crafty.ethbra.com -> Crafty    https://127.0.0.1:8111
                                                                      └─ play.ethbra.com   -> BlueMap   127.0.0.1:8100
LAN ── 192.168.1.22:3000 (Homepage), :8111 (Crafty), :5055, :8989, ... (direct, no Cloudflare)

Players ── play.ethbra.com (SRV) -> mc.ethbra.com -> TCPShield -> Velocity -> live server (unchanged)
```

## Pieces

### Tunnel and DNS (tofu)

- **Tunnel ingress: one rule per hostname, all to `http://127.0.0.1:8080`**,
  then the `http_status:404` catch-all. These are explicit, not a wildcard:
  the list in `tofu/tunnel.tf` is the allowlist of what is public. Adding
  a service means one ingress line and one DNS record.
- DNS: proxied CNAMEs `dash`, `crafty`, `play` ->
  `33ada726-238d-4526-b332-1d2dc369c9e0.cfargotunnel.com`. No wildcard record.

### nginx (`stacks/nginx/`)

- Pinned `nginx` image, `network_mode: host`, **listens on `127.0.0.1:8080`
  only**. Its only client is `cloudflared`. The LAN keeps using the apps'
  own ports. No TLS in nginx: Cloudflare terminates TLS, and the tunnel
  carries it to the box.
- One `server` block per hostname (`server_name` must match exactly). A
  `default_server` returns `444`, so an unknown `Host` gets nothing.
- Crafty: `proxy_pass https://127.0.0.1:8111` (its self-signed cert, so
  `proxy_ssl_verify off`), with websocket upgrade headers.
- Real client IP in the logs: `set_real_ip_from 127.0.0.1;`
  `real_ip_header CF-Connecting-IP;`.
- Config in the repo, deployed by the `stacks` role like the other stacks.

### Homepage (`stacks/homepage/`)

- Pinned `ghcr.io/gethomepage/homepage`, published on `3000` (LAN and
  loopback). `HOMEPAGE_ALLOWED_HOSTS=dash.ethbra.com,192.168.1.22:3000`.
- Docker status through a **read-only socket proxy** (pinned
  `tecnativa/docker-socket-proxy`, `CONTAINERS=1`, `POST=0`, socket mounted
  `:ro`). It sits on an internal network shared only with Homepage and is
  never published. The raw socket would be root on the host for whoever
  takes over Homepage.
- Config in the repo (`stacks/homepage/config/*.yaml`). Widget API keys
  (Sonarr, Radarr, Prowlarr, Plex token) come from SOPS as
  `HOMEPAGE_VAR_*` through the stack's root-only `.env` (`stacks_env`).
- Tiles for the LAN-only apps link to `http://192.168.1.22:<port>`. They
  work at home and deliberately don't from outside. Their widgets still show
  data from outside, because Homepage fetches it server-side.

### Cloudflare Access (tofu)

- **Google login** (`cloudflare_zero_trust_access_identity_provider`, type
  `google`). Google enforces the account's 2-Step Verification, including
  **Google prompts** (tap to approve on the phone: the push notification.
  The Google Authenticator app itself only shows codes). Make sure the account
  has 2SV with Google prompts and/or a passkey.
- **Application "homelab"** (self-hosted), destinations `dash.ethbra.com` and
  `crafty.ethbra.com`. Allowed IdPs: Google only, so One-time PIN is off and
  there is no weaker path in. Session about 24h. Policy: allow, include = the
  owner's email.
- **Safety net:** an application on `*.ethbra.com` with the same owner-only
  policy. Any future proxied name is login-only until it is deliberately
  opened. More specific applications take precedence over it.
- **Map:** an application on `play.ethbra.com` with a **bypass** policy
  (everyone), so the map is public.
- **cloudflared checks the Access token too** (`origin_request.access` on each
  ingress rule, AUD of `homelab`), so a request that somehow skips Access never
  reaches nginx.
- The owner's email is `access_owner_email` in `secrets/cloudflare.yaml`,
  not in the public `.tf` files.
- Crafty keeps its own login and 2FA behind Access (two layers).
- Optional later: Access **independent MFA** (2026-04; TOTP, security key or
  passkey/biometric, checked by Cloudflare itself). Google's OIDC login doesn't
  tell Access *how* you signed in, so this is the only way for Cloudflare to
  require a second factor itself. Free-plan availability is unconfirmed.
- The Google client secret comes from SOPS through `scripts/tofu.sh` as a
  `TF_VAR_` and is stored in the (encrypted) state.

### BlueMap

- BlueMap belongs to a **server**, not to the infrastructure: the map shows
  whichever server is running and has BlueMap with its web server on `8100`
  (mod for NeoForge/Fabric, plugin for Paper). A server without it means
  `play.ethbra.com` shows nginx's 502 until one with it runs. Nothing in the
  repo changes when switching servers.
- Crafty compose: **`127.0.0.1:8100:8100`** (loopback only; nginx reaches it).
- Per-server setup (`config/bluemap/` in the server's directory, written on
  first start): `accept-download: true`, `render-thread-count: 2` (leave cores
  for the game), `metrics: false`; overworld `sorting: -1` in
  `maps/world.conf` (the map opens on the lowest; ties go alphabetically, so
  without it a modded pack opens on e.g. the Aether); then `bluemap reload`.
  Live player markers on (owner's choice).
- First render of a big modded world takes hours; modded blocks may render
  without textures.
- nginx keeps the map read-only and rate limited (the only entry without a
  login): GET only, 1k bodies, per-visitor 30 r/s with a 500 burst, 50
  connections (429 beyond). Raise the burst if a big map's page loads start
  getting 429s (`docker logs nginx | grep ' 429 '`).
- Done 2026-10-15 for ATM10-8-2 (BlueMap 5.7-neoforge).

### Minecraft DNS: SRV, so `play.ethbra.com` can serve the map

`play.ethbra.com` is now a DNS-only CNAME to TCPShield. TCPShield proxies only
Minecraft, so HTTPS to that name goes nowhere. Following
[TCPShield's SRV setup](https://docs.tcpshield.com/panel/dns-setup):

- `mc.ethbra.com`: new helper, DNS-only CNAME to the TCPShield target that
  `play` has now.
- `_minecraft._tcp.play.ethbra.com`: SRV `0 5 25565 mc.ethbra.com`. Port
  25565, because TCPShield maps the port itself. The target is the helper,
  never the TCPShield CNAME directly ("Invalid host").
- `play.ethbra.com`: becomes a proxied CNAME to the tunnel (the map).

Players keep typing `play.ethbra.com`. Java clients look up the SRV first.
The home IP stays hidden and no port forwards are needed.

**Order (no downtime):** the SRV name is separate from `play`, so it can
coexist with the current CNAME.

1. Owner: add `mc.ethbra.com` to the TCPShield network's domains, keeping
   `play`, **and verify it**. Clients send the SRV target as the handshake
   hostname, so an unverified `mc` gives "Invalid hostname" (done 2026-10-15). Which hostname the client sends in the handshake decides which one
   TCPShield checks, so allow both.
2. Tofu: add `mc` + the SRV, with `play` unchanged. Test:
   `scripts/mc-status-ping.py mc.ethbra.com 25565`, then a real client join
   via `play.ethbra.com` (now through the SRV). Check Velocity's log for the
   handshake hostname.
3. Only then, tofu: switch `play` to the tunnel and add its Access bypass app.

Rollback: point `play` back to TCPShield (one tofu change). The SRV can stay.

## Owner prerequisites (done 2026-10-15)

- API token: Account / Cloudflare Tunnel / Edit; Account / Access: Apps and
  Policies / Edit; Account / Access: Organizations, Identity Providers, and
  Groups / Edit; Zone / Zone / Read; Zone / DNS / Edit. Each verified by API.
- Zero Trust team domain: `ethbra.cloudflareaccess.com`. The organization's
  display name is still the generated `old-bonus-eaff...`. Cosmetic; it can be
  set in tofu with the Access step.
- Google OAuth consent screen: **External**, publishing status **Testing**,
  the owner as the only test user. "Internal" fails with `403 org_internal`
  for a gmail.com account. "In production" needs a privacy-policy URL.
  Testing has no cost here, because Access doesn't use refresh tokens.
- Google OAuth client (Web). Redirect URI
  `https://ethbra.cloudflareaccess.com/cdn-cgi/access/callback`. Keys
  `google_oauth_client_id` and `google_oauth_client_secret` in
  `secrets/cloudflare.yaml` (admin key only). `scripts/tofu.sh` will pass
  them as `TF_VAR_`s.
- TCPShield: `mc.ethbra.com` added to the network's domains (`play` kept).

## Order of work

1. Homepage stack on the LAN (`192.168.1.22:3000`), read-only Docker.
2. nginx stack on `127.0.0.1:8080` (`dash`, `crafty`). Test locally with
   `curl -H 'Host: dash.ethbra.com' http://127.0.0.1:8080`.
3. Tofu: Google IdP, Access apps (`homelab` + `*.ethbra.com` safety net),
   then ingress + DNS for `dash` and `crafty`. Access goes in before or with
   the hostnames, never after.
4. BlueMap mod, `127.0.0.1:8100`, nginx `play` block.
5. SRV migration (above), then `play` to the tunnel with the bypass app.

Steps 1-2 need nothing from Cloudflare. The owner prerequisites for 3-5 are
done.

## Sources

- TCPShield DNS / SRV setup: <https://docs.tcpshield.com/panel/dns-setup>
- Homepage Docker integration and socket proxy: <https://gethomepage.dev/configs/docker/>
- Cloudflare Access with Google:
  <https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/google/>
- Access independent MFA:
  <https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/>
- Google prompts for 2SV:
  <https://workspaceupdates.googleblog.com/2017/10/making-google-prompt-primary-choice-for-2sv.html>
