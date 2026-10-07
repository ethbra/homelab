# DNS for ethbra.com. Mirrors the live zone; imported, not created.

locals {
  zone_id = "2c1a71a65eeb159469759acb680645d8" # ethbra.com
}

# Minecraft: players connect to play.ethbra.com -> TCPShield -> Velocity.
# DNS only (TCPShield is the proxy, not Cloudflare).
resource "cloudflare_dns_record" "play" {
  zone_id = local.zone_id
  name    = "play.ethbra.com"
  type    = "CNAME"
  content = "29a07eabe84abc255812d194f34d468d.ipv4.tcpshield.com"
  proxied = false
  ttl     = 1 # automatic
  comment = "TCPShield Minecraft Proxy"
}

import {
  to = cloudflare_dns_record.play
  id = "${local.zone_id}/6c4669a8c02f2308705de41a205cba7c"
}
