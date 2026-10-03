#!/usr/bin/env bash
# Fail if any file under secrets/ is not SOPS-encrypted.
# Usage: check-sops-encrypted.sh [file...]   (no args: check all of secrets/)
set -euo pipefail

if [[ $# -eq 0 ]]; then
  mapfile -t files < <(find secrets -type f ! -name README.md 2>/dev/null)
else
  files=("$@")
fi

status=0
for f in "${files[@]}"; do
  [[ "$(basename "$f")" == README.md ]] && continue
  # SOPS writes its metadata as a top-level "sops" key (YAML/JSON) or sops_* lines (dotenv).
  if ! grep -Eq '^sops:|"sops": *\{|^sops_mac=' "$f"; then
    echo "NOT ENCRYPTED: $f (encrypt it with: sops -e -i $f)" >&2
    status=1
  fi
done
exit "$status"
