# DNS for ethbra.com. Mirrors the live zone; imported, not created.

locals {
  zone_id = "2c1a71a65eeb159469759acb680645d8" # ethbra.com
}

# play.ethbra.com in a browser: the public BlueMap (tunnel -> nginx -> BlueMap).
# Players also type play.ethbra.com; their clients follow the SRV record below
# to mc.ethbra.com (TCPShield) and never use this CNAME.
# Rollback: content = the TCPShield target, proxied = false.
resource "cloudflare_dns_record" "play" {
  zone_id = local.zone_id
  name    = "play.ethbra.com"
  type    = "CNAME"
  content = "${local.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic
  comment = "Tunnel Host -> nginx -> BlueMap; public (Access bypass)"

  depends_on = [cloudflare_zero_trust_access_application.map]
}

import {
  to = cloudflare_dns_record.play
  id = "${local.zone_id}/6c4669a8c02f2308705de41a205cba7c"
}

# Tunnel hostnames (-> nginx). Proxied, so Access is in front. Created only
# after Access is, so a name never resolves without a login in front of it.
resource "cloudflare_dns_record" "tunnel" {
  for_each = toset(["dash", "crafty"])

  zone_id = local.zone_id
  name    = "${each.key}.ethbra.com"
  type    = "CNAME"
  content = "${local.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic
  comment = "Tunnel Host -> nginx; behind Access"

  depends_on = [
    cloudflare_zero_trust_access_application.homelab,
    cloudflare_zero_trust_access_application.wildcard,
  ]
}

# Minecraft via SRV (docs/design/WEB-ENTRY.md), so play.ethbra.com can later
# serve the map over HTTPS while players keep typing play.ethbra.com.
# Clients send the SRV target (mc.ethbra.com) as the handshake hostname, so mc
# must be in TCPShield's domain list *and verified* there (done 2026-10-15).
resource "cloudflare_dns_record" "mc" {
  zone_id = local.zone_id
  name    = "mc.ethbra.com"
  type    = "CNAME"
  content = "29a07eabe84abc255812d194f34d468d.ipv4.tcpshield.com"
  proxied = false
  ttl     = 1 # automatic
  comment = "TCPShield Minecraft Proxy (SRV target for play)"
}

# The target is the helper name, never the TCPShield CNAME itself ("Invalid
# host"); the port is 25565 because TCPShield maps the backend port itself.
resource "cloudflare_dns_record" "play_srv" {
  zone_id = local.zone_id
  name    = "_minecraft._tcp.play.ethbra.com"
  type    = "SRV"
  ttl     = 300
  comment = "Minecraft: play.ethbra.com -> mc.ethbra.com (TCPShield)"
  # The API echoes priority at the top level too; without it every plan
  # shows "priority = 0 -> null".
  priority = 0
  data = {
    priority = 0
    weight   = 5
    port     = 25565
    target   = "mc.ethbra.com"
  }
}
