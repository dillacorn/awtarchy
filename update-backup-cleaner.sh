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

Interactive default (TTY):
  - Scans common awtarchy-managed paths under $HOME for:
      *.backup
      *.backup.YYYYMMDD-HHMMSS
  - Shows a paged list (default 20 items/page)
  - Press a number to toggle KEEP immediately (no Enter)
  - Press [D] to delete everything NOT marked KEEP

Options:
  --dry-run              Print full list and exit (no menu, no deletes)
  --yes                  Delete ALL matches without prompts (ignores KEEP UI)
  --older-than <days>    Only match files with mtime strictly greater than <days> (integer)
  --archive <tar.gz>     Create a tar.gz archive (relative to $HOME if not absolute)
  --help                 Show help

Paging config:
  - Default page size: 20
  - Change via:
      AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT=40 ./awtarchy-backup-clean.sh
    or press [G] in the menu (saved in ~/.config/awtarchy/backup_clean_page_size)

Notes:
  - Non-interactive stdin (pipes/CI) will not delete unless --yes.
EOF
}

# --- args ---
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

HOME_DIR="${HOME:-}"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "\$HOME is not set to a valid directory"

# If archive is not absolute, treat it as under $HOME.
if [[ -n "$ARCHIVE" && "$ARCHIVE" != /* ]]; then
  ARCHIVE="${HOME_DIR}/${ARCHIVE}"
fi

# Match:
#   dest.backup
#   dest.backup.YYYYMMDD-HHMMSS
regex_stamp='.*\.backup\.[0-9]{8}-[0-9]{6}$'

# Default roots (all under $HOME):
ROOTS=(
  "${HOME_DIR}"
  "${HOME_DIR}/.config"
  "${HOME_DIR}/.local/share"
  "${HOME_DIR}/Pictures"
)

mtime_args=()
if [[ -n "$OLDER_THAN" ]]; then
  mtime_args+=(-mtime "+${OLDER_THAN}")
fi

collect_backups() {
  local r
  local -a roots=()
  for r in "${ROOTS[@]}"; do
    [[ -e "$r" ]] || continue
    roots+=("$r")
  done
  (( ${#roots[@]} > 0 )) || return 0

  find "$HOME_DIR" -maxdepth 1 -type f "${mtime_args[@]}" \
    \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
    -print 2>/dev/null || true

  for r in "${roots[@]}"; do
    [[ "$r" == "$HOME_DIR" ]] && continue
    find "$r" -type f "${mtime_args[@]}" \
      \( -name '*.backup' -o -regextype posix-extended -regex "$regex_stamp" \) \
      -print 2>/dev/null || true
  done
}

dedupe_and_sort() {
  declare -A seen=()
  local line
  local -a out=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ -z "${seen[$line]:-}" ]]; then
      seen["$line"]=1
      out+=("$line")
    fi
  done
  (( ${#out[@]} == 0 )) && return 0
  printf '%s\n' "${out[@]}" | LC_ALL=C sort
}

bytes_total_for_list() {
  local -a arr=("$@")
  local f sz
  local total=0
  for f in "${arr[@]}"; do
    sz="$(stat -c '%s' -- "$f" 2>/dev/null || printf '0')"
    [[ "$sz" =~ ^[0-9]+$ ]] && total=$((total + sz))
  done
  printf '%s\n' "$total"
}

print_full_list() {
  local -a arr=("$@")
  local bytes
  bytes="$(bytes_total_for_list "${arr[@]}")"
  log "Matches: ${#arr[@]}"
  log "Total size: ${bytes} bytes"
  log "Files:"
  local i
  for i in "${!arr[@]}"; do
    printf '  [%d] %s\n' "$((i+1))" "${arr[$i]}"
  done
}

make_archive_for_delete_list() {
  local archive_path="$1"
  shift
  local -a del_list=("$@")

  [[ -n "$archive_path" ]] || return 0
  (( ${#del_list[@]} > 0 )) || return 0

  local rel_tmp
  rel_tmp="$(mktemp)"
  : >"$rel_tmp"

  local f rel
  for f in "${del_list[@]}"; do
    case "$f" in
      "$HOME_DIR"/*)
        rel="${f#"$HOME_DIR"/}"
        printf '%s\0' "$rel" >>"$rel_tmp"
        ;;
      *)
        warn "Skipping (not under \$HOME, will not archive): $f"
        ;;
    esac
  done

  mkdir -p -- "$(dirname -- "$archive_path")"
  log "Creating archive: $archive_path"
  tar -C "$HOME_DIR" --null -T "$rel_tmp" -czf "$archive_path"
  rm -f -- "$rel_tmp" 2>/dev/null || true
}

delete_files_verified() {
  local -a del_list=("$@")
  local removed=0 failed=0 skipped=0 f existed=0
  for f in "${del_list[@]}"; do
    existed=0
    [[ -e "$f" ]] && existed=1
    rm -f -- "$f" 2>/dev/null || true

    if (( existed == 0 )); then
      ((skipped++)) || true
      continue
    fi

    if [[ ! -e "$f" ]]; then
      ((removed++)) || true
    else
      ((failed++)) || true
      warn "Failed to delete (still exists): $f"
    fi
  done

  log "Removed: ${removed}"
  (( skipped > 0 )) && log "Skipped (already gone): ${skipped}"
  if (( failed > 0 )); then
    warn "Failed: ${failed}"
    return 2
  fi
  return 0
}

clear_screen() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[H\033[2J'
  fi
}

# --- gather files ---
mapfile -t ALL_FILES < <(collect_backups | dedupe_and_sort)

if (( ${#ALL_FILES[@]} == 0 )); then
  log "No .backup files found in awtarchy-managed paths."
  exit 0
fi

if [[ ! -t 0 ]] && (( DRY_RUN == 0 && YES == 0 )); then
  warn "Non-interactive stdin. Showing list only. Use --yes to delete."
  print_full_list "${ALL_FILES[@]}"
  exit 0
fi

if (( DRY_RUN == 1 )); then
  print_full_list "${ALL_FILES[@]}"
  exit 0
fi

if (( YES == 1 )); then
  [[ -n "$ARCHIVE" ]] && make_archive_for_delete_list "$ARCHIVE" "${ALL_FILES[@]}"
  delete_files_verified "${ALL_FILES[@]}"
  exit $?
fi

# --- interactive paged UI ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/awtarchy"
PAGE_SIZE_DEFAULT="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_DEFAULT:-20}"
PAGE_SIZE_MAX="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_MAX:-200}"
PAGE_SIZE_FILE="${AWTARCHY_BACKUP_CLEAN_PAGE_SIZE_FILE:-$CONFIG_DIR/backup_clean_page_size}"

get_page_size() {
  local def="$PAGE_SIZE_DEFAULT"
  local max="$PAGE_SIZE_MAX"
  local v=""
  if [[ -r "$PAGE_SIZE_FILE" ]]; then
    v="$(head -n1 "$PAGE_SIZE_FILE" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 5 && v <= max )); then
    printf '%s\n' "$v"
    return 0
  fi
  if [[ "$def" =~ ^[0-9]+$ ]] && (( def >= 5 && def <= max )); then
    printf '%s\n' "$def"
  else
    printf '%s\n' "20"
  fi
}

save_page_size() {
  local n="${1:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  (( n >= 5 && n <= PAGE_SIZE_MAX )) || return 1
  mkdir -p "$CONFIG_DIR"
  printf '%s\n' "$n" >"$PAGE_SIZE_FILE"
}

declare -A KEEP=()
FILTER=""
page_size="$(get_page_size)"
page=0

build_view() {
  local f q
  if [[ -z "$FILTER" ]]; then
    printf '%s\n' "${ALL_FILES[@]}"
    return 0
  fi
  q="${FILTER,,}"
  for f in "${ALL_FILES[@]}"; do
    [[ "${f,,}" == *"$q"* ]] && printf '%s\n' "$f"
  done
}

prompt_set_page_size() {
  local cur="$1"
  local input
  while :; do
    printf '%s Page size [%s] (5-%s, q=cancel): ' "$LOG_PREFIX" "$cur" "$PAGE_SIZE_MAX"
    read -r input || exit 1
    [[ "${input,,}" == "q" ]] && return 0
    [[ -z "$input" ]] && return 0
    if ! save_page_size "$input"; then
      printf '%s Invalid page size.\n' "$LOG_PREFIX"
      continue
    fi
    page_size="$input"
    printf '%s Saved page size: %s\n' "$LOG_PREFIX" "$page_size"
    return 0
  done
}

prompt_find() {
  local input
  printf '%s Find (substring, empty clears): ' "$LOG_PREFIX"
  read -r input || exit 1
  FILTER="$input"
  page=0
}

toggle_keep_by_local_index() {
  local local_sel="$1"
  local start="$2"
  shift 2
  local -a view=("$@")
  local idx=$(( start + local_sel - 1 ))
  (( idx < 0 || idx >= ${#view[@]} )) && return 1
  local f="${view[$idx]}"
  if [[ -n "${KEEP[$f]:-}" ]]; then
    unset 'KEEP[$f]'
  else
    KEEP["$f"]=1
  fi
}

confirm_delete() {
  local del_count="$1"
  local keep_count="$2"
  local ans
  printf '%s Delete %s files (keeping %s)? [y/N]: ' "$LOG_PREFIX" "$del_count" "$keep_count"
  read -r ans || exit 1
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

PENDING_KEY=""

read_key() {
  local ch=""
  if [[ -n "$PENDING_KEY" ]]; then
    ch="$PENDING_KEY"
    PENDING_KEY=""
    printf '%s' "$ch"
    return 0
  fi
  IFS= read -rsn1 ch || exit 1
  printf '%s' "$ch"
}

read_number_no_enter() {
  local sel="$1"
  local max="$2"
  local next=""
  local prefix

  prefix="$sel"
  if (( prefix * 10 > max )); then
    printf '%s' "$sel"
    return 0
  fi

  if IFS= read -rsn1 -t 0.12 next; then
    if [[ "$next" =~ ^[0-9]$ ]]; then
      sel+="$next"
      prefix="$sel"
      if (( prefix * 10 <= max )); then
        next=""
        if IFS= read -rsn1 -t 0.12 next; then
          if [[ "$next" =~ ^[0-9]$ ]]; then
            sel+="$next"
          else
            PENDING_KEY="$next"
          fi
        fi
      fi
    else
      PENDING_KEY="$next"
    fi
  fi

  printf '%s' "$sel"
}

quit_clean() {
  clear_screen
  exit 0
}

while :; do
  mapfile -t VIEW_FILES < <(build_view)

  total="${#VIEW_FILES[@]}"
  pages=$(( (total + page_size - 1) / page_size ))
  (( pages < 1 )) && pages=1
  (( page < 0 )) && page=0
  if (( page >= pages )); then
    page=$(( pages - 1 ))
  fi

  start=$(( page * page_size ))
  end=$(( start + page_size ))
  (( end > total )) && end=$total
  on_page=$(( end - start ))

  clear_screen
  printf '%s Backup files\n' "$LOG_PREFIX"

  if (( total == 0 )); then
    echo "No matches."
    echo
  else
    printf 'Page %d/%d, %d-%d of %d, size %d\n\n' \
      "$((page + 1))" "$pages" "$((start + 1))" "$end" "$total" "$page_size"

    i="$start"
    local_i=1
    while (( i < end )); do
      f="${VIEW_FILES[$i]}"
      if [[ -n "${KEEP[$f]:-}" ]]; then
        mark="[KEEP]"
      else
        mark="[    ]"
      fi
      printf '  [%d] %s %s\n' "$local_i" "$mark" "$f"
      ((i++)) || true
      ((local_i++)) || true
    done
    echo
  fi

  echo "  [N]Next [P]Prev [G]Page [F]Find"
  echo "  [D]Delete [Q]Quit"
  echo

  if (( on_page > 0 )); then
    printf 'Select 1-%d or key: ' "$on_page"
  else
    printf 'Key: '
  fi

  ch="$(read_key)"

  case "$ch" in
    $'\r'|$'\n') ;;
    [qQ]) quit_clean ;;
    [nN])
      if (( page + 1 < pages )); then
        page=$((page + 1))
      fi
      ;;
    [pP])
      if (( page > 0 )); then
        page=$((page - 1))
      fi
      ;;
    [gG])
      echo
      prompt_set_page_size "$page_size"
      page=0
      ;;
    [fF])
      echo
      prompt_find
      ;;
    [dD])
      DEL_LIST=()
      keep_count=0

      for f in "${ALL_FILES[@]}"; do
        if [[ -n "${KEEP[$f]:-}" ]]; then
          ((keep_count++)) || true
        else
          DEL_LIST+=("$f")
        fi
      done

      del_count="${#DEL_LIST[@]}"

      echo
      if (( del_count == 0 )); then
        log "Nothing to delete (everything is KEEP)."
        printf '%s Press any key...' "$LOG_PREFIX"
        IFS= read -rsn1 _ || true
        continue
      fi

      if ! confirm_delete "$del_count" "$keep_count"; then
        continue
      fi

      [[ -n "$ARCHIVE" ]] && make_archive_for_delete_list "$ARCHIVE" "${DEL_LIST[@]}"

      delete_files_verified "${DEL_LIST[@]}"
      exit $?
      ;;
    [0-9])
      if (( on_page == 0 )); then
        continue
      fi
      [[ "$ch" == "0" ]] && continue

      sel="$(read_number_no_enter "$ch" "$on_page")"
      [[ "$sel" =~ ^[0-9]+$ ]] || continue
      if (( sel < 1 || sel > on_page )); then
        continue
      fi
      toggle_keep_by_local_index "$sel" "$start" "${VIEW_FILES[@]}" || true
      ;;
    *) ;;
  esac
done
