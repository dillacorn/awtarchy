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

download_release_tarball() {
  local tag="$1"
  local out="$2"
  local url="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/tags/${tag}.tar.gz"

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
