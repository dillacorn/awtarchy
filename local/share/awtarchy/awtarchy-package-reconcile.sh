#!/usr/bin/env bash
# github.com/dillacorn/awtarchy
# Reconcile current Awtarchy package requirements and retired replacements.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

RUNTIME="${AWTARCHY_RUNTIME:-${HOME}/.local/share/awtarchy/awtarchy-runtime.sh}"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/awtarchy"
HARDWARE_FILE="${AWTARCHY_HARDWARE_FILE:-${STATE_DIR}/hardware-state}"
MANAGED_PACKAGES_FILE="${AWTARCHY_MANAGED_PACKAGES_FILE:-/var/lib/awtarchy/managed-packages}"
REVIEW_ONLY=0
MIGRATE_REPLACEMENTS_ONLY=0
MIGRATE_LOCKSCREEN_RETIREMENT_ONLY=0
NEEDS_ACTION_ONLY=0
PACMAN_RECOVERY_CHECK_ONLY=0
PACMAN_RECOVERY_RUN_ONLY=0
NVIDIA_ROLLBACK_ONLY=0
NVIDIA_ROLLBACK_ROOT="/var/lib/awtarchy"
NVIDIA_ROLLBACK_DIR="${NVIDIA_ROLLBACK_ROOT}/nvidia-driver-rollback"
NVIDIA_ROLLBACK_PENDING=""
NVIDIA_ROLLBACK_COMPLETE=0
PACMAN_CACHE_DIR="/var/cache/pacman/pkg"
declare -a PACMAN_RECOVERY_RUN_ARGS=()

# Packages required by currently exposed Awtarchy shell/runtime features.
# Keep this list small. The full installer catalog remains authoritative for
# optional package selection below.
declare -a REQUIRED_ARCH=(
  quickshell
  wl-clipboard
  cliphist
  upower
  playerctl
  hyprland-qt-support
  polkit
  python-gobject
  jq
)

# Explicit replacements retired by the Quickshell migration. An installed
# package is preselected for removal only when Awtarchy recorded ownership.
declare -a RETIRED_ARCH=(
  waybar
  waybar-git
  fuzzel
  wlogout
  mako
  wofi
  network-manager-applet
  blueman
  termdown
  qemu-guest-agent
)

declare -a ARCH_CATALOG=()
declare -a OPTIONAL_ARCH_CATALOG=()
declare -a AUR_CATALOG=()
declare -a OPTIONAL_AUR_CATALOG=()
declare -a FLATPAK_IDS=()
declare -a FLATPAK_NAMES=()
declare -a OPTIONAL_FLATPAK_IDS=()
declare -a OPTIONAL_FLATPAK_NAMES=()
declare -a MISSING_REQUIRED=()
declare -a MISSING_ARCH=()
declare -a MISSING_OPTIONAL_ARCH=()
declare -a MISSING_AUR=()
declare -a MISSING_OPTIONAL_AUR=()
declare -a MISSING_FLATPAK_IDS=()
declare -a MISSING_FLATPAK_NAMES=()
declare -a MISSING_OPTIONAL_FLATPAK_IDS=()
declare -a MISSING_OPTIONAL_FLATPAK_NAMES=()
declare -a RETIRED_MANAGED=()
declare -a RETIRED_UNOWNED=()
declare -a FAILED_AUR=()
SYSTEM_TYPE="unknown"
LY_STATUS="not installed"
CHEESE_REPLACEMENT_NEEDED=0
AUR_SCAN_BIN="/usr/bin/aur-scan"
if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && -n ${AWTARCHY_AUR_SCAN_BIN:-} ]]; then
  AUR_SCAN_BIN="$AWTARCHY_AUR_SCAN_BIN"
fi

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage:
  awtarchy packages
  awtarchy packages --review
  awtarchy nvidia-rollback

Without options, opens an installer-style package reconciliation UI.

The reconciler:
  - installs missing dependencies required by current Awtarchy features;
  - offers other missing current Arch/AUR/Flatpak catalog entries;
  - optionally installs/enables Ly on tty2;
  - offers removal of explicitly retired/replaced shell packages;
  - preselects retired package removal only for Awtarchy-owned packages.

Deselecting a current package never uninstalls it.

On systems with NVIDIA drivers, a full system upgrade requires confirmation.
Awtarchy saves a rollback point from the currently cached NVIDIA/kernel
packages when possible so the last driver update can be restored later.
EOF
}

while (( $# )); do
  case "$1" in
    --review)
      REVIEW_ONLY=1
      ;;
    --migrate-replacements)
      MIGRATE_REPLACEMENTS_ONLY=1
      ;;
    --migrate-lockscreen-retirement)
      MIGRATE_LOCKSCREEN_RETIREMENT_ONLY=1
      ;;
    --needs-action)
      NEEDS_ACTION_ONLY=1
      ;;
    --nvidia-rollback)
      NVIDIA_ROLLBACK_ONLY=1
      ;;
    --pacman-recovery-check)
      PACMAN_RECOVERY_CHECK_ONLY=1
      ;;
    --pacman-recovery-run)
      PACMAN_RECOVERY_RUN_ONLY=1
      shift
      [[ ${1:-} == -- ]] || die "--pacman-recovery-run requires -- before pacman arguments."
      shift
      (( $# > 0 )) || die "--pacman-recovery-run requires pacman arguments."
      PACMAN_RECOVERY_RUN_ARGS=("$@")
      break
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      die "Unknown packages option: $1"
      ;;
  esac
  shift
done

if (( PACMAN_RECOVERY_CHECK_ONLY == 0 && PACMAN_RECOVERY_RUN_ONLY == 0 )); then
  [[ -r "$RUNTIME" && ! -L "$RUNTIME" ]] \
    || die "Awtarchy runtime is unavailable or unsafe: ${RUNTIME}"
  have pacman || die "pacman is required for package reconciliation."
fi

strip_outer_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 && ${value:0:1} == '"' && ${value: -1} == '"' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s\n' "$value"
}

runtime_array_lines() {
  local name="$1"
  awk -v name="$name" '
    $0 ~ "^declare -a " name "=\\(" {
      line=$0
      sub("^.*=\\(", "", line)
      if (line ~ /\)[[:space:]]*$/) {
        sub(/\)[[:space:]]*$/, "", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "" && line !~ /^#/) print line
        exit
      }
      inside=1
      next
    }
    inside && /^[[:space:]]*\)[[:space:]]*$/ { exit }
    inside {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^#/) print line
    }
  ' "$RUNTIME"
}

sort_unique_array() {
  local -n target="$1"
  local tmp
  (( ${#target[@]} )) || return 0
  tmp="$(mktemp)"
  printf '%s\n' "${target[@]}" | LC_ALL=C sort -u >"$tmp"
  mapfile -t target <"$tmp"
  rm -f -- "$tmp"
}

array_contains() {
  local needle="$1" item
  shift || true
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

load_catalogs() {
  local raw entry package_text pkg selected friendly app_id
  local -a words=()

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry == *:* ]] || continue
    package_text="${entry#*:}"
    words=()
    IFS=' ' read -r -a words <<<"$package_text"
    for pkg in "${words[@]}"; do
      [[ -n $pkg ]] && ARCH_CATALOG+=("$pkg")
    done
  done < <(runtime_array_lines PKG_GROUPS)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    OPTIONAL_ARCH_CATALOG+=("$entry")
  done < <(runtime_array_lines OPTIONAL_ARCH_PACKAGES)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    AUR_CATALOG+=("$entry")
  done < <(runtime_array_lines PACKAGES_AUR)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    [[ $entry =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
    OPTIONAL_AUR_CATALOG+=("$entry")
  done < <(runtime_array_lines OPTIONAL_AUR_PACKAGES)

  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    entry="$(strip_outer_quotes "$raw")"
    IFS='|' read -r selected friendly app_id <<<"$entry"
    [[ -n ${friendly:-} && -n ${app_id:-} ]] || continue
    if [[ $selected == 0 ]]; then
      OPTIONAL_FLATPAK_NAMES+=("$friendly")
      OPTIONAL_FLATPAK_IDS+=("$app_id")
    else
      FLATPAK_NAMES+=("$friendly")
      FLATPAK_IDS+=("$app_id")
    fi
  done < <(runtime_array_lines FLATPAK_CATALOG)

  sort_unique_array ARCH_CATALOG
  sort_unique_array OPTIONAL_ARCH_CATALOG
  sort_unique_array AUR_CATALOG
  sort_unique_array OPTIONAL_AUR_CATALOG
}

package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

package_satisfied() {
  local pkg="$1"
  package_installed "$pkg" && return 0

  case "$pkg" in
    zathura-pdf-mupdf)
      package_installed zathura-pdf-poppler
      ;;
    zathura-pdf-poppler)
      package_installed zathura-pdf-mupdf
      ;;
    gamescope|gamescope-git)
      package_installed gamescope || package_installed gamescope-git
      ;;
    *)
      return 1
      ;;
  esac
}

obs_pipewire_audio_capture_user_plugin_installed() {
  [[ -f "${HOME}/.config/obs-studio/plugins/linux-pipewire-audio/bin/64bit/linux-pipewire-audio.so" ]]
}

aur_package_satisfied() {
  local pkg="$1" alt=""

  case "$pkg" in
    alacritty|alacritty-graphics)
      for alt in alacritty alacritty-graphics; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    qimgv|qimgv-git)
      for alt in qimgv qimgv-git; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    hyprmoncfg|hyprmoncfg-bin|hyprmoncfg-git)
      for alt in hyprmoncfg hyprmoncfg-bin hyprmoncfg-git; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    vesktop|vesktop-bin)
      for alt in vesktop vesktop-bin; do
        package_installed "$alt" && return 0
      done
      return 1
      ;;
    obs-pipewire-audio-capture|obs-pipewire-audio-capture-bin)
      for alt in obs-pipewire-audio-capture obs-pipewire-audio-capture-bin; do
        package_installed "$alt" && return 0
      done
      obs_pipewire_audio_capture_user_plugin_installed
      ;;
    *)
      package_installed "$pkg"
      ;;
  esac
}

managed_package() {
  [[ -r "$MANAGED_PACKAGES_FILE" ]] || return 1
  grep -Fxq -- "$1" "$MANAGED_PACKAGES_FILE"
}

flatpak_app_installed() {
  local app="$1"
  have flatpak || return 1
  flatpak --user list --app --columns=application 2>/dev/null | grep -Fxq -- "$app" \
    && return 0
  flatpak --system list --app --columns=application 2>/dev/null | grep -Fxq -- "$app"
}

detect_system_type() {
  local saved="" chassis=""
  if [[ -r "$HARDWARE_FILE" ]]; then
    saved="$(sed -n 's/^is_laptop=//p' "$HARDWARE_FILE" | head -n1)"
    case "$saved" in
      true) SYSTEM_TYPE="laptop"; return 0 ;;
      false) SYSTEM_TYPE="desktop"; return 0 ;;
    esac
  fi

  shopt -s nullglob
  local batteries=(/sys/class/power_supply/BAT*)
  shopt -u nullglob
  if (( ${#batteries[@]} )); then
    SYSTEM_TYPE="laptop"
    return 0
  fi

  if [[ -r /sys/class/dmi/id/chassis_type ]]; then
    chassis="$(tr -d '\r\n' </sys/class/dmi/id/chassis_type)"
    case "$chassis" in
      8|9|10|11|14|30|31|32) SYSTEM_TYPE="laptop"; return 0 ;;
      3|4|5|6|7|13|15|16|17|23|24|35|36) SYSTEM_TYPE="desktop"; return 0 ;;
    esac
  fi

  SYSTEM_TYPE="unknown"
}

detect_ly_status() {
  if ! package_installed ly; then
    LY_STATUS="not installed"
    return 0
  fi
  if have systemctl && systemctl is-enabled --quiet ly@tty2.service 2>/dev/null; then
    LY_STATUS="installed and enabled on tty2"
  else
    LY_STATUS="installed, not enabled on tty2"
  fi
}

collect_state() {
  local pkg i
  load_catalogs
  detect_system_type
  detect_ly_status
  package_installed cheese && CHEESE_REPLACEMENT_NEEDED=1

  for pkg in "${REQUIRED_ARCH[@]}"; do
    package_installed "$pkg" || MISSING_REQUIRED+=("$pkg")
  done

  for pkg in "${ARCH_CATALOG[@]}"; do
    package_satisfied "$pkg" && continue
    array_contains "$pkg" "${REQUIRED_ARCH[@]}" && continue
    [[ $pkg == ly ]] && continue
    MISSING_ARCH+=("$pkg")
  done

  for pkg in "${OPTIONAL_ARCH_CATALOG[@]}"; do
    package_satisfied "$pkg" || MISSING_OPTIONAL_ARCH+=("$pkg")
  done

  for pkg in "${AUR_CATALOG[@]}"; do
    aur_package_satisfied "$pkg" || MISSING_AUR+=("$pkg")
  done

  for pkg in "${OPTIONAL_AUR_CATALOG[@]}"; do
    aur_package_satisfied "$pkg" || MISSING_OPTIONAL_AUR+=("$pkg")
  done

  for i in "${!FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${FLATPAK_IDS[$i]}" && continue
    MISSING_FLATPAK_IDS+=("${FLATPAK_IDS[$i]}")
    MISSING_FLATPAK_NAMES+=("${FLATPAK_NAMES[$i]}")
  done

  for i in "${!OPTIONAL_FLATPAK_IDS[@]}"; do
    flatpak_app_installed "${OPTIONAL_FLATPAK_IDS[$i]}" && continue
    MISSING_OPTIONAL_FLATPAK_IDS+=("${OPTIONAL_FLATPAK_IDS[$i]}")
    MISSING_OPTIONAL_FLATPAK_NAMES+=("${OPTIONAL_FLATPAK_NAMES[$i]}")
  done

  for pkg in "${RETIRED_ARCH[@]}"; do
    package_installed "$pkg" || continue
    if managed_package "$pkg"; then
      RETIRED_MANAGED+=("$pkg")
    else
      RETIRED_UNOWNED+=("$pkg")
    fi
  done
}

print_list() {
  local heading="$1"
  shift || true
  printf '%s\n' "$heading"
  if (( $# == 0 )); then
    printf '  (none)\n'
    return 0
  fi
  printf '  - %s\n' "$@"
}

print_review() {
  printf '%s\n' 'Awtarchy package reconciliation review'
  printf 'System type: %s\n' "$SYSTEM_TYPE"
  printf 'Arch catalog packages: %d (%d default, %d optional)\n'     "$(( ${#ARCH_CATALOG[@]} + ${#OPTIONAL_ARCH_CATALOG[@]} ))"     "${#ARCH_CATALOG[@]}" "${#OPTIONAL_ARCH_CATALOG[@]}"
  printf 'AUR catalog packages: %d (%d default, %d optional)\n'     "$(( ${#AUR_CATALOG[@]} + ${#OPTIONAL_AUR_CATALOG[@]} ))"     "${#AUR_CATALOG[@]}" "${#OPTIONAL_AUR_CATALOG[@]}"
  printf 'Flatpak catalog apps: %d (%d default, %d optional)\n'     "$(( ${#FLATPAK_IDS[@]} + ${#OPTIONAL_FLATPAK_IDS[@]} ))"     "${#FLATPAK_IDS[@]}" "${#OPTIONAL_FLATPAK_IDS[@]}"
  printf 'Ly TTY login manager: %s\n' "$LY_STATUS"
  printf '\n'
  printf '%s\n' 'Required package replacements:'
  if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then
    printf '  - cheese -> snapshot\n'
  else
    printf '  (none)\n'
  fi
  printf '\n'
  print_list 'Missing required Awtarchy packages:' "${MISSING_REQUIRED[@]}"
  printf '\n'
  print_list 'Other missing current Arch catalog packages:' "${MISSING_ARCH[@]}"
  printf '\n'
  print_list 'Optional Arch packages not installed:' "${MISSING_OPTIONAL_ARCH[@]}"
  printf '\n'
  print_list 'Missing current AUR catalog packages:' "${MISSING_AUR[@]}"
  printf '\n'
  print_list 'Optional AUR packages not installed:' "${MISSING_OPTIONAL_AUR[@]}"
  printf '\n'
  if (( ${#MISSING_FLATPAK_IDS[@]} )); then
    printf '%s\n' 'Missing current Flatpak catalog apps:'
    local i
    for i in "${!MISSING_FLATPAK_IDS[@]}"; do
      printf '  - %s (%s)\n' "${MISSING_FLATPAK_NAMES[$i]}" "${MISSING_FLATPAK_IDS[$i]}"
    done
  else
    printf '%s\n' 'Missing current Flatpak catalog apps:' '  (none)'
  fi
  printf '\n'
  if (( ${#MISSING_OPTIONAL_FLATPAK_IDS[@]} )); then
    printf '%s\n' 'Optional Flatpak apps not installed:'
    local i
    for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
      printf '  - %s (%s)\n' "${MISSING_OPTIONAL_FLATPAK_NAMES[$i]}" "${MISSING_OPTIONAL_FLATPAK_IDS[$i]}"
    done
  else
    printf '%s\n' 'Optional Flatpak apps not installed:' '  (none)'
  fi
  printf '\n'
  print_list 'Retired Awtarchy-owned packages eligible for removal:' "${RETIRED_MANAGED[@]}"
  printf '\n'
  print_list 'Retired packages installed but not Awtarchy-owned (kept by default):' "${RETIRED_UNOWNED[@]}"
}

read_key() {
  local key rest
  IFS= read -rsn1 key </dev/tty || return 1
  if [[ $key == $'\033' ]]; then
    IFS= read -rsn2 -t 0.03 rest </dev/tty || true
    key+="$rest"
  fi
  printf '%s' "$key"
}

multi_select() {
  local title="$1" labels_name="$2" defaults_name="$3"
  local -n labels="$labels_name"
  local -n selected="$defaults_name"
  local current=0 key rows page start end i marker pointer

  (( ${#labels[@]} )) || return 0
  [[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

  while true; do
    rows="$(tput lines 2>/dev/null || printf '24')"
    [[ $rows =~ ^[0-9]+$ ]] || rows=24
    page=$(( rows - 8 ))
    (( page < 5 )) && page=5
    (( page > 18 )) && page=18
    start=$(( current - page / 2 ))
    (( start < 0 )) && start=0
    if (( start + page > ${#labels[@]} )); then
      start=$(( ${#labels[@]} - page ))
      (( start < 0 )) && start=0
    fi
    end=$(( start + page ))
    (( end > ${#labels[@]} )) && end=${#labels[@]}

    printf '\033[H\033[2J' >/dev/tty
    printf '%s\n\n' "$title" >/dev/tty
    printf '%s\n\n' 'Arrow keys move, Space toggles, A selects all, C clears all, Enter accepts, Esc cancels.' >/dev/tty
    for (( i=start; i<end; i++ )); do
      pointer=' '
      (( i == current )) && pointer='>'
      marker=' '
      (( selected[i] == 1 )) && marker='x'
      printf '%s [%s] %s\n' "$pointer" "$marker" "${labels[$i]}" >/dev/tty
    done
    if (( ${#labels[@]} > page )); then
      printf '\n%d-%d of %d\n' "$((start + 1))" "$end" "${#labels[@]}" >/dev/tty
    fi

    key="$(read_key)" || return 1
    case "$key" in
      $'\033[A'|k)
        if (( current > 0 )); then
          ((current--))
        fi
        ;;
      $'\033[B'|j)
        if (( current + 1 < ${#labels[@]} )); then
          ((current++))
        fi
        ;;
      ' ')
        if (( selected[current] == 1 )); then selected[current]=0; else selected[current]=1; fi
        ;;
      a|A)
        for i in "${!selected[@]}"; do selected[i]=1; done
        ;;
      c|C)
        for i in "${!selected[@]}"; do selected[i]=0; done
        ;;
      ''|$'\n'|$'\r')
        return 0
        ;;
      $'\033'|q|Q)
        return 1
        ;;
    esac
  done
}

confirm_yes_no() {
  local prompt="$1" default_yes="${2:-0}" answer=""
  local suffix='[y/N]'
  (( default_yes == 1 )) && suffix='[Y/n]'
  printf '%s %s ' "$prompt" "$suffix" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    n|N|no|NO) return 1 ;;
    '') (( default_yes == 1 )) ;;
    *) return 1 ;;
  esac
}


nvidia_rollback_package_name() {
  case "$1" in
    nvidia|nvidia-*|lib32-nvidia-*|opencl-nvidia*|lib32-opencl-nvidia*|libva-nvidia-driver|linux-*-nvidia*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

installed_nvidia_package_names() {
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    nvidia_rollback_package_name "$pkg" && printf '%s\n' "$pkg"
  done < <(pacman -Qq 2>/dev/null || true)
}

current_kernel_package_names() {
  local pkgbase_file pkg

  if [[ -n "${AWTARCHY_KERNEL_PKGBASES:-}" ]]; then
    tr ' ' '\n' <<<"$AWTARCHY_KERNEL_PKGBASES" | sed '/^$/d' | LC_ALL=C sort -u
    return 0
  fi

  shopt -s nullglob
  for pkgbase_file in /usr/lib/modules/*/pkgbase; do
    [[ -r "$pkgbase_file" ]] || continue
    pkg="$(tr -d '\r\n' <"$pkgbase_file")"
    [[ -n "$pkg" ]] && printf '%s\n' "$pkg"
  done
  shopt -u nullglob
}

nvidia_rollback_candidate_packages() {
  local pkg
  local -a packages=()

  mapfile -t packages < <(installed_nvidia_package_names)
  (( ${#packages[@]} )) || return 1

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    packages+=("$pkg")
    package_installed "${pkg}-headers" && packages+=("${pkg}-headers")
  done < <(current_kernel_package_names)

  printf '%s\n' "${packages[@]}" | sed '/^$/d' | LC_ALL=C sort -u
}

package_version() {
  pacman -Q "$1" 2>/dev/null | awk 'NR == 1 { print $2 }'
}

root_owned_nonwritable_path() {
  local path="$1" owner="" mode=""

  [[ -e "$path" && ! -L "$path" ]] || return 1
  owner="$(/usr/bin/stat -Lc '%u' -- "$path" 2>/dev/null)" || return 1
  mode="$(/usr/bin/stat -Lc '%a' -- "$path" 2>/dev/null)" || return 1
  [[ "$owner" == 0 && "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  (( (8#$mode & 0022) == 0 ))
}

trusted_nvidia_cache_archive() {
  local archive="$1"
  [[ -f "$archive" && ! -L "$archive" ]] || return 1
  root_owned_nonwritable_path "$archive"
}

find_cached_package_archive() {
  local pkg="$1" version="$2" candidate
  local -a matches=()

  shopt -s nullglob
  matches=(
    "${PACMAN_CACHE_DIR}/${pkg}-${version}-"*.pkg.tar.*
  )
  shopt -u nullglob

  for candidate in "${matches[@]}"; do
    [[ "$candidate" != *.sig ]] || continue
    trusted_nvidia_cache_archive "$candidate" || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

validate_nvidia_rollback_storage() {
  root_owned_nonwritable_path "$NVIDIA_ROLLBACK_ROOT" \
    && [[ -d "$NVIDIA_ROLLBACK_ROOT" ]] \
    && root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR" \
    && [[ -d "$NVIDIA_ROLLBACK_DIR" ]] \
    && root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR/packages" \
    && [[ -d "$NVIDIA_ROLLBACK_DIR/packages" ]] \
    && root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR/metadata" \
    && [[ -f "$NVIDIA_ROLLBACK_DIR/metadata" ]] \
    && root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR/changes.tsv" \
    && [[ -f "$NVIDIA_ROLLBACK_DIR/changes.tsv" ]]
}

cleanup_nvidia_pending_snapshot() {
  if [[ -n "${NVIDIA_ROLLBACK_PENDING:-}" && -e "$NVIDIA_ROLLBACK_PENDING" ]]; then
    as_root rm -rf -- "$NVIDIA_ROLLBACK_PENDING" \
      || warn "Could not remove pending NVIDIA rollback state: $NVIDIA_ROLLBACK_PENDING"
  fi
}

prepare_nvidia_rollback_snapshot() {
  local pkg version archive="" archive_name="" missing=0 metadata_tmp="" before_tmp=""
  local -a candidates=() missing_packages=()

  mapfile -t candidates < <(nvidia_rollback_candidate_packages) || return 2
  (( ${#candidates[@]} )) || return 2

  NVIDIA_ROLLBACK_PENDING="${NVIDIA_ROLLBACK_DIR}.pending.$"
  if ! as_root rm -rf -- "$NVIDIA_ROLLBACK_PENDING" \
    || ! as_root install -d -m 0755 -- \
      "$NVIDIA_ROLLBACK_ROOT" \
      "$NVIDIA_ROLLBACK_PENDING" \
      "$NVIDIA_ROLLBACK_PENDING/packages";
  then
    NVIDIA_ROLLBACK_PENDING=""
    return 3
  fi

  metadata_tmp="$(mktemp)"
  before_tmp="$(mktemp)"
  {
    printf 'created_at=%s\n' "$(date -Iseconds)"
    printf 'status=pending\n'
  } >"$metadata_tmp"
  : >"$before_tmp"

  for pkg in "${candidates[@]}"; do
    version="$(package_version "$pkg" || true)"
    [[ -n "$version" ]] || continue
    archive=""
    archive_name=""
    if archive="$(find_cached_package_archive "$pkg" "$version" 2>/dev/null)"; then
      archive_name="$(basename -- "$archive")"
      if ! as_root install -m 0644 -- \
        "$archive" "$NVIDIA_ROLLBACK_PENDING/packages/$archive_name";
      then
        rm -f -- "$metadata_tmp" "$before_tmp"
        cleanup_nvidia_pending_snapshot
        NVIDIA_ROLLBACK_PENDING=""
        return 3
      fi
    else
      missing=1
      missing_packages+=("$pkg")
    fi
    printf '%s\t%s\t%s\n' "$pkg" "$version" "$archive_name" >>"$before_tmp"
  done

  if (( missing == 1 )); then
    printf 'snapshot_complete=0\n' >>"$metadata_tmp"
  else
    printf 'snapshot_complete=1\n' >>"$metadata_tmp"
  fi

  if ! as_root install -m 0644 -- "$metadata_tmp" "$NVIDIA_ROLLBACK_PENDING/metadata" \
    || ! as_root install -m 0644 -- "$before_tmp" "$NVIDIA_ROLLBACK_PENDING/before.tsv";
  then
    rm -f -- "$metadata_tmp" "$before_tmp"
    cleanup_nvidia_pending_snapshot
    NVIDIA_ROLLBACK_PENDING=""
    return 3
  fi
  rm -f -- "$metadata_tmp" "$before_tmp"

  if (( missing == 1 )); then
    warn "NVIDIA rollback point is missing trusted cached package archives for: ${missing_packages[*]}"
    return 1
  fi

  return 0
}

finalize_nvidia_rollback_snapshot() {
  local pkg old_version archive_name current_version complete=1 changed=0
  local changes_tmp="" metadata_tmp=""

  [[ -n "$NVIDIA_ROLLBACK_PENDING" && -d "$NVIDIA_ROLLBACK_PENDING" ]] || return 1

  changes_tmp="$(mktemp)"
  metadata_tmp="$(mktemp)"
  : >"$changes_tmp"

  while IFS=$'\t' read -r pkg old_version archive_name; do
    [[ -n "$pkg" && -n "$old_version" ]] || continue
    current_version="$(package_version "$pkg" || true)"
    [[ -n "$current_version" ]] || current_version='(not installed)'
    [[ "$current_version" != "$old_version" ]] || continue

    changed=1
    if [[ -z "$archive_name" || ! -f "$NVIDIA_ROLLBACK_PENDING/packages/$archive_name" ]]; then
      complete=0
    fi
    printf '%s\t%s\t%s\t%s\n' "$pkg" "$old_version" "$current_version" "$archive_name" >>"$changes_tmp"
  done <"$NVIDIA_ROLLBACK_PENDING/before.tsv"

  if (( changed == 0 )); then
    rm -f -- "$changes_tmp" "$metadata_tmp"
    cleanup_nvidia_pending_snapshot
    NVIDIA_ROLLBACK_PENDING=""
    NVIDIA_ROLLBACK_COMPLETE=0
    return 1
  fi

  NVIDIA_ROLLBACK_COMPLETE="$complete"
  if ! cat -- "$NVIDIA_ROLLBACK_PENDING/metadata" >"$metadata_tmp"; then
    rm -f -- "$changes_tmp" "$metadata_tmp"
    die "Could not read pending NVIDIA rollback metadata."
  fi
  {
    printf 'status=available\n'
    printf 'finalized_at=%s\n' "$(date -Iseconds)"
    printf 'rollback_complete=%s\n' "$complete"
  } >>"$metadata_tmp"

  if ! as_root install -m 0644 -- "$changes_tmp" "$NVIDIA_ROLLBACK_PENDING/changes.tsv" \
    || ! as_root install -m 0644 -- "$metadata_tmp" "$NVIDIA_ROLLBACK_PENDING/metadata";
  then
    rm -f -- "$changes_tmp" "$metadata_tmp"
    die "Could not finalize the NVIDIA rollback point."
  fi
  rm -f -- "$changes_tmp" "$metadata_tmp"

  if ! as_root rm -rf -- "${NVIDIA_ROLLBACK_DIR}.previous"; then
    die "Could not clear the previous NVIDIA rollback staging path."
  fi
  if [[ -e "$NVIDIA_ROLLBACK_DIR" ]]; then
    if ! as_root mv -- "$NVIDIA_ROLLBACK_DIR" "${NVIDIA_ROLLBACK_DIR}.previous"; then
      die "Could not preserve the previous NVIDIA rollback point."
    fi
  fi
  if ! as_root mv -- "$NVIDIA_ROLLBACK_PENDING" "$NVIDIA_ROLLBACK_DIR"; then
    if [[ -e "${NVIDIA_ROLLBACK_DIR}.previous" ]]; then
      as_root mv -- "${NVIDIA_ROLLBACK_DIR}.previous" "$NVIDIA_ROLLBACK_DIR" \
        || warn "Could not restore the previous NVIDIA rollback point after persistence failure."
    fi
    die "Could not save the NVIDIA rollback point."
  fi
  if ! as_root rm -rf -- "${NVIDIA_ROLLBACK_DIR}.previous"; then
    warn "Saved the new NVIDIA rollback point, but could not remove the previous snapshot staging directory."
  fi
  NVIDIA_ROLLBACK_PENDING=""
  return 0
}

print_nvidia_rollback_changes() {
  local pkg old_version current_version archive_name

  [[ -r "$NVIDIA_ROLLBACK_DIR/changes.tsv" ]] || return 1
  printf '%s\n' 'NVIDIA/kernel packages changed:' >/dev/tty
  while IFS=$'\t' read -r pkg old_version current_version archive_name; do
    [[ -n "$pkg" ]] || continue
    printf '  %s: %s -> %s\n' "$pkg" "$old_version" "$current_version" >/dev/tty
  done <"$NVIDIA_ROLLBACK_DIR/changes.tsv"
}

apply_nvidia_rollback() {
  local assume_yes="${1:-0}" complete="" pkg old_version saved_current_version archive_name installed_version
  local metadata_tmp=""
  local -a archives=()

  [[ -r "$NVIDIA_ROLLBACK_DIR/metadata" && -r "$NVIDIA_ROLLBACK_DIR/changes.tsv" ]] \
    || die "No saved NVIDIA rollback point is available."
  validate_nvidia_rollback_storage \
    || die "Saved NVIDIA rollback state is not root-owned and immutable enough for privileged package restore."

  complete="$(sed -n 's/^rollback_complete=//p' "$NVIDIA_ROLLBACK_DIR/metadata" | tail -n1)"
  [[ "$complete" == 1 ]] \
    || die "The saved NVIDIA rollback point is incomplete; refusing an automatic partial driver rollback."

  if [[ ${AWTARCHY_TEST_MODE:-0} != 1 ]]; then
    print_nvidia_rollback_changes
    printf '\nRollback restores the saved NVIDIA packages and any kernel packages that changed with them.\n' >/dev/tty
    printf 'A reboot is recommended after rollback.\n\n' >/dev/tty
  fi

  while IFS=$'\t' read -r pkg old_version saved_current_version archive_name; do
    [[ -n "$pkg" && -n "$old_version" && -n "$saved_current_version" ]] || continue
    installed_version="$(package_version "$pkg" || true)"
    [[ -n "$installed_version" ]] || installed_version='(not installed)'
    if [[ "$installed_version" != "$old_version" && "$installed_version" != "$saved_current_version" ]]; then
      die "Saved NVIDIA rollback point no longer matches ${pkg}: expected ${saved_current_version} (or already-restored ${old_version}), found ${installed_version}. Refusing an automatic rollback after later package changes."
    fi
  done <"$NVIDIA_ROLLBACK_DIR/changes.tsv"

  if (( assume_yes == 0 )); then
    confirm_yes_no 'Restore the saved NVIDIA/kernel package versions now?' 0 \
      || { log 'NVIDIA rollback canceled.'; return 0; }
  fi

  while IFS=$'\t' read -r pkg old_version saved_current_version archive_name; do
    [[ -n "$pkg" && -n "$old_version" ]] || continue
    installed_version="$(package_version "$pkg" || true)"
    [[ -n "$installed_version" ]] || installed_version='(not installed)'
    [[ "$installed_version" != "$old_version" ]] || continue
    [[ -n "$archive_name" && "$archive_name" == "$(basename -- "$archive_name")" ]] \
      || die "Rollback archive name is invalid for ${pkg} ${old_version}."
    [[ -f "$NVIDIA_ROLLBACK_DIR/packages/$archive_name" && ! -L "$NVIDIA_ROLLBACK_DIR/packages/$archive_name" ]] \
      || die "Rollback archive is missing for ${pkg} ${old_version}."
    root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR/packages/$archive_name" \
      || die "Rollback archive is not trusted for privileged restore: ${archive_name}."
    archives+=("$NVIDIA_ROLLBACK_DIR/packages/$archive_name")
  done <"$NVIDIA_ROLLBACK_DIR/changes.tsv"

  if (( ${#archives[@]} == 0 )); then
    log 'Saved NVIDIA/kernel versions are already restored.'
    return 0
  fi

  if ! as_root pacman -U --needed --noconfirm "${archives[@]}"; then
    die "NVIDIA rollback package transaction failed."
  fi

  while IFS=    [[ -n "$pkg" && -n "$old_version" ]] || continue
    if [[ "$(package_version "$pkg" || true)" != "$old_version" ]]; then
      die "NVIDIA rollback verification failed for ${pkg}; expected ${old_version}."
    fi
  done <"$NVIDIA_ROLLBACK_DIR/changes.tsv"

  metadata_tmp="$(mktemp)"
  if ! cat -- "$NVIDIA_ROLLBACK_DIR/metadata" >"$metadata_tmp"; then
    rm -f -- "$metadata_tmp"
    die "NVIDIA packages were restored, but rollback metadata could not be read for status update."
  fi
  {
    printf 'restored_at=%s\n' "$(date -Iseconds)"
    printf 'status=restored\n'
  } >>"$metadata_tmp"
  if ! as_root install -m 0644 -- "$metadata_tmp" "$NVIDIA_ROLLBACK_DIR/metadata"; then
    rm -f -- "$metadata_tmp"
    die "NVIDIA packages were restored, but rollback metadata could not be updated."
  fi
  rm -f -- "$metadata_tmp"

  log 'NVIDIA/kernel rollback completed. Reboot before judging the restored driver.'
}

confirm_nvidia_system_upgrade() {
  local snapshot_rc=0
  local -a nvidia_packages=()

  mapfile -t nvidia_packages < <(installed_nvidia_package_names)
  (( ${#nvidia_packages[@]} )) || return 0

  printf '\nNVIDIA drivers are installed on this system.\n' >/dev/tty
  printf 'This package plan requires a full system upgrade, which may update the NVIDIA driver and kernel.\n' >/dev/tty
  printf 'Awtarchy will save the currently cached driver/kernel packages first so they can be restored later.\n\n' >/dev/tty
  printf 'Current NVIDIA packages:\n' >/dev/tty
  pacman -Q "${nvidia_packages[@]}" 2>/dev/null | sed 's/^/  /' >/dev/tty || true
  printf '\n' >/dev/tty

  confirm_yes_no 'Allow the full system upgrade, including any available NVIDIA update?' 0 \
    || { log 'Package reconciliation canceled before NVIDIA/system upgrade.'; return 1; }

  prepare_nvidia_rollback_snapshot || snapshot_rc=$?
  case "$snapshot_rc" in
    0)
      log 'Saved a complete pre-upgrade NVIDIA/kernel rollback snapshot.'
      ;;
    1)
      printf '\nAwtarchy could not cache every currently installed NVIDIA/kernel package.\n' >/dev/tty
      printf 'A one-command rollback may be unavailable if one of those uncached packages changes.\n' >/dev/tty
      confirm_yes_no 'Continue with the NVIDIA/system upgrade anyway?' 0 \
        || {
          cleanup_nvidia_pending_snapshot
          NVIDIA_ROLLBACK_PENDING=""
          log 'Package reconciliation canceled because a complete rollback point was unavailable.'
          return 1
        }
      ;;
    2)
      NVIDIA_ROLLBACK_PENDING=""
      ;;
    *)
      die 'Could not prepare the NVIDIA rollback point.'
      ;;
  esac
  return 0
}

offer_nvidia_post_upgrade_choice() {
  [[ -n "$NVIDIA_ROLLBACK_PENDING" ]] || return 0

  if ! finalize_nvidia_rollback_snapshot; then
    log 'NVIDIA/kernel package versions did not change during the system upgrade.'
    return 0
  fi

  printf '\n' >/dev/tty
  print_nvidia_rollback_changes
  printf '\n' >/dev/tty

  if (( NVIDIA_ROLLBACK_COMPLETE == 1 )); then
    printf 'Rollback point saved. If a problem appears after reboot, run: awtarchy nvidia-rollback\n' >/dev/tty
    printf 'Some NVIDIA problems only appear after reboot or when launching a game.\n' >/dev/tty
    if ! confirm_yes_no 'Keep the new NVIDIA/kernel versions for now?' 1; then
      apply_nvidia_rollback 1
      return 20
    fi
  else
    warn 'NVIDIA/kernel packages changed, but the saved rollback point is incomplete.'
    warn 'Awtarchy will not attempt an unsafe partial automatic rollback.'
  fi
}

choose_ly_action() {
  install_ly=0
  enable_ly=0

  case "$LY_STATUS" in
    'not installed')
      if confirm_yes_no 'Install and enable Ly on tty2?' 0; then
        install_ly=1
        enable_ly=1
      fi
      ;;
    'installed, not enabled on tty2')
      if confirm_yes_no 'Enable installed Ly on tty2?' 0; then
        enable_ly=1
      fi
      ;;
    'installed and enabled on tty2')
      printf '\nLy is already installed and enabled on tty2; leaving it unchanged.\n' >/dev/tty
      ;;
    *)
      printf '\nLy state is %s; leaving it unchanged.\n' "$LY_STATUS" >/dev/tty
      ;;
  esac
}

selected_values() {
  local values_name="$1" flags_name="$2" output_name="$3"
  local -n values="$values_name"
  local -n flags="$flags_name"
  local -n output="$output_name"
  local i
  output=()
  for i in "${!values[@]}"; do
    (( flags[i] == 1 )) && output+=("${values[$i]}")
  done
}

root_free_mib() {
  local available_kib=""
  available_kib="$(/usr/bin/df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ $available_kib =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$(( available_kib / 1024 ))"
}

recover_package_disk_headroom() {
  local preferred_mib="${AWTARCHY_UPDATE_PREFERRED_FREE_MIB:-4096}"
  local required_mib="${AWTARCHY_UPDATE_REQUIRED_FREE_MIB:-1024}"
  local free_mib="" paccache_bin=""

  [[ $preferred_mib =~ ^[0-9]+$ && $required_mib =~ ^[0-9]+$ ]] \
    || die "Invalid update disk-space threshold override."
  (( preferred_mib >= required_mib )) \
    || die "Preferred update disk-space threshold cannot be below the required threshold."

  free_mib="$(root_free_mib)" \
    || die "Could not determine free space on the root filesystem."
  (( free_mib >= preferred_mib )) && return 0

  for paccache_bin in /usr/bin/paccache /usr/sbin/paccache; do
    [[ -x $paccache_bin ]] && break
    paccache_bin=""
  done

  if [[ -n $paccache_bin ]]; then
    log "Root filesystem has ${free_mib} MiB free; pruning old pacman cache entries while keeping two package versions..."
    if ! as_root "$paccache_bin" -rk2; then
      die "Automatic pacman cache pruning failed."
    fi
    free_mib="$(root_free_mib)" \
      || die "Could not re-check free space after pacman cache pruning."
  fi

  (( free_mib >= required_mib )) \
    || die "Root filesystem has only ${free_mib} MiB free; at least ${required_mib} MiB is required before continuing package installation."

  if (( free_mib < preferred_mib )); then
    warn "Root filesystem has ${free_mib} MiB free; continuing above the ${required_mib} MiB hard minimum."
  fi
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -- "$@"
  fi
}

pacman_recovery_supported_runtime() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    return 0
  fi
  [[ $(command -v pacman 2>/dev/null || true) == /usr/bin/pacman && -x /usr/bin/pacman ]]
}

pacman_recovery_configure() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    PACMAN_RECOVERY_PACMAN="${AWTARCHY_PACMAN_BIN:?test mode requires AWTARCHY_PACMAN_BIN}"
    PACMAN_RECOVERY_CONF="${AWTARCHY_PACMAN_CONF:?test mode requires AWTARCHY_PACMAN_CONF}"
    PACMAN_RECOVERY_SYNC_DIR="${AWTARCHY_PACMAN_SYNC_DIR:?test mode requires AWTARCHY_PACMAN_SYNC_DIR}"
    PACMAN_RECOVERY_CACHY_RATE="${AWTARCHY_CACHY_RATE_BIN:-/nonexistent/cachyos-rate-mirrors}"
    PACMAN_RECOVERY_REFLECTOR="${AWTARCHY_REFLECTOR_BIN:-/nonexistent/reflector}"
    PACMAN_RECOVERY_SKIP_MIRROR_REFRESH="${AWTARCHY_SKIP_MIRROR_REFRESH:-0}"
  else
    PACMAN_RECOVERY_PACMAN=/usr/bin/pacman
    PACMAN_RECOVERY_CONF=/etc/pacman.conf
    PACMAN_RECOVERY_SYNC_DIR=/var/lib/pacman/sync
    PACMAN_RECOVERY_CACHY_RATE=/usr/bin/cachyos-rate-mirrors
    PACMAN_RECOVERY_REFLECTOR=/usr/bin/reflector
    PACMAN_RECOVERY_SKIP_MIRROR_REFRESH=0
  fi

  [[ -x $PACMAN_RECOVERY_PACMAN ]] \
    || { warn "Pacman recovery binary is unavailable: ${PACMAN_RECOVERY_PACMAN}"; return 1; }
  [[ -r $PACMAN_RECOVERY_CONF ]] \
    || { warn "Pacman recovery configuration is unavailable: ${PACMAN_RECOVERY_CONF}"; return 1; }
}

pacman_recovery_as_root() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    "$@"
  else
    as_root "$@"
  fi
}

pacman_recovery_run_capture() {
  local root_mode="$1" error_file="$2"
  shift 2
  local rc=0

  : >"$error_file"
  if [[ $root_mode == root ]]; then
    if pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" "$@" 2>"$error_file"; then
      rc=0
    else
      rc=$?
    fi
  else
    if "$PACMAN_RECOVERY_PACMAN" "$@" 2>"$error_file"; then
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

pacman_recovery_parse_repos() {
  local error_file="$1" line
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

pacman_recovery_repo_is_cachyos() {
  [[ $1 == cachyos || $1 == cachyos-* ]]
}

pacman_recovery_repo_is_arch() {
  [[ $1 =~ ^(core|extra|multilib)(-testing|-staging)?$ ]]
}

pacman_recovery_repo_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

pacman_recovery_write_config_without_repos() {
  local destination="$1"
  shift
  local -a blocked=("$@")
  local line section="" skip=0

  : >"$destination"
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^\[([A-Za-z0-9@._+:-]+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"
      if pacman_recovery_repo_in_list "$section" "${blocked[@]}"; then
        skip=1
      else
        skip=0
      fi
    fi
    (( skip == 1 )) || printf '%s\n' "$line" >>"$destination"
  done <"$PACMAN_RECOVERY_CONF"
}

pacman_recovery_bootstrap_tool() {
  local kind="$1"
  shift
  local -a repos=("$@")
  local tmp_conf

  tmp_conf="$(mktemp)"
  pacman_recovery_write_config_without_repos "$tmp_conf" "${repos[@]}"

  case "$kind" in
    cachyos)
      log "CachyOS mirror tool is missing; bootstrapping rate-mirrors and cachyos-rate-mirrors without the broken repository."
      if ! pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" \
        --config "$tmp_conf" -S --needed --noconfirm rate-mirrors cachyos-rate-mirrors; then
        rm -f -- "$tmp_conf"
        warn "Could not bootstrap cachyos-rate-mirrors; continuing with targeted database resync only."
        return 1
      fi
      ;;
    arch)
      log "Arch mirror tool is missing; trying to bootstrap reflector without the broken repository."
      if ! pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" \
        --config "$tmp_conf" -S --needed --noconfirm reflector; then
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
}

pacman_recovery_refresh_mirrors() {
  local -a repos=("$@")
  local repo need_cachy=0 need_arch=0

  [[ $PACMAN_RECOVERY_SKIP_MIRROR_REFRESH == 1 ]] && return 0

  for repo in "${repos[@]}"; do
    pacman_recovery_repo_is_cachyos "$repo" && need_cachy=1
    pacman_recovery_repo_is_arch "$repo" && need_arch=1
  done

  if (( need_cachy == 1 )); then
    if [[ ! -x $PACMAN_RECOVERY_CACHY_RATE ]]; then
      pacman_recovery_bootstrap_tool cachyos "${repos[@]}" || true
    fi
    if [[ -x $PACMAN_RECOVERY_CACHY_RATE ]]; then
      log "Refreshing CachyOS mirrors before retrying pacman..."
      pacman_recovery_as_root "$PACMAN_RECOVERY_CACHY_RATE" \
        || warn "CachyOS mirror refresh failed; continuing with targeted database resync only."
    fi
  fi

  if (( need_arch == 1 )); then
    if [[ ! -x $PACMAN_RECOVERY_REFLECTOR ]]; then
      pacman_recovery_bootstrap_tool arch "${repos[@]}" || true
    fi
    if [[ -x $PACMAN_RECOVERY_REFLECTOR ]]; then
      log "Refreshing standard Arch mirrors before retrying pacman..."
      pacman_recovery_as_root "$PACMAN_RECOVERY_REFLECTOR" \
        --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist \
        || warn "Arch mirror refresh failed; continuing with targeted database resync only."
    fi
  fi
}

pacman_recovery_confirm() {
  local answer=""
  local -a repos=("$@")

  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
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
    *)
      printf 'Pacman repository repair skipped.\n' >/dev/tty
      return 1
      ;;
  esac
}

pacman_recovery_clear_sync_databases() {
  local repo
  for repo in "$@"; do
    pacman_recovery_as_root rm -f -- \
      "${PACMAN_RECOVERY_SYNC_DIR}/${repo}.db" \
      "${PACMAN_RECOVERY_SYNC_DIR}/${repo}.db.sig"
  done
}

pacman_recovery_repair() {
  local -a repos=("$@")
  local error_file rc=0

  (( ${#repos[@]} > 0 )) || return 1
  pacman_recovery_confirm "${repos[@]}" || return 1

  pacman_recovery_refresh_mirrors "${repos[@]}"
  pacman_recovery_clear_sync_databases "${repos[@]}"

  error_file="$(mktemp)"
  log "Forcing a fresh pacman database sync..."
  if pacman_recovery_run_capture root "$error_file" -Syy; then
    rm -f -- "$error_file"
    log "Pacman repository database recovery completed."
    return 0
  else
    rc=$?
  fi
  rm -f -- "$error_file"
  warn "Pacman database resync still failed; no signature checks were bypassed and no keyring changes were made."
  return "$rc"
}

pacman_sync_db_preflight() {
  local error_file rc=0
  local -a repos=()

  pacman_recovery_supported_runtime || return 0
  pacman_recovery_configure || return 1

  error_file="$(mktemp)"
  if pacman_recovery_run_capture user "$error_file" -Slq >/dev/null; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(pacman_recovery_parse_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"
  pacman_recovery_repair "${repos[@]}"
}

pacman_recovery_run_command() {
  local error_file rc=0 retry_rc=0
  local -a repos=() args=("$@")

  pacman_recovery_supported_runtime || {
    as_root pacman "${args[@]}"
    return $?
  }
  pacman_recovery_configure || return 1

  error_file="$(mktemp)"
  if pacman_recovery_run_capture root "$error_file" "${args[@]}"; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(pacman_recovery_parse_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"

  if ! pacman_recovery_repair "${repos[@]}"; then
    return "$rc"
  fi

  error_file="$(mktemp)"
  log "Retrying the original pacman command once..."
  if pacman_recovery_run_capture root "$error_file" "${args[@]}"; then
    retry_rc=0
  else
    retry_rc=$?
  fi
  rm -f -- "$error_file"
  return "$retry_rc"
}

pacman_install_with_recovery() {
  pacman_recovery_run_command "$@"
}

ensure_aur_scanner() {
  if [[ -x "$AUR_SCAN_BIN" ]] && "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$AUR_SCAN_BIN" != /usr/bin/aur-scan ]]; then
    warn "Configured aur-scan test binary is unavailable: ${AUR_SCAN_BIN}"
    return 1
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "aur-scanner is missing and a usable /usr/bin/yay is unavailable for the one-time bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner through yay for the one-time bootstrap..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner installed without a usable /usr/bin/aur-scan."
    return 1
  fi

  AUR_SCAN_BIN="/usr/bin/aur-scan"
}

install_selected_aur_packages() {
  local pkg

  for pkg in "$@"; do
    if aur_package_satisfied "$pkg"; then
      log "${pkg} or an equivalent installation is already present; skipping."
      continue
    fi

    if (( EUID != 0 )); then
      sudo -k
    fi
    log "Installing AUR package through upstream aur-scanner: ${pkg}"
    if ! "$AUR_SCAN_BIN" install "$pkg" --noconfirm; then
      warn "AUR package failed: ${pkg}. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! aur_package_satisfied "$pkg"; then
      warn "aur-scanner returned success but ${pkg} is still not detected. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! record_managed_packages "$pkg"; then
      warn "${pkg} installed, but Awtarchy could not update its managed-package ledger."
    fi
  done

  return 0
}

record_managed_packages() {
  local -a add=("$@")
  local tmp pkg
  (( ${#add[@]} )) || return 0
  tmp="$(mktemp)"
  if [[ -r "$MANAGED_PACKAGES_FILE" ]]; then
    cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  else
    : >"$tmp"
  fi
  for pkg in "${add[@]}"; do
    package_installed "$pkg" && printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -d -m 0755 -- "$(dirname -- "$MANAGED_PACKAGES_FILE")"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

forget_managed_packages() {
  local -a remove=("$@")
  local tmp pkg
  (( ${#remove[@]} )) || return 0
  [[ -r "$MANAGED_PACKAGES_FILE" ]] || return 0
  tmp="$(mktemp)"
  cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  for pkg in "${remove[@]}"; do
    sed -i "/^$(printf '%s' "$pkg" | sed 's/[][\\.^$*+?{}|()]/\\&/g')$/d" "$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

apply_cheese_snapshot_replacement() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) || return 0

  log "Replacing retired Cheese camera app with Snapshot..."
  if ! package_installed snapshot; then
    pacman_install_with_recovery -S --needed --noconfirm snapshot
  fi
  record_managed_packages snapshot
  as_root pacman -R --noconfirm cheese
  forget_managed_packages cheese
  CHEESE_REPLACEMENT_NEEDED=0
  log "Replaced Cheese with Snapshot."
}

apply_bibata_cursor_replacement() {
  array_contains bibata-cursor-theme-bin "${AUR_CATALOG[@]}" || return 0

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    if [[ ! -x "$AUR_SCAN_BIN" ]] || ! "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
      warn "Bibata cursor migration requires a usable aur-scan; leaving the existing cursor package untouched."
      return 0
    fi
    log "Installing Bibata cursor theme through upstream aur-scanner..."
    install_selected_aur_packages bibata-cursor-theme-bin
  fi

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    warn "Bibata cursor theme is not installed; leaving the existing cursor package untouched."
    return 0
  fi

  package_installed xcursor-comix || return 0
  local ownership_recorded=0
  managed_package xcursor-comix && ownership_recorded=1
  log "Removing retired xcursor-comix package after Bibata replacement..."

  if ! as_root pacman -R --noconfirm xcursor-comix; then
    warn "Could not remove retired xcursor-comix; leaving it installed for a later retry."
    return 0
  fi
  if package_installed xcursor-comix; then
    warn "xcursor-comix is still detected after package removal."
    return 0
  fi
  if (( ownership_recorded == 1 )); then
    if ! forget_managed_packages xcursor-comix; then
      warn "xcursor-comix was removed, but Awtarchy could not update its managed-package ledger."
      return 0
    fi
  fi
  log "Replaced retired xcursor-comix with Bibata."
}

migrate_lockscreen_retirement() {
  [[ "${AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED:-0}" == 1 ]] \
    || die "Lockscreen retirement requires an explicitly confirmed target."

  if array_contains hyprlock "${ARCH_CATALOG[@]}"; then
    die "Target runtime still requires Hyprlock; refusing package retirement."
  fi

  package_installed hyprlock || return 0
  local ownership_recorded=0
  managed_package hyprlock && ownership_recorded=1
  log "Removing retired Hyprlock package after Quickshell lockscreen cutover..."

  if ! as_root pacman -R --noconfirm hyprlock; then
    warn "Could not remove retired Hyprlock; leaving it installed for a later retry."
    return 0
  fi
  if package_installed hyprlock; then
    warn "hyprlock is still detected after package removal."
    return 0
  fi
  if (( ownership_recorded == 1 )); then
    if ! forget_managed_packages hyprlock; then
      warn "Hyprlock was removed, but Awtarchy could not update its managed-package ledger."
      return 0
    fi
  fi
  log "Removed retired Hyprlock package."
}

flatpak_scope() {
  local fs=""
  if have findmnt; then
    fs="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
  fi
  if [[ $fs == btrfs ]]; then printf '%s\n' system; else printf '%s\n' user; fi
}

install_flatpak_apps() {
  local scope="$1"
  shift
  local -a apps=("$@") cmd=()
  (( ${#apps[@]} )) || return 0

  if [[ $scope == user ]]; then
    cmd=(flatpak --user)
  else
    cmd=(as_root flatpak --system)
  fi

  if ! "${cmd[@]}" remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    "${cmd[@]}" remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  "${cmd[@]}" install -y flathub "${apps[@]}"
}

package_reconciliation_needs_action() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) && return 0
  (( ${#MISSING_REQUIRED[@]} > 0 )) && return 0
  (( ${#MISSING_ARCH[@]} > 0 )) && return 0
  (( ${#MISSING_AUR[@]} > 0 )) && return 0
  (( ${#MISSING_FLATPAK_IDS[@]} > 0 )) && return 0
  (( ${#RETIRED_MANAGED[@]} > 0 )) && return 0
  return 1
}

if (( NVIDIA_ROLLBACK_ONLY == 1 )); then
  if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && ${AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES:-0} == 1 ]]; then
    apply_nvidia_rollback 1
  else
    [[ -r /dev/tty && -w /dev/tty ]] || die "NVIDIA rollback requires an interactive terminal."
    apply_nvidia_rollback 0
  fi
  exit $?
fi

if (( PACMAN_RECOVERY_CHECK_ONLY == 1 )); then
  pacman_sync_db_preflight
  exit $?
fi

if (( PACMAN_RECOVERY_RUN_ONLY == 1 )); then
  pacman_recovery_run_command "${PACMAN_RECOVERY_RUN_ARGS[@]}"
  exit $?
fi

if (( NEEDS_ACTION_ONLY == 1 )); then
  pacman_sync_db_preflight || true
fi

collect_state

if (( NEEDS_ACTION_ONLY == 1 )); then
  if package_reconciliation_needs_action; then
    exit 10
  fi
  exit 0
fi

if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then
  apply_cheese_snapshot_replacement
  apply_bibata_cursor_replacement
  exit 0
fi

if (( MIGRATE_LOCKSCREEN_RETIREMENT_ONLY == 1 )); then
  migrate_lockscreen_retirement
  exit 0
fi

if (( REVIEW_ONLY == 1 )); then
  print_review
  exit 0
fi

[[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

print_review >/dev/tty
printf '\nOptional choices are listed first and start unchecked.\n' >/dev/tty
printf 'Missing default packages start selected; Space opts out.\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\n\n' >/dev/tty
confirm_yes_no 'Continue to package choices?' 1 || { log 'Package reconciliation canceled.'; exit 0; }

# Optional Arch packages are shown first and unchecked; missing defaults follow selected.
declare -a arch_labels=()
declare -a arch_values=()
declare -a arch_flags=()
declare -a selected_arch=()
for pkg in "${MISSING_OPTIONAL_ARCH[@]}"; do
  arch_labels+=("${pkg} (optional)")
  arch_values+=("$pkg")
  arch_flags+=(0)
done
for pkg in "${MISSING_ARCH[@]}"; do
  arch_labels+=("$pkg")
  arch_values+=("$pkg")
  arch_flags+=(1)
done
if (( ${#arch_labels[@]} )); then
  multi_select 'Arch packages to install' arch_labels arch_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values arch_values arch_flags selected_arch

# Optional AUR packages are shown first and unchecked; missing defaults follow selected.
declare -a aur_labels=()
declare -a aur_values=()
declare -a aur_flags=()
declare -a selected_aur=()
for pkg in "${MISSING_OPTIONAL_AUR[@]}"; do
  aur_labels+=("${pkg} (optional)")
  aur_values+=("$pkg")
  aur_flags+=(0)
done
for pkg in "${MISSING_AUR[@]}"; do
  aur_labels+=("$pkg")
  aur_values+=("$pkg")
  aur_flags+=(1)
done
if (( ${#aur_labels[@]} )); then
  multi_select 'AUR packages to install' aur_labels aur_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values aur_values aur_flags selected_aur

# Optional Flatpaks are shown first and unchecked; missing defaults follow selected.
declare -a flatpak_labels=()
declare -a flatpak_values=()
declare -a flatpak_flags=()
declare -a selected_flatpak=()
for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_OPTIONAL_FLATPAK_NAMES[$i]} (${MISSING_OPTIONAL_FLATPAK_IDS[$i]}) (optional)")
  flatpak_values+=("${MISSING_OPTIONAL_FLATPAK_IDS[$i]}")
  flatpak_flags+=(0)
done
for i in "${!MISSING_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_FLATPAK_NAMES[$i]} (${MISSING_FLATPAK_IDS[$i]})")
  flatpak_values+=("${MISSING_FLATPAK_IDS[$i]}")
  flatpak_flags+=(1)
done
if (( ${#flatpak_labels[@]} )); then
  multi_select 'Flatpak apps to install' flatpak_labels flatpak_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values flatpak_values flatpak_flags selected_flatpak

install_ly=0
enable_ly=0
choose_ly_action

# Retired packages: Awtarchy-owned defaults selected; unowned defaults kept.
declare -a retired_labels=()
declare -a retired_values=()
declare -a retired_flags=()
declare -a selected_retired=()
for pkg in "${RETIRED_MANAGED[@]}"; do
  retired_labels+=("${pkg} (Awtarchy-owned, replaced)")
  retired_values+=("$pkg")
  retired_flags+=(1)
done
for pkg in "${RETIRED_UNOWNED[@]}"; do
  retired_labels+=("${pkg} (not Awtarchy-owned, keep unless selected)")
  retired_values+=("$pkg")
  retired_flags+=(0)
done
if (( ${#retired_labels[@]} )); then
  multi_select 'Retired/replaced packages to remove' retired_labels retired_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values retired_values retired_flags selected_retired

if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then
  array_contains cheese "${selected_retired[@]}" || selected_retired+=(cheese)
fi

install_arch=("${MISSING_REQUIRED[@]}" "${selected_arch[@]}")
if (( CHEESE_REPLACEMENT_NEEDED == 1 )) && ! package_installed snapshot; then
  install_arch+=(snapshot)
fi
sort_unique_array install_arch
if (( install_ly == 1 )); then install_arch+=(ly); fi
if (( ${#selected_flatpak[@]} )) && ! have flatpak; then
  install_arch+=(flatpak)
fi
sort_unique_array install_arch

printf '\033[H\033[2J' >/dev/tty
printf '%s\n\n' 'Awtarchy package reconciliation plan' >/dev/tty
print_list 'Install from Arch repositories:' "${install_arch[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install from AUR:' "${selected_aur[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install Flatpak apps:' "${selected_flatpak[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Remove retired/replaced packages:' "${selected_retired[@]}" >/dev/tty
if (( enable_ly == 1 )); then printf '\nLy: enable ly@tty2.service and disable getty@tty2.service\n' >/dev/tty; fi
printf '\nNo current installed package will be removed merely because it was not selected; explicit replacements may be migrated.\n\n' >/dev/tty

if (( ${#install_arch[@]} == 0 && ${#selected_aur[@]} == 0 && ${#selected_flatpak[@]} == 0 && ${#selected_retired[@]} == 0 && enable_ly == 0 )); then
  log 'No package changes selected.'
  exit 0
fi

confirm_yes_no 'Apply this package plan?' 0 || { log 'Package reconciliation canceled.'; exit 0; }
recover_package_disk_headroom

if (( ${#install_arch[@]} )); then
  confirm_nvidia_system_upgrade || exit 0
  log "Installing Arch packages with a full system upgrade: ${install_arch[*]}"
  if ! pacman_install_with_recovery -Syu --needed --noconfirm "${install_arch[@]}"; then
    cleanup_nvidia_pending_snapshot
    NVIDIA_ROLLBACK_PENDING=""
    die "Arch package transaction failed."
  fi
  # Finalize/offer NVIDIA recovery before bookkeeping so a ledger failure cannot
  # strand a successful driver upgrade without its rollback point.
  nvidia_post_rc=0
  offer_nvidia_post_upgrade_choice || nvidia_post_rc=$?
  record_managed_packages "${install_arch[@]}"
  case "$nvidia_post_rc" in
    0) ;;
    20)
      log 'NVIDIA/kernel rollback completed; stopping package reconciliation so the system can be rebooted cleanly.'
      exit 0
      ;;
    *)
      exit "$nvidia_post_rc"
      ;;
  esac
fi

if (( enable_ly == 1 )); then
  have systemctl || die "Ly is installed but systemctl is unavailable for tty2 setup."
  as_root systemctl disable getty@tty2.service >/dev/null 2>&1 || true
  as_root systemctl enable ly@tty2.service
  log 'Ly enabled on tty2; getty@tty2 disabled.'
fi

if (( ${#selected_aur[@]} )); then
  log 'AUR build privilege isolation enabled; makepkg may request sudo independently.'
  if ensure_aur_scanner; then
    install_selected_aur_packages "${selected_aur[@]}"
  else
    warn 'aur-scanner is unavailable; recording selected AUR packages as failed and continuing with remaining package actions.'
    FAILED_AUR+=("${selected_aur[@]}")
  fi
fi

if (( ${#selected_flatpak[@]} )); then
  have flatpak || die "Flatpak installation was selected but flatpak is unavailable after package installation."
  scope="$(flatpak_scope)"
  log "Installing Flatpak apps in ${scope} scope: ${selected_flatpak[*]}"
  install_flatpak_apps "$scope" "${selected_flatpak[@]}"
fi

if (( ${#selected_retired[@]} )); then
  log "Removing selected retired packages: ${selected_retired[*]}"
  as_root pacman -R --noconfirm "${selected_retired[@]}"
  forget_managed_packages "${selected_retired[@]}"
fi

if (( ${#FAILED_AUR[@]} )); then
  sort_unique_array FAILED_AUR
  printf '\n'
  print_list 'AUR packages that could not be installed:' "${FAILED_AUR[@]}"
  warn 'AUR failures do not stop package reconciliation; all other selected package actions were still processed.'
  log 'Package reconciliation completed with AUR package failures.'
else
  log 'Package reconciliation complete.'
fi\t' read -r pkg old_version saved_current_version archive_name; do
    [[ -n "$pkg" && -n "$old_version" ]] || continue
    if [[ "$(package_version "$pkg" || true)" != "$old_version" ]]; then
      die "NVIDIA rollback verification failed for ${pkg}; expected ${old_version}."
    fi
  done <"$NVIDIA_ROLLBACK_DIR/changes.tsv"

  metadata_tmp="$(mktemp)"
  cat -- "$NVIDIA_ROLLBACK_DIR/metadata" >"$metadata_tmp"
  {
    printf 'restored_at=%s\n' "$(date -Iseconds)"
    printf 'status=restored\n'
  } >>"$metadata_tmp"
  if ! as_root install -m 0644 -- "$metadata_tmp" "$NVIDIA_ROLLBACK_DIR/metadata"; then
    rm -f -- "$metadata_tmp"
    die "NVIDIA packages were restored, but rollback metadata could not be updated."
  fi
  rm -f -- "$metadata_tmp"

  log 'NVIDIA/kernel rollback completed. Reboot before judging the restored driver.'
}

confirm_nvidia_system_upgrade() {
  local snapshot_rc=0
  local -a nvidia_packages=()

  mapfile -t nvidia_packages < <(installed_nvidia_package_names)
  (( ${#nvidia_packages[@]} )) || return 0

  printf '\nNVIDIA drivers are installed on this system.\n' >/dev/tty
  printf 'This package plan requires a full system upgrade, which may update the NVIDIA driver and kernel.\n' >/dev/tty
  printf 'Awtarchy will save the currently cached driver/kernel packages first so they can be restored later.\n\n' >/dev/tty
  printf 'Current NVIDIA packages:\n' >/dev/tty
  pacman -Q "${nvidia_packages[@]}" 2>/dev/null | sed 's/^/  /' >/dev/tty || true
  printf '\n' >/dev/tty

  confirm_yes_no 'Allow the full system upgrade, including any available NVIDIA update?' 0 \
    || { log 'Package reconciliation canceled before NVIDIA/system upgrade.'; return 1; }

  prepare_nvidia_rollback_snapshot || snapshot_rc=$?
  case "$snapshot_rc" in
    0)
      log 'Saved a complete pre-upgrade NVIDIA/kernel rollback snapshot.'
      ;;
    1)
      printf '\nAwtarchy could not cache every currently installed NVIDIA/kernel package.\n' >/dev/tty
      printf 'A one-command rollback may be unavailable if one of those uncached packages changes.\n' >/dev/tty
      confirm_yes_no 'Continue with the NVIDIA/system upgrade anyway?' 0 \
        || {
          cleanup_nvidia_pending_snapshot
          NVIDIA_ROLLBACK_PENDING=""
          log 'Package reconciliation canceled because a complete rollback point was unavailable.'
          return 1
        }
      ;;
    2)
      NVIDIA_ROLLBACK_PENDING=""
      ;;
    *)
      die 'Could not prepare the NVIDIA rollback point.'
      ;;
  esac
  return 0
}

offer_nvidia_post_upgrade_choice() {
  [[ -n "$NVIDIA_ROLLBACK_PENDING" ]] || return 0

  if ! finalize_nvidia_rollback_snapshot; then
    log 'NVIDIA/kernel package versions did not change during the system upgrade.'
    return 0
  fi

  printf '\n' >/dev/tty
  print_nvidia_rollback_changes
  printf '\n' >/dev/tty

  if (( NVIDIA_ROLLBACK_COMPLETE == 1 )); then
    printf 'Rollback point saved. If a problem appears after reboot, run: awtarchy nvidia-rollback\n' >/dev/tty
    printf 'Some NVIDIA problems only appear after reboot or when launching a game.\n' >/dev/tty
    if ! confirm_yes_no 'Keep the new NVIDIA/kernel versions for now?' 1; then
      apply_nvidia_rollback 1
      return 20
    fi
  else
    warn 'NVIDIA/kernel packages changed, but the saved rollback point is incomplete.'
    warn 'Awtarchy will not attempt an unsafe partial automatic rollback.'
  fi
}

choose_ly_action() {
  install_ly=0
  enable_ly=0

  case "$LY_STATUS" in
    'not installed')
      if confirm_yes_no 'Install and enable Ly on tty2?' 0; then
        install_ly=1
        enable_ly=1
      fi
      ;;
    'installed, not enabled on tty2')
      if confirm_yes_no 'Enable installed Ly on tty2?' 0; then
        enable_ly=1
      fi
      ;;
    'installed and enabled on tty2')
      printf '\nLy is already installed and enabled on tty2; leaving it unchanged.\n' >/dev/tty
      ;;
    *)
      printf '\nLy state is %s; leaving it unchanged.\n' "$LY_STATUS" >/dev/tty
      ;;
  esac
}

selected_values() {
  local values_name="$1" flags_name="$2" output_name="$3"
  local -n values="$values_name"
  local -n flags="$flags_name"
  local -n output="$output_name"
  local i
  output=()
  for i in "${!values[@]}"; do
    (( flags[i] == 1 )) && output+=("${values[$i]}")
  done
}

root_free_mib() {
  local available_kib=""
  available_kib="$(/usr/bin/df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ $available_kib =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$(( available_kib / 1024 ))"
}

recover_package_disk_headroom() {
  local preferred_mib="${AWTARCHY_UPDATE_PREFERRED_FREE_MIB:-4096}"
  local required_mib="${AWTARCHY_UPDATE_REQUIRED_FREE_MIB:-1024}"
  local free_mib="" paccache_bin=""

  [[ $preferred_mib =~ ^[0-9]+$ && $required_mib =~ ^[0-9]+$ ]] \
    || die "Invalid update disk-space threshold override."
  (( preferred_mib >= required_mib )) \
    || die "Preferred update disk-space threshold cannot be below the required threshold."

  free_mib="$(root_free_mib)" \
    || die "Could not determine free space on the root filesystem."
  (( free_mib >= preferred_mib )) && return 0

  for paccache_bin in /usr/bin/paccache /usr/sbin/paccache; do
    [[ -x $paccache_bin ]] && break
    paccache_bin=""
  done

  if [[ -n $paccache_bin ]]; then
    log "Root filesystem has ${free_mib} MiB free; pruning old pacman cache entries while keeping two package versions..."
    if ! as_root "$paccache_bin" -rk2; then
      die "Automatic pacman cache pruning failed."
    fi
    free_mib="$(root_free_mib)" \
      || die "Could not re-check free space after pacman cache pruning."
  fi

  (( free_mib >= required_mib )) \
    || die "Root filesystem has only ${free_mib} MiB free; at least ${required_mib} MiB is required before continuing package installation."

  if (( free_mib < preferred_mib )); then
    warn "Root filesystem has ${free_mib} MiB free; continuing above the ${required_mib} MiB hard minimum."
  fi
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -- "$@"
  fi
}

pacman_recovery_supported_runtime() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    return 0
  fi
  [[ $(command -v pacman 2>/dev/null || true) == /usr/bin/pacman && -x /usr/bin/pacman ]]
}

pacman_recovery_configure() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    PACMAN_RECOVERY_PACMAN="${AWTARCHY_PACMAN_BIN:?test mode requires AWTARCHY_PACMAN_BIN}"
    PACMAN_RECOVERY_CONF="${AWTARCHY_PACMAN_CONF:?test mode requires AWTARCHY_PACMAN_CONF}"
    PACMAN_RECOVERY_SYNC_DIR="${AWTARCHY_PACMAN_SYNC_DIR:?test mode requires AWTARCHY_PACMAN_SYNC_DIR}"
    PACMAN_RECOVERY_CACHY_RATE="${AWTARCHY_CACHY_RATE_BIN:-/nonexistent/cachyos-rate-mirrors}"
    PACMAN_RECOVERY_REFLECTOR="${AWTARCHY_REFLECTOR_BIN:-/nonexistent/reflector}"
    PACMAN_RECOVERY_SKIP_MIRROR_REFRESH="${AWTARCHY_SKIP_MIRROR_REFRESH:-0}"
  else
    PACMAN_RECOVERY_PACMAN=/usr/bin/pacman
    PACMAN_RECOVERY_CONF=/etc/pacman.conf
    PACMAN_RECOVERY_SYNC_DIR=/var/lib/pacman/sync
    PACMAN_RECOVERY_CACHY_RATE=/usr/bin/cachyos-rate-mirrors
    PACMAN_RECOVERY_REFLECTOR=/usr/bin/reflector
    PACMAN_RECOVERY_SKIP_MIRROR_REFRESH=0
  fi

  [[ -x $PACMAN_RECOVERY_PACMAN ]] \
    || { warn "Pacman recovery binary is unavailable: ${PACMAN_RECOVERY_PACMAN}"; return 1; }
  [[ -r $PACMAN_RECOVERY_CONF ]] \
    || { warn "Pacman recovery configuration is unavailable: ${PACMAN_RECOVERY_CONF}"; return 1; }
}

pacman_recovery_as_root() {
  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
    "$@"
  else
    as_root "$@"
  fi
}

pacman_recovery_run_capture() {
  local root_mode="$1" error_file="$2"
  shift 2
  local rc=0

  : >"$error_file"
  if [[ $root_mode == root ]]; then
    if pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" "$@" 2>"$error_file"; then
      rc=0
    else
      rc=$?
    fi
  else
    if "$PACMAN_RECOVERY_PACMAN" "$@" 2>"$error_file"; then
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

pacman_recovery_parse_repos() {
  local error_file="$1" line
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

pacman_recovery_repo_is_cachyos() {
  [[ $1 == cachyos || $1 == cachyos-* ]]
}

pacman_recovery_repo_is_arch() {
  [[ $1 =~ ^(core|extra|multilib)(-testing|-staging)?$ ]]
}

pacman_recovery_repo_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

pacman_recovery_write_config_without_repos() {
  local destination="$1"
  shift
  local -a blocked=("$@")
  local line section="" skip=0

  : >"$destination"
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^\[([A-Za-z0-9@._+:-]+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"
      if pacman_recovery_repo_in_list "$section" "${blocked[@]}"; then
        skip=1
      else
        skip=0
      fi
    fi
    (( skip == 1 )) || printf '%s\n' "$line" >>"$destination"
  done <"$PACMAN_RECOVERY_CONF"
}

pacman_recovery_bootstrap_tool() {
  local kind="$1"
  shift
  local -a repos=("$@")
  local tmp_conf

  tmp_conf="$(mktemp)"
  pacman_recovery_write_config_without_repos "$tmp_conf" "${repos[@]}"

  case "$kind" in
    cachyos)
      log "CachyOS mirror tool is missing; bootstrapping rate-mirrors and cachyos-rate-mirrors without the broken repository."
      if ! pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" \
        --config "$tmp_conf" -S --needed --noconfirm rate-mirrors cachyos-rate-mirrors; then
        rm -f -- "$tmp_conf"
        warn "Could not bootstrap cachyos-rate-mirrors; continuing with targeted database resync only."
        return 1
      fi
      ;;
    arch)
      log "Arch mirror tool is missing; trying to bootstrap reflector without the broken repository."
      if ! pacman_recovery_as_root "$PACMAN_RECOVERY_PACMAN" \
        --config "$tmp_conf" -S --needed --noconfirm reflector; then
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
}

pacman_recovery_refresh_mirrors() {
  local -a repos=("$@")
  local repo need_cachy=0 need_arch=0

  [[ $PACMAN_RECOVERY_SKIP_MIRROR_REFRESH == 1 ]] && return 0

  for repo in "${repos[@]}"; do
    pacman_recovery_repo_is_cachyos "$repo" && need_cachy=1
    pacman_recovery_repo_is_arch "$repo" && need_arch=1
  done

  if (( need_cachy == 1 )); then
    if [[ ! -x $PACMAN_RECOVERY_CACHY_RATE ]]; then
      pacman_recovery_bootstrap_tool cachyos "${repos[@]}" || true
    fi
    if [[ -x $PACMAN_RECOVERY_CACHY_RATE ]]; then
      log "Refreshing CachyOS mirrors before retrying pacman..."
      pacman_recovery_as_root "$PACMAN_RECOVERY_CACHY_RATE" \
        || warn "CachyOS mirror refresh failed; continuing with targeted database resync only."
    fi
  fi

  if (( need_arch == 1 )); then
    if [[ ! -x $PACMAN_RECOVERY_REFLECTOR ]]; then
      pacman_recovery_bootstrap_tool arch "${repos[@]}" || true
    fi
    if [[ -x $PACMAN_RECOVERY_REFLECTOR ]]; then
      log "Refreshing standard Arch mirrors before retrying pacman..."
      pacman_recovery_as_root "$PACMAN_RECOVERY_REFLECTOR" \
        --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist \
        || warn "Arch mirror refresh failed; continuing with targeted database resync only."
    fi
  fi
}

pacman_recovery_confirm() {
  local answer=""
  local -a repos=("$@")

  if [[ ${AWTARCHY_PACMAN_RECOVERY_TEST_MODE:-0} == 1 ]]; then
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
    *)
      printf 'Pacman repository repair skipped.\n' >/dev/tty
      return 1
      ;;
  esac
}

pacman_recovery_clear_sync_databases() {
  local repo
  for repo in "$@"; do
    pacman_recovery_as_root rm -f -- \
      "${PACMAN_RECOVERY_SYNC_DIR}/${repo}.db" \
      "${PACMAN_RECOVERY_SYNC_DIR}/${repo}.db.sig"
  done
}

pacman_recovery_repair() {
  local -a repos=("$@")
  local error_file rc=0

  (( ${#repos[@]} > 0 )) || return 1
  pacman_recovery_confirm "${repos[@]}" || return 1

  pacman_recovery_refresh_mirrors "${repos[@]}"
  pacman_recovery_clear_sync_databases "${repos[@]}"

  error_file="$(mktemp)"
  log "Forcing a fresh pacman database sync..."
  if pacman_recovery_run_capture root "$error_file" -Syy; then
    rm -f -- "$error_file"
    log "Pacman repository database recovery completed."
    return 0
  else
    rc=$?
  fi
  rm -f -- "$error_file"
  warn "Pacman database resync still failed; no signature checks were bypassed and no keyring changes were made."
  return "$rc"
}

pacman_sync_db_preflight() {
  local error_file rc=0
  local -a repos=()

  pacman_recovery_supported_runtime || return 0
  pacman_recovery_configure || return 1

  error_file="$(mktemp)"
  if pacman_recovery_run_capture user "$error_file" -Slq >/dev/null; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(pacman_recovery_parse_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"
  pacman_recovery_repair "${repos[@]}"
}

pacman_recovery_run_command() {
  local error_file rc=0 retry_rc=0
  local -a repos=() args=("$@")

  pacman_recovery_supported_runtime || {
    as_root pacman "${args[@]}"
    return $?
  }
  pacman_recovery_configure || return 1

  error_file="$(mktemp)"
  if pacman_recovery_run_capture root "$error_file" "${args[@]}"; then
    rm -f -- "$error_file"
    return 0
  else
    rc=$?
  fi

  mapfile -t repos < <(pacman_recovery_parse_repos "$error_file" || true)
  rm -f -- "$error_file"
  (( ${#repos[@]} > 0 )) || return "$rc"

  if ! pacman_recovery_repair "${repos[@]}"; then
    return "$rc"
  fi

  error_file="$(mktemp)"
  log "Retrying the original pacman command once..."
  if pacman_recovery_run_capture root "$error_file" "${args[@]}"; then
    retry_rc=0
  else
    retry_rc=$?
  fi
  rm -f -- "$error_file"
  return "$retry_rc"
}

pacman_install_with_recovery() {
  pacman_recovery_run_command "$@"
}

ensure_aur_scanner() {
  if [[ -x "$AUR_SCAN_BIN" ]] && "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$AUR_SCAN_BIN" != /usr/bin/aur-scan ]]; then
    warn "Configured aur-scan test binary is unavailable: ${AUR_SCAN_BIN}"
    return 1
  fi

  if [[ ! -x /usr/bin/yay ]] || ! /usr/bin/yay --version >/dev/null 2>&1; then
    warn "aur-scanner is missing and a usable /usr/bin/yay is unavailable for the one-time bootstrap."
    return 1
  fi

  log "Installing stable aur-scanner through yay for the one-time bootstrap..."
  if ! /usr/bin/yay -S --noconfirm --pgpfetch aur-scanner; then
    warn "Failed to bootstrap stable aur-scanner."
    return 1
  fi

  if [[ ! -x /usr/bin/aur-scan ]] || ! /usr/bin/aur-scan --version >/dev/null 2>&1; then
    warn "aur-scanner installed without a usable /usr/bin/aur-scan."
    return 1
  fi

  AUR_SCAN_BIN="/usr/bin/aur-scan"
}

install_selected_aur_packages() {
  local pkg

  for pkg in "$@"; do
    if aur_package_satisfied "$pkg"; then
      log "${pkg} or an equivalent installation is already present; skipping."
      continue
    fi

    if (( EUID != 0 )); then
      sudo -k
    fi
    log "Installing AUR package through upstream aur-scanner: ${pkg}"
    if ! "$AUR_SCAN_BIN" install "$pkg" --noconfirm; then
      warn "AUR package failed: ${pkg}. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! aur_package_satisfied "$pkg"; then
      warn "aur-scanner returned success but ${pkg} is still not detected. Continuing with remaining package actions."
      FAILED_AUR+=("$pkg")
      continue
    fi

    if ! record_managed_packages "$pkg"; then
      warn "${pkg} installed, but Awtarchy could not update its managed-package ledger."
    fi
  done

  return 0
}

record_managed_packages() {
  local -a add=("$@")
  local tmp pkg
  (( ${#add[@]} )) || return 0
  tmp="$(mktemp)"
  if [[ -r "$MANAGED_PACKAGES_FILE" ]]; then
    cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  else
    : >"$tmp"
  fi
  for pkg in "${add[@]}"; do
    package_installed "$pkg" && printf '%s\n' "$pkg" >>"$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -d -m 0755 -- "$(dirname -- "$MANAGED_PACKAGES_FILE")"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

forget_managed_packages() {
  local -a remove=("$@")
  local tmp pkg
  (( ${#remove[@]} )) || return 0
  [[ -r "$MANAGED_PACKAGES_FILE" ]] || return 0
  tmp="$(mktemp)"
  cat -- "$MANAGED_PACKAGES_FILE" >"$tmp"
  for pkg in "${remove[@]}"; do
    sed -i "/^$(printf '%s' "$pkg" | sed 's/[][\\.^$*+?{}|()]/\\&/g')$/d" "$tmp"
  done
  LC_ALL=C sort -u -o "$tmp" "$tmp"
  as_root install -m 0644 -- "$tmp" "$MANAGED_PACKAGES_FILE"
  rm -f -- "$tmp"
}

apply_cheese_snapshot_replacement() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) || return 0

  log "Replacing retired Cheese camera app with Snapshot..."
  if ! package_installed snapshot; then
    pacman_install_with_recovery -S --needed --noconfirm snapshot
  fi
  record_managed_packages snapshot
  as_root pacman -R --noconfirm cheese
  forget_managed_packages cheese
  CHEESE_REPLACEMENT_NEEDED=0
  log "Replaced Cheese with Snapshot."
}

apply_bibata_cursor_replacement() {
  array_contains bibata-cursor-theme-bin "${AUR_CATALOG[@]}" || return 0

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    if [[ ! -x "$AUR_SCAN_BIN" ]] || ! "$AUR_SCAN_BIN" --version >/dev/null 2>&1; then
      warn "Bibata cursor migration requires a usable aur-scan; leaving the existing cursor package untouched."
      return 0
    fi
    log "Installing Bibata cursor theme through upstream aur-scanner..."
    install_selected_aur_packages bibata-cursor-theme-bin
  fi

  if ! aur_package_satisfied bibata-cursor-theme-bin; then
    warn "Bibata cursor theme is not installed; leaving the existing cursor package untouched."
    return 0
  fi

  package_installed xcursor-comix || return 0
  local ownership_recorded=0
  managed_package xcursor-comix && ownership_recorded=1
  log "Removing retired xcursor-comix package after Bibata replacement..."

  if ! as_root pacman -R --noconfirm xcursor-comix; then
    warn "Could not remove retired xcursor-comix; leaving it installed for a later retry."
    return 0
  fi
  if package_installed xcursor-comix; then
    warn "xcursor-comix is still detected after package removal."
    return 0
  fi
  if (( ownership_recorded == 1 )); then
    if ! forget_managed_packages xcursor-comix; then
      warn "xcursor-comix was removed, but Awtarchy could not update its managed-package ledger."
      return 0
    fi
  fi
  log "Replaced retired xcursor-comix with Bibata."
}

migrate_lockscreen_retirement() {
  [[ "${AWTARCHY_LOCKSCREEN_RETIRE_CONFIRMED:-0}" == 1 ]] \
    || die "Lockscreen retirement requires an explicitly confirmed target."

  if array_contains hyprlock "${ARCH_CATALOG[@]}"; then
    die "Target runtime still requires Hyprlock; refusing package retirement."
  fi

  package_installed hyprlock || return 0
  local ownership_recorded=0
  managed_package hyprlock && ownership_recorded=1
  log "Removing retired Hyprlock package after Quickshell lockscreen cutover..."

  if ! as_root pacman -R --noconfirm hyprlock; then
    warn "Could not remove retired Hyprlock; leaving it installed for a later retry."
    return 0
  fi
  if package_installed hyprlock; then
    warn "hyprlock is still detected after package removal."
    return 0
  fi
  if (( ownership_recorded == 1 )); then
    if ! forget_managed_packages hyprlock; then
      warn "Hyprlock was removed, but Awtarchy could not update its managed-package ledger."
      return 0
    fi
  fi
  log "Removed retired Hyprlock package."
}

flatpak_scope() {
  local fs=""
  if have findmnt; then
    fs="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
  fi
  if [[ $fs == btrfs ]]; then printf '%s\n' system; else printf '%s\n' user; fi
}

install_flatpak_apps() {
  local scope="$1"
  shift
  local -a apps=("$@") cmd=()
  (( ${#apps[@]} )) || return 0

  if [[ $scope == user ]]; then
    cmd=(flatpak --user)
  else
    cmd=(as_root flatpak --system)
  fi

  if ! "${cmd[@]}" remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    "${cmd[@]}" remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  "${cmd[@]}" install -y flathub "${apps[@]}"
}

package_reconciliation_needs_action() {
  (( CHEESE_REPLACEMENT_NEEDED == 1 )) && return 0
  (( ${#MISSING_REQUIRED[@]} > 0 )) && return 0
  (( ${#MISSING_ARCH[@]} > 0 )) && return 0
  (( ${#MISSING_AUR[@]} > 0 )) && return 0
  (( ${#MISSING_FLATPAK_IDS[@]} > 0 )) && return 0
  (( ${#RETIRED_MANAGED[@]} > 0 )) && return 0
  return 1
}

if (( NVIDIA_ROLLBACK_ONLY == 1 )); then
  if [[ ${AWTARCHY_TEST_MODE:-0} == 1 && ${AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES:-0} == 1 ]]; then
    apply_nvidia_rollback 1
  else
    [[ -r /dev/tty && -w /dev/tty ]] || die "NVIDIA rollback requires an interactive terminal."
    apply_nvidia_rollback 0
  fi
  exit $?
fi

if (( PACMAN_RECOVERY_CHECK_ONLY == 1 )); then
  pacman_sync_db_preflight
  exit $?
fi

if (( PACMAN_RECOVERY_RUN_ONLY == 1 )); then
  pacman_recovery_run_command "${PACMAN_RECOVERY_RUN_ARGS[@]}"
  exit $?
fi

if (( NEEDS_ACTION_ONLY == 1 )); then
  pacman_sync_db_preflight || true
fi

collect_state

if (( NEEDS_ACTION_ONLY == 1 )); then
  if package_reconciliation_needs_action; then
    exit 10
  fi
  exit 0
fi

if (( MIGRATE_REPLACEMENTS_ONLY == 1 )); then
  apply_cheese_snapshot_replacement
  apply_bibata_cursor_replacement
  exit 0
fi

if (( MIGRATE_LOCKSCREEN_RETIREMENT_ONLY == 1 )); then
  migrate_lockscreen_retirement
  exit 0
fi

if (( REVIEW_ONLY == 1 )); then
  print_review
  exit 0
fi

[[ -r /dev/tty && -w /dev/tty ]] || die "Interactive package reconciliation requires a terminal."

print_review >/dev/tty
printf '\nOptional choices are listed first and start unchecked.\n' >/dev/tty
printf 'Missing default packages start selected; Space opts out.\n' >/dev/tty
printf 'Installed current packages are preserved even when not selected here.\n\n' >/dev/tty
confirm_yes_no 'Continue to package choices?' 1 || { log 'Package reconciliation canceled.'; exit 0; }

# Optional Arch packages are shown first and unchecked; missing defaults follow selected.
declare -a arch_labels=()
declare -a arch_values=()
declare -a arch_flags=()
declare -a selected_arch=()
for pkg in "${MISSING_OPTIONAL_ARCH[@]}"; do
  arch_labels+=("${pkg} (optional)")
  arch_values+=("$pkg")
  arch_flags+=(0)
done
for pkg in "${MISSING_ARCH[@]}"; do
  arch_labels+=("$pkg")
  arch_values+=("$pkg")
  arch_flags+=(1)
done
if (( ${#arch_labels[@]} )); then
  multi_select 'Arch packages to install' arch_labels arch_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values arch_values arch_flags selected_arch

# Optional AUR packages are shown first and unchecked; missing defaults follow selected.
declare -a aur_labels=()
declare -a aur_values=()
declare -a aur_flags=()
declare -a selected_aur=()
for pkg in "${MISSING_OPTIONAL_AUR[@]}"; do
  aur_labels+=("${pkg} (optional)")
  aur_values+=("$pkg")
  aur_flags+=(0)
done
for pkg in "${MISSING_AUR[@]}"; do
  aur_labels+=("$pkg")
  aur_values+=("$pkg")
  aur_flags+=(1)
done
if (( ${#aur_labels[@]} )); then
  multi_select 'AUR packages to install' aur_labels aur_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values aur_values aur_flags selected_aur

# Optional Flatpaks are shown first and unchecked; missing defaults follow selected.
declare -a flatpak_labels=()
declare -a flatpak_values=()
declare -a flatpak_flags=()
declare -a selected_flatpak=()
for i in "${!MISSING_OPTIONAL_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_OPTIONAL_FLATPAK_NAMES[$i]} (${MISSING_OPTIONAL_FLATPAK_IDS[$i]}) (optional)")
  flatpak_values+=("${MISSING_OPTIONAL_FLATPAK_IDS[$i]}")
  flatpak_flags+=(0)
done
for i in "${!MISSING_FLATPAK_IDS[@]}"; do
  flatpak_labels+=("${MISSING_FLATPAK_NAMES[$i]} (${MISSING_FLATPAK_IDS[$i]})")
  flatpak_values+=("${MISSING_FLATPAK_IDS[$i]}")
  flatpak_flags+=(1)
done
if (( ${#flatpak_labels[@]} )); then
  multi_select 'Flatpak apps to install' flatpak_labels flatpak_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values flatpak_values flatpak_flags selected_flatpak

install_ly=0
enable_ly=0
choose_ly_action

# Retired packages: Awtarchy-owned defaults selected; unowned defaults kept.
declare -a retired_labels=()
declare -a retired_values=()
declare -a retired_flags=()
declare -a selected_retired=()
for pkg in "${RETIRED_MANAGED[@]}"; do
  retired_labels+=("${pkg} (Awtarchy-owned, replaced)")
  retired_values+=("$pkg")
  retired_flags+=(1)
done
for pkg in "${RETIRED_UNOWNED[@]}"; do
  retired_labels+=("${pkg} (not Awtarchy-owned, keep unless selected)")
  retired_values+=("$pkg")
  retired_flags+=(0)
done
if (( ${#retired_labels[@]} )); then
  multi_select 'Retired/replaced packages to remove' retired_labels retired_flags \
    || { log 'Package reconciliation canceled.'; exit 0; }
fi
selected_values retired_values retired_flags selected_retired

if (( CHEESE_REPLACEMENT_NEEDED == 1 )); then
  array_contains cheese "${selected_retired[@]}" || selected_retired+=(cheese)
fi

install_arch=("${MISSING_REQUIRED[@]}" "${selected_arch[@]}")
if (( CHEESE_REPLACEMENT_NEEDED == 1 )) && ! package_installed snapshot; then
  install_arch+=(snapshot)
fi
sort_unique_array install_arch
if (( install_ly == 1 )); then install_arch+=(ly); fi
if (( ${#selected_flatpak[@]} )) && ! have flatpak; then
  install_arch+=(flatpak)
fi
sort_unique_array install_arch

printf '\033[H\033[2J' >/dev/tty
printf '%s\n\n' 'Awtarchy package reconciliation plan' >/dev/tty
print_list 'Install from Arch repositories:' "${install_arch[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install from AUR:' "${selected_aur[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Install Flatpak apps:' "${selected_flatpak[@]}" >/dev/tty
printf '\n' >/dev/tty
print_list 'Remove retired/replaced packages:' "${selected_retired[@]}" >/dev/tty
if (( enable_ly == 1 )); then printf '\nLy: enable ly@tty2.service and disable getty@tty2.service\n' >/dev/tty; fi
printf '\nNo current installed package will be removed merely because it was not selected; explicit replacements may be migrated.\n\n' >/dev/tty

if (( ${#install_arch[@]} == 0 && ${#selected_aur[@]} == 0 && ${#selected_flatpak[@]} == 0 && ${#selected_retired[@]} == 0 && enable_ly == 0 )); then
  log 'No package changes selected.'
  exit 0
fi

confirm_yes_no 'Apply this package plan?' 0 || { log 'Package reconciliation canceled.'; exit 0; }
recover_package_disk_headroom

if (( ${#install_arch[@]} )); then
  confirm_nvidia_system_upgrade || exit 0
  log "Installing Arch packages with a full system upgrade: ${install_arch[*]}"
  if ! pacman_install_with_recovery -Syu --needed --noconfirm "${install_arch[@]}"; then
    cleanup_nvidia_pending_snapshot
    NVIDIA_ROLLBACK_PENDING=""
    die "Arch package transaction failed."
  fi
  # Finalize/offer NVIDIA recovery before bookkeeping so a ledger failure cannot
  # strand a successful driver upgrade without its rollback point.
  nvidia_post_rc=0
  offer_nvidia_post_upgrade_choice || nvidia_post_rc=$?
  record_managed_packages "${install_arch[@]}"
  case "$nvidia_post_rc" in
    0) ;;
    20)
      log 'NVIDIA/kernel rollback completed; stopping package reconciliation so the system can be rebooted cleanly.'
      exit 0
      ;;
    *)
      exit "$nvidia_post_rc"
      ;;
  esac
fi

if (( enable_ly == 1 )); then
  have systemctl || die "Ly is installed but systemctl is unavailable for tty2 setup."
  as_root systemctl disable getty@tty2.service >/dev/null 2>&1 || true
  as_root systemctl enable ly@tty2.service
  log 'Ly enabled on tty2; getty@tty2 disabled.'
fi

if (( ${#selected_aur[@]} )); then
  log 'AUR build privilege isolation enabled; makepkg may request sudo independently.'
  if ensure_aur_scanner; then
    install_selected_aur_packages "${selected_aur[@]}"
  else
    warn 'aur-scanner is unavailable; recording selected AUR packages as failed and continuing with remaining package actions.'
    FAILED_AUR+=("${selected_aur[@]}")
  fi
fi

if (( ${#selected_flatpak[@]} )); then
  have flatpak || die "Flatpak installation was selected but flatpak is unavailable after package installation."
  scope="$(flatpak_scope)"
  log "Installing Flatpak apps in ${scope} scope: ${selected_flatpak[*]}"
  install_flatpak_apps "$scope" "${selected_flatpak[@]}"
fi

if (( ${#selected_retired[@]} )); then
  log "Removing selected retired packages: ${selected_retired[*]}"
  as_root pacman -R --noconfirm "${selected_retired[@]}"
  forget_managed_packages "${selected_retired[@]}"
fi

if (( ${#FAILED_AUR[@]} )); then
  sort_unique_array FAILED_AUR
  printf '\n'
  print_list 'AUR packages that could not be installed:' "${FAILED_AUR[@]}"
  warn 'AUR failures do not stop package reconciliation; all other selected package actions were still processed.'
  log 'Package reconciliation completed with AUR package failures.'
else
  log 'Package reconciliation complete.'
fi