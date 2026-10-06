# Cloudflare DNS and tunnel ingress (IAC-DESIGN phase 4). Applied by hand by
# the owner with scripts/tofu.sh, never by the pull agent.
#
# State is committed to the repo, encrypted (OpenTofu state encryption,
# passphrase in secrets/cloudflare.yaml, admin key only). `enforced` makes tofu refuse to
# write an unencrypted state or plan.
terraform {
  required_version = "~> 1.13"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.27"
    }
  }

  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

variable "state_passphrase" {
  description = "From secrets/cloudflare.yaml, set by scripts/tofu.sh"
  type        = string
  sensitive   = true
}

# The API token comes from CLOUDFLARE_API_TOKEN (scripts/tofu.sh, SOPS).
provider "cloudflare" {}
