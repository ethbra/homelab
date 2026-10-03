#!/usr/bin/env bash
# Storage migration, pre-seed pass (see docs/NEXT-STEPS.md).
#
# Copies data to where the new storage layout wants it, while everything keeps
# running. It is COPY-ONLY: nothing at the source is changed or deleted, no
# mount is touched, no service is stopped. Safe to re-run; each run copies only
# what changed. The cutover later repeats it with the containers stopped, then
# switches the mount.
#
#   1. App data      /DATA/AppData/<app>          -> /srv/appdata/<app>   (NVMe, outside FUSE)
#   2. NVMe branch   /var/lib/casaos/files/<dir>  -> /mnt/HDD_X/<dir>     (same relative path,
#                    so files keep their /DATA path once the pool is HDD-only)
#
# Run detached so it survives logging out:
#   sudo systemd-run --unit=homelab-preseed -p Nice=10 scripts/storage-preseed.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
for tool in rsync comm cmp; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool (apt install rsync)" >&2; exit 1; }
done

NVME_BRANCH=/var/lib/casaos/files
APPDATA_SRC=/DATA/AppData
APPDATA_DST=/srv/appdata
LOG=/var/log/homelab-preseed.log

# Which hard drive each NVMe-branch directory goes to (both have ~830 GB free).
declare -A BRANCH_TARGET=(
  [Downloads]=/mnt/HDD_A
  [Media]=/mnt/HDD_B
  [Documents]=/mnt/HDD_A
  [Gallery]=/mnt/HDD_A
)

# App data that is NOT moving: Crafty's backups stay on HDD_A (bind-mounted from
# there directly), ollama/open-webui are retired, config/ is a leftover.
APPDATA_EXCLUDES=(
  --exclude=/crafty/backups/
  --exclude=/ollama-nvidia/
  --exclude=/open-webui-ollama/
  --exclude=/config/
)

exec > >(tee -a "$LOG") 2>&1
say() { printf '\n[%(%F %T)T] %s\n' -1 "$*"; }

say "pre-seed started"
df -h / /mnt/HDD_A /mnt/HDD_B

# 1. App data. Read through the pool so all three branches are merged.
#    No -X: mergerfs exposes virtual user.mergerfs.* xattrs that must not be copied.
say "1/2 app data: $APPDATA_SRC -> $APPDATA_DST"
install -d -m 0755 "$APPDATA_DST"
rsync -aH --acls --numeric-ids --info=stats1 "${APPDATA_EXCLUDES[@]}" \
  "$APPDATA_SRC/" "$APPDATA_DST/"

# 2. NVMe branch -> hard drives, branch to branch (ext4 to ext4, so -X is fine).
for dir in "${!BRANCH_TARGET[@]}"; do
  src="$NVME_BRANCH/$dir"
  dst="${BRANCH_TARGET[$dir]}/$dir"
  [[ -d $src ]] || { say "skip $dir (not on the NVMe branch)"; continue; }

  # Never overwrite a different file that already lives at the same path.
  collisions=$(comm -12 \
    <(cd "$NVME_BRANCH" && find "$dir" -type f | sort) \
    <(cd "${BRANCH_TARGET[$dir]}" && find "$dir" -type f 2>/dev/null | sort) |
    while read -r f; do
      cmp -s "$NVME_BRANCH/$f" "${BRANCH_TARGET[$dir]}/$f" || echo "$f"
    done | wc -l)
  if (( collisions > 0 )); then
    say "ABORT: $collisions file(s) under $dir exist on ${BRANCH_TARGET[$dir]} with different content"
    exit 1
  fi

  say "2/2 $src -> $dst"
  install -d -m 0777 "$dst"
  rsync -aHAX --numeric-ids --info=stats1 "$src/" "$dst/"
done

# Report what still differs (normally only files the running apps wrote meanwhile).
say "verification (dry run; lists files that differ right now)"
appdata_diff=$(rsync -aH --numeric-ids --dry-run --itemize-changes "${APPDATA_EXCLUDES[@]}" \
  "$APPDATA_SRC/" "$APPDATA_DST/" | grep -c '^[<>]' || true)
echo "app data: $appdata_diff file(s) changed since the copy (expected: a few, from running apps)"
for dir in "${!BRANCH_TARGET[@]}"; do
  [[ -d $NVME_BRANCH/$dir ]] || continue
  n=$(rsync -aHAX --numeric-ids --dry-run --itemize-changes \
    "$NVME_BRANCH/$dir/" "${BRANCH_TARGET[$dir]}/$dir/" | grep -c '^[<>]' || true)
  echo "$dir: $n file(s) differ"
done

df -h / /mnt/HDD_A /mnt/HDD_B
say "pre-seed finished OK"
