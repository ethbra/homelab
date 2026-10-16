# Cloudflare Access in front of the tunnel's hostnames
# (docs/design/WEB-ENTRY.md). Login is Google only; the policy allows only
# the owner. Team domain: ethbra.cloudflareaccess.com.

variable "google_oauth_client_id" {
  description = "From secrets/cloudflare.yaml, set by scripts/tofu.sh"
  type        = string
}

variable "google_oauth_client_secret" {
  description = "From secrets/cloudflare.yaml, set by scripts/tofu.sh"
  type        = string
  sensitive   = true
}

# Kept out of the (public) repo; sensitive so plans don't print it.
variable "access_owner_email" {
  description = "From secrets/cloudflare.yaml, set by scripts/tofu.sh"
  type        = string
  sensitive   = true
}

# Google enforces the account's 2-Step Verification (Google prompts, passkey).
resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = local.account_id
  name       = "Google"
  type       = "google"
  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

resource "cloudflare_zero_trust_access_policy" "owner" {
  account_id = local.account_id
  name       = "Owner only"
  decision   = "allow"
  include = [{
    email = { email = var.access_owner_email }
  }]
}

# dash + crafty: one application, so one sign-in covers both.
resource "cloudflare_zero_trust_access_application" "homelab" {
  account_id = local.account_id
  name       = "homelab"
  type       = "self_hosted"
  destinations = [
    { type = "public", uri = "dash.ethbra.com" },
    { type = "public", uri = "crafty.ethbra.com" },
  ]
  # Google only: One-time PIN is not offered, so there is no weaker way in.
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.google.id]
  auto_redirect_to_identity = true
  session_duration          = "24h"
  policies = [{
    id         = cloudflare_zero_trust_access_policy.owner.id
    precedence = 1
  }]
}

# Safety net: any other proxied name is owner-only until it gets its own
# application. More specific applications take precedence over it.
resource "cloudflare_zero_trust_access_application" "wildcard" {
  account_id = local.account_id
  name       = "ethbra.com catch-all"
  type       = "self_hosted"
  destinations = [
    { type = "public", uri = "*.ethbra.com" },
  ]
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.google.id]
  auto_redirect_to_identity = true
  session_duration          = "24h"
  policies = [{
    id         = cloudflare_zero_trust_access_policy.owner.id
    precedence = 1
  }]
}

# The map is public: anyone, no login. More specific than the *.ethbra.com
# catch-all, so it wins for play.ethbra.com.
resource "cloudflare_zero_trust_access_policy" "public" {
  account_id = local.account_id
  name       = "Public"
  decision   = "bypass"
  include = [{
    everyone = {}
  }]
}

resource "cloudflare_zero_trust_access_application" "map" {
  account_id = local.account_id
  name       = "map (BlueMap)"
  type       = "self_hosted"
  destinations = [
    { type = "public", uri = "play.ethbra.com" },
  ]
  app_launcher_visible = false
  policies = [{
    id         = cloudflare_zero_trust_access_policy.public.id
    precedence = 1
  }]
}
