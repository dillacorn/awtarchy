#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

LOG_PREFIX="[awtarchy-backup-clean]"
log()  { printf '%s %s\n'  "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

usage() {
  cat <<'EOF'
Usage:
  awtarchy-backup-clean.sh [options]

Default behavior:
  1) Scan common Awtarchy-managed locations for:
       - *.backup
       - *.backup.YYYYMMDD-HHMMSS
  2) Print the full list and a summary
  3) Prompt: delete them now? [y/N]
     - "y" deletes
     - anything else exits without deleting

Options:
  --dry-run              List only; do not prompt, do not delete
  --yes                  Delete without prompt (still prints list first)
  --older-than <days>    Only match files with mtime strictly greater than <days> (integer)
  --archive <tar.gz>     Create a tar.gz archive (relative to $HOME) of matches before deletion
  --help                 Show help

Notes:
  - This only scans within $HOME in locations your update-reset-backup script writes to.
  - If your backups live elsewhere, add those paths into the ROOTS array below.
EOF
}

DRY_RUN=0
YES=0
OLDER_THAN=""
ARCHIVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    --older-than)
      OLDER_THAN="${2:-}"
      [[ "$OLDER_THAN" =~ ^[0-9]+$ ]] || die "--older-than expects an integer days value"
      shift 2
      ;;
    --archive)
      ARCHIVE="${2:-}"
      [[ -n "$ARCHIVE" ]] || die "Missing value for --archive"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown arg: $1 (use --help)" ;;
  esac
done

need_cmd find
need_cmd stat
need_cmd rm
if [[ -n "$ARCHIVE" ]]; then
  need_cmd tar
fi

HOME_DIR="${HOME}"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "\$HOME is not set to a valid directory"

# Match Awtarchy update-reset-backup backup naming:
#   dest.backup
#   dest.backup.YYYYMMDD-HHMMSS
regex_stamp='.*\.backup\.[0-9]{8}-[0-9]{6}$'

# Default roots based on update-reset-backup.sh deploy targets (all under $HOME):
ROOTS=(
  "${HOME_DIR}"
  "${HOME_DIR}/.config"
  "${HOME_DIR}/.local/share"
  "${HOME_DIR}/Pictures"
)

# Build find list of existing roots; limit $HOME itself to maxdepth 1 to catch ~/.bashrc.backup* safely.
existing_roots=()
for r in "${ROOTS[@]}"; do
  [[ -e "$r" ]] || continue
  existing_roots+=("$r")
done

(( ${#existing_roots[@]} > 0 )) || die "No scan roots exist under $HOME"

tmp_list="$(mktemp)"
trap 'rm -f -- "$tmp_list" 2>/dev/null || true' EXIT
: >"$tmp_list"

mtime_args=()
if [[ -n "$OLDER_THAN" ]]; then
  mtime_args+=(-mtime "+${OLDER_THAN}")
fi

# 1) $HOME maxdepth 1
if [[ -d "${HOME_DIR}" ]]; then
  find "${HOME_DIR}" -maxdepth 1 -type f "${mtime_args[@]}" \
    \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
    -print0 >>"$tmp_list" 2>/dev/null || true
fi

# 2) Other roots recursive (skip $HOME itself to avoid duplicates)
for r in "${existing_roots[@]}"; do
  [[ "$r" == "$HOME_DIR" ]] && continue
  find "$r" -type f "${mtime_args[@]}" \
    \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
    -print0 >>"$tmp_list" 2>/dev/null || true
done

found=0
bytes=0

if [[ -s "$tmp_list" ]]; then
  while IFS= read -r -d '' f; do
    ((found++)) || true
    sz="$(stat -c '%s' -- "$f" 2>/dev/null || printf '0')"
    [[ "$sz" =~ ^[0-9]+$ ]] && bytes=$((bytes + sz))
  done <"$tmp_list"
fi

if (( found == 0 )); then
  log "No .backup files found in Awtarchy-managed paths."
  exit 0
fi

log "Matches: ${found}"
log "Total size: ${bytes} bytes"
log "Files:"
while IFS= read -r -d '' f; do
  printf '  %s\n' "$f"
done <"$tmp_list"

if (( DRY_RUN == 1 )); then
  log "Dry-run: no prompt, no deletes."
  exit 0
fi

do_delete=0

if (( YES == 1 )); then
  do_delete=1
else
  if [[ -t 0 ]]; then
    printf '%s Delete these %d files now? [y/N]: ' "$LOG_PREFIX" "$found"
    read -r ans || ans=""
    [[ "$ans" == "y" || "$ans" == "Y" ]] && do_delete=1
  else
    warn "Non-interactive stdin and --yes not provided. Exiting without deleting."
    exit 0
  fi
fi

if (( do_delete == 0 )); then
  log "No changes made."
  exit 0
fi

if [[ -n "$ARCHIVE" ]]; then
  # Archive paths relative to $HOME to avoid absolute-path extraction surprises.
  # Only archive files under $HOME.
  rel_tmp="$(mktemp)"
  trap 'rm -f -- "$tmp_list" "$rel_tmp" 2>/dev/null || true' EXIT
  : >"$rel_tmp"

  while IFS= read -r -d '' f; do
    case "$f" in
      "$HOME_DIR"/*) printf '%s\0' "${f#"$HOME_DIR"/}" >>"$rel_tmp" ;;
      *) warn "Skipping (not under \$HOME, will not archive): $f" ;;
    esac
  done <"$tmp_list"

  mkdir -p -- "$(dirname -- "$ARCHIVE")"
  log "Creating archive: $ARCHIVE"
  tar -C "$HOME_DIR" --null -T "$rel_tmp" -czf "$ARCHIVE"
fi

deleted=0
failed=0
while IFS= read -r -d '' f; do
  if rm -f -- "$f" 2>/dev/null; then
    ((deleted++)) || true
  else
    ((failed++)) || true
    warn "Failed to delete: $f"
  fi
done <"$tmp_list"

log "Deleted: ${deleted}"
if (( failed > 0 )); then
  warn "Failed: ${failed}"
  exit 2
fi

log "Done."
