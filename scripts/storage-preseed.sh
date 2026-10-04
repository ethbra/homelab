#!/usr/bin/env bash
# Storage migration (see docs/current/RUNBOOK.md, "Storage and stacks cutover").
#
#   storage-preseed.sh            pre-seed: copy while everything runs
#   storage-preseed.sh --final    cutover: last pass with the containers stopped,
#                                 then record the old pool's file list
#   storage-preseed.sh --compare  after the new pool is mounted at /DATA:
#                                 compare its file list with the recorded one
#
# Pre-seed copies data to where the new storage layout wants it, while everything keeps
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
#
# --final differs from the pre-seed in two ways, both only safe once nothing
# writes to the data any more:
#   - app data is copied with --delete, so files the apps removed since the
#     pre-seed (SQLite -wal/-shm files, for one) don't linger in the new copy;
#   - the collision check is skipped: by now the copies on the hard drives are
#     ours, and any that differ are just older than the source.
# Branch data is never copied with --delete: the target directories on the
# hard drives also hold files that were there before.
set -euo pipefail

MODE=${1:-preseed}
case $MODE in
  preseed|--final|--compare) ;;
  *) echo "usage: $0 [--final|--compare]" >&2; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
for tool in rsync comm cmp; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool (apt install rsync)" >&2; exit 1; }
done

NVME_BRANCH=/var/lib/casaos/files
APPDATA_SRC=/DATA/AppData
APPDATA_DST=/srv/appdata
LOG=/var/log/homelab-preseed.log
LISTS=/var/log/homelab-cutover        # file lists of the old and new pool
STACK_CONTAINERS=(prowlarr overseerr sonarr radarr transmission plex crafty-container)

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

# Regular files in the pool, with sizes. AppData is left out: it moved to
# /srv/appdata, and what remains of it on the drives is not compared.
pool_list() {
  find /DATA -path /DATA/AppData -prune -o -type f -printf '%P\t%s\n' | LC_ALL=C sort
}

if [[ $MODE == --compare ]]; then
  [[ $(findmnt -no SOURCE /DATA) == mergerfs ]] || { echo "ABORT: /DATA is not the new pool" >&2; exit 1; }
  [[ -s $LISTS/old-pool.list ]] || { echo "ABORT: no $LISTS/old-pool.list (run --final first)" >&2; exit 1; }
  say "comparing the new pool with the old one"
  pool_list > "$LISTS/new-pool.list"
  LC_ALL=C comm -23 "$LISTS/old-pool.list" "$LISTS/new-pool.list" > "$LISTS/missing.list"
  LC_ALL=C comm -13 "$LISTS/old-pool.list" "$LISTS/new-pool.list" > "$LISTS/extra.list"
  echo "old pool: $(wc -l < "$LISTS/old-pool.list") files, new pool: $(wc -l < "$LISTS/new-pool.list") files"
  echo "missing or different size in the new pool: $(wc -l < "$LISTS/missing.list") (expected: 0)"
  head -20 "$LISTS/missing.list"
  echo "only in the new pool: $(wc -l < "$LISTS/extra.list") (files deleted from the NVMe after the pre-seed; review)"
  head -20 "$LISTS/extra.list"
  echo "full lists: $LISTS/"
  if [[ -s $LISTS/missing.list ]]; then
    say "compare FOUND MISSING FILES"; exit 1
  fi
  say "compare OK"
  exit 0
fi

APPDATA_DELETE=()
if [[ $MODE == --final ]]; then
  for c in "${STACK_CONTAINERS[@]}"; do
    if [[ $(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null) == true ]]; then
      echo "ABORT: container $c is still running" >&2; exit 1
    fi
  done
  if systemctl is-active --quiet casaos-app-management; then
    echo "ABORT: casaos-app-management is running (it can restart containers)" >&2; exit 1
  fi
  [[ $(findmnt -no SOURCE /DATA) == "$NVME_BRANCH":* ]] || { echo "ABORT: the old (CasaOS) pool is not mounted at /DATA" >&2; exit 1; }
  APPDATA_DELETE=(--delete)
fi

say "$MODE started"
df -h / /mnt/HDD_A /mnt/HDD_B

# 1. App data. Read through the pool so all three branches are merged.
#    No -X: mergerfs exposes virtual user.mergerfs.* xattrs that must not be copied.
say "1/2 app data: $APPDATA_SRC -> $APPDATA_DST"
install -d -m 0755 "$APPDATA_DST"
rsync -aH --acls --numeric-ids --info=stats1 "${APPDATA_DELETE[@]}" "${APPDATA_EXCLUDES[@]}" \
  "$APPDATA_SRC/" "$APPDATA_DST/"

# 2. NVMe branch -> hard drives, branch to branch (ext4 to ext4, so -X is fine).
for dir in "${!BRANCH_TARGET[@]}"; do
  src="$NVME_BRANCH/$dir"
  dst="${BRANCH_TARGET[$dir]}/$dir"
  [[ -d $src ]] || { say "skip $dir (not on the NVMe branch)"; continue; }

  # Never overwrite a different file that already lives at the same path.
  # (Pre-seed only; see the header for why --final skips it.)
  [[ $MODE == --final ]] || collisions=$(comm -12 \
    <(cd "$NVME_BRANCH" && find "$dir" -type f | sort) \
    <(cd "${BRANCH_TARGET[$dir]}" && find "$dir" -type f 2>/dev/null | sort) |
    while read -r f; do
      cmp -s "$NVME_BRANCH/$f" "${BRANCH_TARGET[$dir]}/$f" || echo "$f"
    done | wc -l)
  if [[ $MODE != --final ]] && (( collisions > 0 )); then
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

if [[ $MODE == --final ]]; then
  say "recording the old pool's file list"
  install -d -m 0700 "$LISTS"
  pool_list > "$LISTS/old-pool.list"
  echo "$(wc -l < "$LISTS/old-pool.list") files -> $LISTS/old-pool.list"
fi

df -h / /mnt/HDD_A /mnt/HDD_B
say "$MODE finished OK"
