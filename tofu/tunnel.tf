# Cloudflare Tunnel "Host" (cloudflared role on the box). Mirrors the live
# tunnel; imported, not created. Its token stays in SOPS and the cloudflared
# role, never in tofu.

locals {
  account_id = "0b06150c6bf4109441c4e8c4e8cad17d"
  tunnel_id  = "33ada726-238d-4526-b332-1d2dc369c9e0" # Host
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.host
  id = "${local.account_id}/${local.tunnel_id}"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.host
  id = "${local.account_id}/${local.tunnel_id}"
}

# Remotely managed (config_src = "cloudflare"): routes live in the _config
# resource below, not in a config file on the box.
resource "cloudflare_zero_trust_tunnel_cloudflared" "host" {
  account_id = local.account_id
  name       = "Host"
  config_src = "cloudflare"

  # Replacing the tunnel would invalidate the token cloudflared runs with.
  lifecycle {
    prevent_destroy = true
  }
}

locals {
  # Every public hostname goes to nginx (stacks/nginx), which routes by Host.
  # This list is the allowlist of what the tunnel serves.
  nginx = "http://127.0.0.1:8080"

  # cloudflared itself checks the Access token before forwarding, so a request
  # that somehow skipped Access never reaches nginx.
  access_required = {
    required  = true
    team_name = "ethbra"
    aud_tag   = [cloudflare_zero_trust_access_application.homelab.aud]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "host" {
  account_id = local.account_id
  tunnel_id  = local.tunnel_id
  source     = "cloudflare"
  config = {
    ingress = [
      {
        hostname       = "dash.ethbra.com"
        service        = local.nginx
        origin_request = { access = local.access_required }
      },
      {
        hostname       = "crafty.ethbra.com"
        service        = local.nginx
        origin_request = { access = local.access_required }
      },
      # Public map: no Access token to check (bypass).
      {
        hostname = "play.ethbra.com"
        service  = local.nginx
      },
      { service = "http_status:404" },
    ]
  }
}
