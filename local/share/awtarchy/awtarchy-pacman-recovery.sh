#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Guarded recovery for invalid signed pacman repository databases.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

TEST_MODE="${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0}"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ $TEST_MODE == 1 ]]; then
  (( EUID != 0 )) || die "Pacman recovery test mode must not run as root."
  PACMAN_BIN="${AWTARCHY_PACMAN_BIN:?test mode requires AWTARCHY_PACMAN_BIN}"
  PACMAN_CONF="${AWTARCHY_PACMAN_CONF:?test mode requires AWTARCHY_PACMAN_CONF}"
  SYNC_DIR="${AWTARCHY_PACMAN_SYNC_DIR:?test mode requires AWTARCHY_PACMAN_SYNC_DIR}"
  CACHY_RATE_BIN="${AWTARCHY_CACHY_RATE_BIN:-/nonexistent/cachyos-rate-mirrors}"
  REFLECTOR_BIN="${AWTARCHY_REFLECTOR_BIN:-/nonexistent/reflector}"
  SKIP_MIRROR_REFRESH="${AWTARCHY_SKIP_MIRROR_REFRESH:-0}"
else
  PACMAN_BIN=/usr/bin/pacman
  PACMAN_CONF=/etc/pacman.conf
  SYNC_DIR=/var/lib/pacman/sync
  CACHY_RATE_BIN=/usr/bin/cachyos-rate-mirrors
  REFLECTOR_BIN=/usr/bin/reflector
  SKIP_MIRROR_REFRESH=0
fi

[[ -x $PACMAN_BIN ]] || die "pacman is unavailable: ${PACMAN_BIN}"
[[ -r $PACMAN_CONF ]] || die "pacman configuration is unavailable: ${PACMAN_CONF}"

as_root() {
  if [[ $TEST_MODE == 1 || $EUID -eq 0 ]]; then
    "$@"
  else
    /usr/bin/sudo -- "$@"
  fi
}

run_capture_stderr() {
  local root_mode="$1" error_file="$2"
  shift 2
  local rc=0

  : >"$error_file"
  if [[ $root_mode == root ]]; then
    if as_root "$PACMAN_BIN" "$@" 2>"$error_file"; then
      rc=0
    else
      rc=$?
    fi
  else
    if "$PACMAN_BIN" "$@" 2>"$error_file"; then
      rc=0
    else
      rc=$?
    fi
  fi

  if [[ -s $error_file ]]; then
    cat -- "$error_file" >&2
  fi
  return "$rc"
}

parse_sync_database_repos() {
  local error_file="$1" line repo=""
  local saw_sync_failure=0
  local -a repos=()

  grep -Fq 'failed to synchronize all databases' "$error_file" \
    && saw_sync_failure=1

  while IFS= read -r line; do
    if [[ $line =~ ^error:\ database\ \'([A-Za-z0-9@._+:-]+)\'\ is\ not\ valid\ \(invalid\ or\ corrupted\ database\ \(PGP\ signature\)\)$ ]]; then
      repos+=("${BASH_REMATCH[1]}")
      continue
    fi
    if (( saw_sync_failure == 1 )) \
      && [[ $line =~ ^error:\ ([A-Za-z0-9@._+:-]+):\ signature\ from\ .+\ is\ invalid$ ]]; then
      repos+=("${BASH_REMATCH[1]}")
    fi
  done <"$error_file"

  (( ${#repos[@]} > 0 )) || return 1
  printf '%s\n' "${repos[@]}" | LC_ALL=C sort -u
}

repo_is_cachyos() {
  [[ $1 == cachyos || $1 == cachyos-* ]]
}

repo_is_arch_official() {
  [[ $1 =~ ^(core|extra|multilib)(-testing|-staging)?$ ]]
}

repo_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

write_config_without_repos() {
  local destination="$1"
  shift
  local -a blocked=("$@")
  local line section="" skip=0

  : >"$destination"
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^\[([A-Za-z0-9@._+:-]+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"
      if repo_in_list "$section" "${blocked[@]}"; then
        skip=1
      else
        skip=0
      fi
    fi
    (( skip == 1 )) || printf '%s\n' "$line" >>"$destination"
  done <"$PACMAN_CONF"
}

bootstrap_mirror_tool() {
  local kind="$1"
  shift
  local -a repos=("$@")
  local tmp_conf package_label

  tmp_conf="$(mktemp)"
  write_config_without_repos "$tmp_conf" "${repos[@]}"

  case "$kind" in
    cachyos)
      package_label='rate-mirrors cachyos-rate-mirrors'
      log "CachyOS mirror tool is missing; bootstrapping ${package_label} without the broken repository."
      if ! as_root "$PACMAN_BIN" --config "$tmp_conf" -S --needed --noconfirm \
        rate-mirrors cachyos-rate-mirrors; then
        rm -f -- "$tmp_conf"
        warn "Could not bootstrap cachyos-rate-mirrors; continuing with targeted database resync only."
        return 1
      fi
      ;;
    arch)
      package_label='reflector'
      log "Arch mirror tool is missing; bootstrapping ${package_label} without the broken repository."
      if ! as_root "$PACMAN_BIN" --config "$tmp_conf" -S --needed --noconfirm reflector; then
        rm -f -- "$tmp_conf"
        warn "Could not bootstrap reflector; continuing with targeted database resync only."
        return 1
      fi
      ;;
    *)
      rm -f -- "$tmp_conf"
      return 1
      ;;
  esac

  rm -f -- "$tmp_conf"
  return 0
}

refresh_supported_mirrors() {
  local -a repos=("$@")
  local repo need_cachy=0 need_arch=0

  [[ $SKIP_MIRROR_REFRESH == 1 ]] && return 0

  for repo in "${repos[@]}"; do
    repo_is_cachyos "$repo" && need_cachy=1
    repo_is_arch_official "$repo" && need_arch=1
  done

  if (( need_cachy == 1 )); then
    if [[ ! -x $CACHY_RATE_BIN ]]; then
      bootstrap_mirror_tool cachyos "${repos[@]}" || true
    fi
    if [[ -x $CACHY_RATE_BIN ]]; then
      log "Refreshing CachyOS mirrors before retrying pacman..."
      if ! as_root "$CACHY_RATE_BIN"; then
        warn "CachyOS mirror refresh failed; continuing with targeted database resync only."
      fi
    fi
  fi

  if (( need_arch == 1 )); then
    if [[ ! -x $REFLECTOR_BIN ]]; then
      bootstrap_mirror_tool arch "${repos[@]}" || true
    fi
    if [[ -x $REFLECTOR_BIN ]]; then
      log "Refreshing standard Arch mirrors before retrying pacman..."
      if ! as_root "$REFLECTOR_BIN" --verbose --latest 5 --sort rate \
        --save /etc/pacman.d/mirrorlist; then
        warn "Arch mirror refresh failed; continuing with targeted database resync only."
      fi
    fi
  fi
}

confirm_repair() {
  local answer=""
  local -a repos=("$@")

  if [[ $TEST_MODE == 1 ]]; then
    case "${AWTARCHY_ASSUME_PACMAN_REPAIR:-no}" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    warn "Pacman has an invalid signed repository database, but no interactive terminal is available for repair approval."
    return 1
  fi

  printf '\nAwtarchy detected an invalid signed pacman repository database:\n' >/dev/tty
  printf '  - %s\n' "${repos[@]}" >/dev/tty
  printf '\nAwtarchy can refresh supported mirrors, remove only the affected cached\n' >/dev/tty
  printf 'repository database/signature files, force a fresh sync, and retry once.\n' >/dev/tty
  printf 'It will not disable signature checking or reset your pacman keyring.\n\n' >/dev/tty
  printf 'Attempt this repair? [y/N] ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=''
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

clear_affected_sync_databases() {
  local repo
  for repo in "$@"; do
    as_root rm -f -- \
      "${SYNC_DIR}/${repo}.db" \
      "${SYNC_DIR}/${repo}.db.sig"
  done
}

repair_sync_databases() {
  local -a repos=("$@")
  local sync_error rc=0

  (( ${#repos[@]} > 0 )) || return 1
  confirm_repair "${repos[@]}" || return 1

  refresh_supported_mirrors "${repos[@]}"
  clear_affected_sync_databases "${repos[@]}"

  sync_error="$(mktemp)"
  log "Forcing a fresh pacman database sync..."
  if run_capture_stderr root "$sync_error" -Syy; then
    rm -f -- "$sync_error"
    log "Pacman repository database recovery completed."
    return 0
  else
    rc=$?
  fi
  rm -f -- "$sync_error"
  warn "Pacman database resync still failed; no signature checks were bypassed and no keyring changes were made."
  return "$rc"
}

check_cached_sync_databases() {
  local error_file rc=0
  local -a repos=()

  error_file="$(mktemp)"
  if run_capture_stderr user "$error_file" -Slq >/dev/null; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(parse_sync_database_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"
  repair_sync_databases "${repos[@]}"
}

run_pacman_with_recovery() {
  local error_file rc=0 retry_rc=0
  local -a repos=() args=("$@")

  error_file="$(mktemp)"
  if run_capture_stderr root "$error_file" "${args[@]}"; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(parse_sync_database_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"

  if ! repair_sync_databases "${repos[@]}"; then
    return "$rc"
  fi

  error_file="$(mktemp)"
  log "Retrying the original pacman command once..."
  if run_capture_stderr root "$error_file" "${args[@]}"; then
    retry_rc=0
  else
    retry_rc=$?
  fi
  rm -f -- "$error_file"
  return "$retry_rc"
}

usage() {
  cat <<'EOF'
Usage:
  awtarchy-pacman-recovery.sh check
  awtarchy-pacman-recovery.sh run -- <pacman arguments...>

Internal Awtarchy helper for guarded recovery of invalid signed repository
sync databases. Package-file signature failures and keyring repair are outside
this helper's scope.
EOF
}

case "${1:-}" in
  check)
    shift
    (( $# == 0 )) || die "check does not accept additional arguments."
    check_cached_sync_databases
    ;;
  run)
    shift
    [[ ${1:-} == -- ]] || die "run requires -- before pacman arguments."
    shift
    (( $# > 0 )) || die "run requires pacman arguments."
    run_pacman_with_recovery "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
