#!/usr/bin/env bash
# Runs OpenTofu in tofu/ with its secrets from SOPS, in this process's
# environment only (never written to disk). Usage: scripts/tofu.sh plan
set -euo pipefail

cd "$(dirname "$0")/../tofu"
secrets=../secrets/cloudflare.yaml   # admin key only (see .sops.yaml)

CLOUDFLARE_API_TOKEN=$(sops -d --extract '["cloudflare_api_token"]' "$secrets")
TF_VAR_state_passphrase=$(sops -d --extract '["tofu_state_passphrase"]' "$secrets")
export CLOUDFLARE_API_TOKEN TF_VAR_state_passphrase

exec tofu "$@"
