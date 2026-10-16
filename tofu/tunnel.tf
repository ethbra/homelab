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

# No routes yet (remote config version 0). The first hostname adds
# config.ingress here, ending with the http_status:404 catch-all.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "host" {
  account_id = local.account_id
  tunnel_id  = local.tunnel_id
  source     = "cloudflare"
}
