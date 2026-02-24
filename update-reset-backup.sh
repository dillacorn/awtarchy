#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

REPO_OWNER="dillacorn"
REPO_NAME="awtarchy"

LOG_PREFIX="[awtarchy-update]"

log()  { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

ts() { date -Iseconds; }
stamp() { date +%Y%m%d-%H%M%S; }

TARGET_USER=""
HOME_DIR=""
BACKUPS=()

run_target() {
  if [[ "${EUID}" -eq 0 ]]; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" -H -- "$@"
    else
      die "Running as root but neither runuser nor sudo is available to run commands as ${TARGET_USER}"
    fi
  else
    "$@"
  fi
}

init_target_user() {
  if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  else
    TARGET_USER="${USER}"
  fi

  HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
  [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "Could not resolve HOME for user: ${TARGET_USER}"
}

curl_headers() {
  CURL_ARGS=(
    -fsSL
    --retry 3
    --retry-delay 1
    -H "User-Agent: awtarchy-update"
  )

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    CURL_ARGS+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
}

fetch_latest_release_tag() {
  local api="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  local json

  json="$(curl "${CURL_ARGS[@]}" -H "Accept: application/vnd.github+json" "$api")" || die "Failed to query GitHub latest release API"

  python3 - <<'PY' "$json"
import json, sys
j = json.loads(sys.argv[1])
tag = (j.get("tag_name") or "").strip()
if not tag:
  raise SystemExit(2)
print(tag)
PY
}

urlencode_path_segment() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
# Keep "/" unescaped (rare but possible in tags), encode everything else that could break URLs (like '#').
print(quote(sys.argv[1], safe="/-._~"))
PY
}

download_release_tarball() {
  local tag="$1"
  local out="$2"
  local tag_enc
  tag_enc="$(urlencode_path_segment "$tag")"

  local url="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/${tag_enc}.tar.gz"
  curl "${CURL_ARGS[@]}" -L -o "$out" "$url" || die "Failed to download release tarball: $url"
}

tar_topdir() {
  local tgz="$1"
  local top
  top="$(tar -tzf "$tgz" | head -n 1 | cut -d/ -f1)"
  [[ -n "$top" ]] || die "Could not determine tarball top directory"
  printf '%s\n' "$top"
}

make_backup_file() {
  local dest="$1"
  [[ -e "$dest" || -L "$dest" ]] || return 0

  local b="${dest}.backup"
  if [[ -e "$b" || -L "$b" ]]; then
    b="${dest}.backup.$(stamp)"
  fi
  mkdir -p -- "$(dirname "$b")"
  cp -a -- "$dest" "$b"
  BACKUPS+=("$b")
}

same_symlink_target() {
  local a="$1" b="$2"
  [[ -L "$a" && -L "$b" ]] || return 1
  [[ "$(readlink "$a")" == "$(readlink "$b")" ]]
}

files_equal() {
  local src="$1" dest="$2"

  if [[ -L "$src" || -L "$dest" ]]; then
    same_symlink_target "$src" "$dest"
    return $?
  fi

  [[ -f "$src" && -f "$dest" ]] || return 1
  cmp -s -- "$src" "$dest"
}

atomic_copy() {
  local src="$1" dest="$2"

  if [[ -f "$src" && ! -L "$src" && ! -s "$src" ]]; then
    warn "Skipping empty upstream file (refusing to overwrite): $dest"
    return 0
  fi

  mkdir -p -- "$(dirname "$dest")"

  local tmp
  tmp="$(mktemp --tmpdir="$(dirname "$dest")" ".awtarchy.tmp.XXXXXX")"
  rm -f -- "$tmp" 2>/dev/null || true

  cp -a --no-preserve=ownership -- "$src" "$tmp"

  if [[ "${EUID}" -eq 0 ]]; then
    chown -h "${TARGET_USER}:${TARGET_USER}" "$tmp" 2>/dev/null || true
  fi

  mv -Tf -- "$tmp" "$dest"
}

deploy_file() {
  local src="$1" dest="$2"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if files_equal "$src" "$dest"; then
      return 0
    fi
    make_backup_file "$dest"
    if [[ -d "$dest" && ! -d "$src" ]]; then
      rm -rf -- "$dest"
    fi
  fi

  atomic_copy "$src" "$dest"
}

deploy_tree() {
  local src_root="$1" dest_root="$2"

  [[ -d "$src_root" ]] || die "Missing upstream directory: $src_root"
  mkdir -p -- "$dest_root"

  while IFS= read -r -d '' d; do
    local rel="${d#"$src_root"/}"
    mkdir -p -- "${dest_root}/${rel}"
  done < <(find "$src_root" -mindepth 1 -type d -print0)

  while IFS= read -r -d '' f; do
    local rel="${f#"$src_root"/}"
    deploy_file "$f" "${dest_root}/${rel}"
  done < <(find "$src_root" -mindepth 1 \( -type f -o -type l \) -print0)

  if [[ "${EUID}" -eq 0 ]]; then
    chown -R "${TARGET_USER}:${TARGET_USER}" "$dest_root" 2>/dev/null || true
  fi
}

fix_managed_perms() {
  local -a dirs=("$@")

  for d in "${dirs[@]}"; do
    local root="${HOME_DIR}/.config/${d}"
    [[ -d "$root" ]] || continue
    find "$root" -type d -exec chmod 755 {} + 2>/dev/null || true
    find "$root" -type f -exec chmod 644 {} + 2>/dev/null || true
  done

  [[ -d "${HOME_DIR}/.config/hypr/scripts" ]] && find "${HOME_DIR}/.config/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
  [[ -d "${HOME_DIR}/.config/hypr/themes" ]] && find "${HOME_DIR}/.config/hypr/themes" -type f -exec chmod +x {} + 2>/dev/null || true
  [[ -d "${HOME_DIR}/.config/waybar/scripts" ]] && find "${HOME_DIR}/.config/waybar/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
}

maybe_hyprctl_reload() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  run_target hyprctl reload >/dev/null 2>&1 || true
}

write_version_stamp() {
  local tag="$1"
  local dest="${HOME_DIR}/.cache/awtarchy/version"
  mkdir -p -- "$(dirname "$dest")"
  {
    printf '%s\n' "tag=${tag}"
    printf '%s\n' "updated_at=$(ts)"
  } >"$dest"
  if [[ "${EUID}" -eq 0 ]]; then
    chown "${TARGET_USER}:${TARGET_USER}" "$dest" 2>/dev/null || true
  fi
}

update_system_cursor_default() {
  [[ "${EUID}" -eq 0 ]] || return 0
  install -d -m 755 /usr/share/icons/default
  printf '%s\n' "[Icon Theme]" "Inherits=ComixCursors-White" | tee /usr/share/icons/default/index.theme >/dev/null
  chmod 644 /usr/share/icons/default/index.theme 2>/dev/null || true
}

is_interactive_tty() {
  [[ -t 0 && -t 1 ]]
}

ask_yes_no() {
  local prompt="$1"
  local ans=""
  if ! is_interactive_tty; then
    warn "Non-interactive shell detected; skipping prompt: ${prompt}"
    return 1
  fi

  while true; do
    read -r -p "${prompt} [y/n] " ans
    case "${ans}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf '%s\n' "Please answer y or n." ;;
    esac
  done
}

print_wrapped_list() {
  local -n _items_ref="$1"
  local prefix="${2:-  - }"
  local i
  for i in "${_items_ref[@]}"; do
    printf '%s%s\n' "${prefix}" "${i}"
  done
}

parse_bash_array_from_script() {
  local file="$1"
  local array_name="$2"
  local mode="$3" # plain | arch-groups

  python3 - "$file" "$array_name" "$mode" <<'PY'
import re
import shlex
import sys
from pathlib import Path

path, array_name, mode = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(path).read_text(encoding="utf-8")

m = re.search(rf'(?ms)^\s*(?:declare\s+-a\s+)?{re.escape(array_name)}=\(\s*(.*?)^\s*\)', text)
if not m:
    raise SystemExit(2)

body = m.group(1)

lex = shlex.shlex(body, posix=True)
lex.whitespace_split = True
lex.commenters = '#'
items = list(lex)

out = []
seen = set()

def emit(token: str):
    token = token.strip()
    if not token:
        return
    if token in seen:
        return
    seen.add(token)
    out.append(token)

if mode == "arch-groups":
    for entry in items:
        if ":" in entry:
            _, pkg_blob = entry.split(":", 1)
        else:
            pkg_blob = entry
        for pkg in pkg_blob.split():
            emit(pkg)
elif mode == "plain":
    for entry in items:
        emit(entry)
else:
    raise SystemExit(3)

sys.stdout.write("\n".join(out))
PY
}

pkg_installed_pacman() {
  local pkg="$1"
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qq "$pkg" >/dev/null 2>&1
}

flatpak_app_installed_any_scope() {
  local app_id="$1"
  command -v flatpak >/dev/null 2>&1 || return 1

  flatpak info --system "$app_id" >/dev/null 2>&1 && return 0
  run_target flatpak --user info "$app_id" >/dev/null 2>&1 && return 0
  flatpak info "$app_id" >/dev/null 2>&1 && return 0
  return 1
}

detect_repo_scripts_dir() {
  local downloaded_repo_dir="${1:-}"
  local self_dir="" pwd_dir=""

  self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  pwd_dir="$(pwd -P)"

  if [[ -d "${self_dir}/scripts" ]]; then
    printf '%s\n' "${self_dir}/scripts"
    return 0
  fi

  if [[ -d "${pwd_dir}/scripts" ]]; then
    printf '%s\n' "${pwd_dir}/scripts"
    return 0
  fi

  if [[ -n "${downloaded_repo_dir}" && -d "${downloaded_repo_dir}/scripts" ]]; then
    printf '%s\n' "${downloaded_repo_dir}/scripts"
    return 0
  fi

  return 1
}

detect_aur_helper() {
  if command -v yay >/dev/null 2>&1; then
    printf '%s\n' "yay"
    return 0
  fi
  if command -v paru >/dev/null 2>&1; then
    printf '%s\n' "paru"
    return 0
  fi

  local helper=""
  helper="$(run_target bash -lc 'if command -v yay >/dev/null 2>&1; then echo yay; elif command -v paru >/dev/null 2>&1; then echo paru; fi' 2>/dev/null || true)"
  if [[ -n "${helper}" ]]; then
    printf '%s\n' "${helper}"
    return 0
  fi
  return 1
}

flatpak_effective_install_scope() {
  if [[ "${EUID}" -ne 0 ]]; then
    printf '%s\n' "user"
    return 0
  fi
  local root_fs_type=""
  root_fs_type="$(df -T / | awk 'NR==2 {print $2}' 2>/dev/null || true)"
  if [[ "${root_fs_type}" == "btrfs" ]]; then
    printf '%s\n' "system"
  else
    printf '%s\n' "user"
  fi
}

ensure_flatpak_remote_for_scope() {
  local scope="$1"
  local remote_name="flathub"
  local remote_url="https://flathub.org/repo/flathub.flatpakrepo"

  if [[ "${scope}" == "user" ]]; then
    run_target flatpak --user remotes --columns=name | grep -Fxq "${remote_name}" \
      || run_target flatpak --user remote-add --if-not-exists "${remote_name}" "${remote_url}"
  else
    flatpak remotes --columns=name | grep -Fxq "${remote_name}" \
      || flatpak remote-add --if-not-exists "${remote_name}" "${remote_url}"
  fi
}

install_missing_arch_repo_packages() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  if ! command -v pacman >/dev/null 2>&1; then
    warn "pacman not found; cannot install Arch repo packages."
    return 1
  fi
  if [[ "${EUID}" -ne 0 ]]; then
    warn "Arch repo installs require root. Re-run update-reset-backup.sh with sudo to install missing packages."
    return 1
  fi

  log "Installing missing Arch repo packages (${#pkgs[@]}):"
  print_wrapped_list pkgs "  - "
  pacman -S --needed --noconfirm "${pkgs[@]}"
}

install_missing_aur_packages() {
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0

  local aur_helper=""
  if ! aur_helper="$(detect_aur_helper)"; then
    warn "No AUR helper found (yay/paru). Skipping AUR package installs."
    return 1
  fi

  log "Installing missing AUR packages with ${aur_helper} (${#pkgs[@]}):"
  print_wrapped_list pkgs "  - "
  run_target "${aur_helper}" -S --needed --noconfirm "${pkgs[@]}"
}

install_missing_flatpak_apps() {
  local -a app_ids=("$@")
  (( ${#app_ids[@]} )) || return 0

  if ! command -v flatpak >/dev/null 2>&1; then
    if [[ "${EUID}" -eq 0 ]]; then
      log "flatpak not found. Installing flatpak package first."
      pacman -S --needed --noconfirm flatpak
    else
      warn "flatpak is not installed and this script is not running as root. Skipping Flatpak app installs."
      return 1
    fi
  fi

  local scope=""
  scope="$(flatpak_effective_install_scope)"
  ensure_flatpak_remote_for_scope "${scope}"

  log "Installing missing Flatpak apps in ${scope} scope (${#app_ids[@]}):"
  print_wrapped_list app_ids "  - "
  if [[ "${scope}" == "user" ]]; then
    run_target flatpak --user install -y flathub "${app_ids[@]}"
  else
    flatpak install -y flathub "${app_ids[@]}"
  fi
}

check_and_offer_missing_installs() {
  local downloaded_repo_dir="${1:-}"
  local scripts_dir=""

  if ! scripts_dir="$(detect_repo_scripts_dir "${downloaded_repo_dir}")"; then
    warn "Could not locate repo scripts directory for package checks."
    return 0
  fi

  local arch_script="${scripts_dir}/install_arch_repo_apps.sh"
  local aur_script="${scripts_dir}/install_aur_repo_apps.sh"
  local flatpak_script="${scripts_dir}/install_flatpak_apps.sh"

  if [[ ! -f "${arch_script}" || ! -f "${aur_script}" || ! -f "${flatpak_script}" ]]; then
    warn "Package install scripts not found in ${scripts_dir}; skipping missing package checks."
    return 0
  fi

  log "Checking installed packages against:"
  printf '  %s\n' "${arch_script}"
  printf '  %s\n' "${aur_script}"
  printf '  %s\n' "${flatpak_script}"

  local -a declared_arch=() declared_aur=() declared_flatpak=()
  local -a missing_arch=() missing_aur=() missing_flatpak=()
  local item=""

  if ! mapfile -t declared_arch < <(parse_bash_array_from_script "${arch_script}" "PKG_GROUPS" "arch-groups"); then
    warn "Failed to parse PKG_GROUPS from ${arch_script}"
    declared_arch=()
  fi

  if ! mapfile -t declared_aur < <(parse_bash_array_from_script "${aur_script}" "PACKAGES_AUR" "plain"); then
    warn "Failed to parse PACKAGES_AUR from ${aur_script}"
    declared_aur=()
  fi

  if ! mapfile -t declared_flatpak < <(parse_bash_array_from_script "${flatpak_script}" "FLATPAK_APPS" "plain"); then
    warn "Failed to parse FLATPAK_APPS from ${flatpak_script}"
    declared_flatpak=()
  fi

  for item in "${declared_arch[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! pkg_installed_pacman "${item}"; then
      missing_arch+=("${item}")
    fi
  done

  for item in "${declared_aur[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! pkg_installed_pacman "${item}"; then
      missing_aur+=("${item}")
    fi
  done

  for item in "${declared_flatpak[@]}"; do
    [[ -n "${item}" ]] || continue
    if ! flatpak_app_installed_any_scope "${item}"; then
      missing_flatpak+=("${item}")
    fi
  done

  if (( ${#declared_arch[@]} )); then
    if (( ${#missing_arch[@]} )); then
      warn "Missing Arch repo packages (${#missing_arch[@]}) from install_arch_repo_apps.sh:"
      print_wrapped_list missing_arch "  - "
      if ask_yes_no "Install all missing Arch repo packages now?"; then
        install_missing_arch_repo_packages "${missing_arch[@]}" || true
      else
        log "Skipped Arch repo package installation."
      fi
    else
      log "Arch repo package check: nothing missing."
    fi
  fi

  if (( ${#declared_aur[@]} )); then
    if (( ${#missing_aur[@]} )); then
      warn "Missing AUR packages (${#missing_aur[@]}) from install_aur_repo_apps.sh:"
      print_wrapped_list missing_aur "  - "
      if ask_yes_no "Install all missing AUR packages now?"; then
        install_missing_aur_packages "${missing_aur[@]}" || true
      else
        log "Skipped AUR package installation."
      fi
    else
      log "AUR package check: nothing missing."
    fi
  fi

  if (( ${#declared_flatpak[@]} )); then
    if (( ${#missing_flatpak[@]} )); then
      warn "Missing Flatpak apps (${#missing_flatpak[@]}) from install_flatpak_apps.sh:"
      print_wrapped_list missing_flatpak "  - "
      if ask_yes_no "Install all missing Flatpak apps now?"; then
        install_missing_flatpak_apps "${missing_flatpak[@]}" || true
      else
        log "Skipped Flatpak app installation."
      fi
    else
      log "Flatpak app check: nothing missing."
    fi
  fi
}

main() {
  need_cmd curl
  need_cmd tar
  need_cmd find
  need_cmd cmp
  need_cmd mktemp
  need_cmd getent
  need_cmd python3

  init_target_user
  curl_headers

  local tag=""
  if [[ "${1:-}" == "--tag" ]]; then
    tag="${2:-}"
    [[ -n "$tag" ]] || die "Usage: $0 [--tag <tag>]"
  else
    tag="$(fetch_latest_release_tag)" || die "No GitHub release found for ${REPO_OWNER}/${REPO_NAME}"
  fi

  log "Target user: ${TARGET_USER}"
  log "Release tag: ${tag}"

  local tmpd
  tmpd="$(mktemp -d)"
  trap 'rm -rf -- "${tmpd:-}" 2>/dev/null || true' EXIT

  local tgz="${tmpd}/awtarchy.tgz"
  download_release_tarball "$tag" "$tgz"

  local top repo_dir
  top="$(tar_topdir "$tgz")"
  tar -xzf "$tgz" -C "$tmpd"
  repo_dir="${tmpd}/${top}"
  [[ -d "$repo_dir" ]] || die "Extracted repo dir missing: $repo_dir"

  log "Deploying (latest Release tag; backups on change; refuses empty overwrites)."

  if [[ -f "${repo_dir}/bashrc" ]]; then
    deploy_file "${repo_dir}/bashrc" "${HOME_DIR}/.bashrc"
  else
    warn "Upstream missing: bashrc (skipped)"
  fi

  if [[ -f "${repo_dir}/bash_profile" ]]; then
    deploy_file "${repo_dir}/bash_profile" "${HOME_DIR}/.bash_profile"
  else
    warn "Upstream missing: bash_profile (skipped)"
  fi

  if [[ -f "${repo_dir}/Xresources" ]]; then
    deploy_file "${repo_dir}/Xresources" "${HOME_DIR}/.Xresources"
  else
    warn "Upstream missing: Xresources (skipped)"
  fi

  if [[ -f "${repo_dir}/config/mimeapps.list" ]]; then
    deploy_file "${repo_dir}/config/mimeapps.list" "${HOME_DIR}/.config/mimeapps.list"
  else
    warn "Upstream missing: config/mimeapps.list (skipped)"
  fi

  if [[ -f "${repo_dir}/config/gamemode.ini" ]]; then
    deploy_file "${repo_dir}/config/gamemode.ini" "${HOME_DIR}/.config/gamemode.ini"
  else
    warn "Upstream missing: config/gamemode.ini (skipped)"
  fi

  local -a CONFIG_DIRS=(
    "hypr" "waybar" "alacritty" "wlogout" "mako" "fuzzel"
    "gtk-3.0" "Kvantum" "SpeedCrunch" "fastfetch" "pcmanfm-qt" "yazi"
    "xdg-desktop-portal" "qt5ct" "qt6ct" "lsfg-vk" "wiremix" "cava" "YouTube Music"
  )

  for d in "${CONFIG_DIRS[@]}"; do
    if [[ -d "${repo_dir}/config/${d}" ]]; then
      deploy_tree "${repo_dir}/config/${d}" "${HOME_DIR}/.config/${d}"
    else
      warn "Upstream missing dir: config/${d} (skipped)"
    fi
  done

  if [[ -f "${repo_dir}/local/share/nwg-look/gsettings" ]]; then
    deploy_file "${repo_dir}/local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/gsettings"
  fi

  if [[ -d "${repo_dir}/local/share/SpeedCrunch/color-schemes" ]]; then
    deploy_tree "${repo_dir}/local/share/SpeedCrunch/color-schemes" "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"
  fi

  if [[ -d "${repo_dir}/local/share/applications" ]]; then
    deploy_tree "${repo_dir}/local/share/applications" "${HOME_DIR}/.local/share/applications"
  fi

  mkdir -p -- "${HOME_DIR}/Pictures/wallpapers" "${HOME_DIR}/Pictures/Screenshots"
  if [[ -f "${repo_dir}/awtarchy_geology.png" ]]; then
    deploy_file "${repo_dir}/awtarchy_geology.png" "${HOME_DIR}/Pictures/wallpapers/awtarchy_geology.png"
  fi

  mkdir -p -- "${HOME_DIR}/.local/share/icons/ComixCursors-White"
  if [[ -d "/usr/share/icons/ComixCursors-White" ]]; then
    cp -a --no-preserve=ownership /usr/share/icons/ComixCursors-White/. "${HOME_DIR}/.local/share/icons/ComixCursors-White/" 2>/dev/null || true
    if [[ "${EUID}" -eq 0 ]]; then
      chown -R "${TARGET_USER}:${TARGET_USER}" "${HOME_DIR}/.local/share/icons/ComixCursors-White" 2>/dev/null || true
    fi
  fi

  update_system_cursor_default

  if command -v flatpak >/dev/null 2>&1; then
    run_target flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White >/dev/null 2>&1 || true
  fi

  fix_managed_perms "${CONFIG_DIRS[@]}"
  write_version_stamp "$tag"
  maybe_hyprctl_reload
  check_and_offer_missing_installs "${repo_dir}"

  if (( ${#BACKUPS[@]} )); then
    warn "Backups created:"
    for b in "${BACKUPS[@]}"; do
      printf '  %s\n' "$b"
    done
  else
    log "No backups created."
  fi

  log "Done."
}

main "$@"
