#!/usr/bin/env bash
# FILE: ~/awtarchy/update.sh
# Run: sudo ./update.sh

set -Eeuo pipefail
umask 022

# ──────────────────────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

die() { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
log() { echo -e "${CYAN}$*${NC}"; }
ok()  { echo -e "${GREEN}$*${NC}"; }
warn(){ echo -e "${YELLOW}$*${NC}"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

retry() {
  local tries=3 n=0
  until "$@"; do
    n=$((n+1))
    if (( n >= tries )); then
      die "Command failed after ${tries} attempts: $*"
    fi
    warn "Retrying (${n}/${tries}) for: $*"
    sleep 1
  done
}

require_sudo_user() {
  [[ "${EUID}" -eq 0 ]] || die "Run with sudo."
  [[ -n "${SUDO_USER:-}" ]] || die "SUDO_USER is empty. Use: sudo ./update.sh"
  [[ "${SUDO_USER}" != "root" ]] || die "Refusing to target root."
}

create_dir_user() {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    retry mkdir -p "$d"
    retry chown "${SUDO_USER}:${SUDO_USER}" "$d"
    retry chmod 755 "$d"
  fi
}

create_dir_root() {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    retry mkdir -p "$d"
    retry chown root:root "$d" || true
    retry chmod 755 "$d"
  fi
}

timestamp() { date +%Y%m%d-%H%M%S; }

backup_name_for() {
  local dest="$1"
  local base="${dest}.backup"
  if [[ -e "$base" ]]; then
    echo "${dest}.backup.$(timestamp)"
  else
    echo "$base"
  fi
}

BACKUPS=()

backup_path() {
  local dest="$1"
  local b
  b="$(backup_name_for "$dest")"
  retry cp -a -- "$dest" "$b"
  BACKUPS+=("$b")
  warn "Backup: $b"
}

comment_flatpak_user_alias_if_btrfs() {
  local f="$1"
  if findmnt -n -o FSTYPE / 2>/dev/null | grep -qi btrfs; then
    sed -i '/alias flatpak=.flatpak --user./ { /^[[:space:]]*#/! s/^/#/ }' "$f" || true
  fi
}

git_repo_clean_or_die() {
  local repo="$1"
  [[ -d "$repo/.git" ]] || die "Not a git repo: $repo"
  local st
  st="$(git -C "$repo" status --porcelain || true)"
  [[ -z "$st" ]] || die "Repo has local changes in $repo. Commit/stash/reset before updating."
}

git_path_exists_in_commit() {
  local repo="$1" commit="$2" path="$3"
  git -C "$repo" cat-file -e "${commit}:${path}" 2>/dev/null
}

files_equal() {
  local a="$1" b="$2"
  cmp -s -- "$a" "$b"
}

maybe_backup_file() {
  local repo="$1" old_commit="$2" repo_rel="$3" src="$4" dest="$5"
  [[ -e "$dest" || -L "$dest" ]] || return 0

  if [[ -d "$dest" && ! -d "$src" ]]; then
    backup_path "$dest"
    return 0
  fi

  if git_path_exists_in_commit "$repo" "$old_commit" "$repo_rel"; then
    if [[ -L "$src" ]]; then
      local baseline_link dest_link
      baseline_link="$(git -C "$repo" show "${old_commit}:${repo_rel}" 2>/dev/null || true)"
      baseline_link="${baseline_link%$'\n'}"
      dest_link="$(readlink "$dest" 2>/dev/null || true)"
      [[ "$dest_link" == "$baseline_link" ]] || backup_path "$dest"
      return 0
    fi

    local tmp
    tmp="$(mktemp)"
    git -C "$repo" show "${old_commit}:${repo_rel}" >"$tmp" 2>/dev/null || true

    if [[ "$repo_rel" == "bashrc" || "$repo_rel" == "bash_profile" ]]; then
      comment_flatpak_user_alias_if_btrfs "$tmp"
    fi

    if [[ -f "$dest" ]] && files_equal "$dest" "$tmp"; then
      rm -f "$tmp"
      return 0
    fi

    rm -f "$tmp"
    backup_path "$dest"
    return 0
  fi

  if [[ -L "$src" ]]; then
    local new_link dest_link
    new_link="$(readlink "$src" 2>/dev/null || true)"
    dest_link="$(readlink "$dest" 2>/dev/null || true)"
    [[ "$dest_link" == "$new_link" ]] || backup_path "$dest"
    return 0
  fi

  if [[ -f "$dest" && -f "$src" ]] && files_equal "$dest" "$src"; then
    return 0
  fi

  backup_path "$dest"
}

sync_one() {
  local repo="$1" old_commit="$2" repo_rel="$3" dest="$4"
  local src="${repo}/${repo_rel}"

  [[ -e "$src" || -L "$src" ]] || die "Missing source in repo: $src"

  create_dir_user "$(dirname "$dest")"

  maybe_backup_file "$repo" "$old_commit" "$repo_rel" "$src" "$dest"

  if [[ -e "$dest" && -d "$dest" && ! -d "$src" ]]; then
    retry rm -rf -- "$dest"
  elif [[ -e "$dest" && ! -d "$dest" && -d "$src" ]]; then
    retry rm -f -- "$dest"
  fi

  retry cp -a -- "$src" "$dest"
  retry chown "${SUDO_USER}:${SUDO_USER}" "$dest" || true

  if [[ ! -d "$dest" ]]; then
    retry chmod 644 "$dest" || true
  fi

  if [[ "$repo_rel" == "bashrc" || "$repo_rel" == "bash_profile" ]]; then
    comment_flatpak_user_alias_if_btrfs "$dest"
  fi
}

sync_tree() {
  local repo="$1" old_commit="$2" repo_root_rel="$3" dest_root="$4"
  local src_root="${repo}/${repo_root_rel}"

  [[ -d "$src_root" ]] || die "Missing source dir in repo: $src_root"

  create_dir_user "$dest_root"

  while IFS= read -r -d '' d; do
    local rel="${d#"$src_root"/}"
    [[ "$rel" == "$d" ]] && rel=""
    [[ -z "$rel" ]] && continue
    create_dir_user "${dest_root}/${rel}"
  done < <(find "$src_root" -type d -print0)

  while IFS= read -r -d '' p; do
    local rel="${p#"$src_root"/}"
    local repo_rel="${repo_root_rel}/${rel}"
    local dest="${dest_root}/${rel}"

    create_dir_user "$(dirname "$dest")"
    maybe_backup_file "$repo" "$old_commit" "$repo_rel" "$p" "$dest"

    if [[ -e "$dest" && -d "$dest" && ! -d "$p" ]]; then
      retry rm -rf -- "$dest"
    elif [[ -e "$dest" && ! -d "$dest" && -d "$p" ]]; then
      retry rm -f -- "$dest"
    fi

    retry cp -a -- "$p" "$dest"
    retry chown "${SUDO_USER}:${SUDO_USER}" "$dest" || true
  done < <(find "$src_root" \( -type f -o -type l \) -print0)
}

fix_managed_perms() {
  local home="$1"
  shift
  local -a dirs=("$@")

  for d in "${dirs[@]}"; do
    local root="${home}/.config/${d}"
    [[ -d "$root" ]] || continue
    find "$root" -type d -exec chmod 755 {} + || true
    find "$root" -type f -exec chmod 644 {} + || true
  done

  [[ -d "${home}/.config/hypr/scripts"   ]] && find "${home}/.config/hypr/scripts"   -type f -exec chmod +x {} + || true
  [[ -d "${home}/.config/hypr/themes"    ]] && find "${home}/.config/hypr/themes"    -type f -exec chmod +x {} + || true
  [[ -d "${home}/.config/waybar/scripts" ]] && find "${home}/.config/waybar/scripts" -type f -exec chmod +x {} + || true
}

main() {
  require_sudo_user
  need_cmd git
  need_cmd find
  need_cmd cp
  need_cmd cmp
  need_cmd chown
  need_cmd chmod
  need_cmd mkdir
  need_cmd sed
  need_cmd findmnt

  local HOME_DIR="/home/${SUDO_USER}"
  local REPO_DIR="${HOME_DIR}/awtarchy"

  [[ -d "$HOME_DIR" ]] || die "Home directory not found: $HOME_DIR"
  [[ -d "$REPO_DIR" ]] || die "Repo directory not found: $REPO_DIR"

  git_repo_clean_or_die "$REPO_DIR"

  log "Updating repo: $REPO_DIR"
  local OLD_COMMIT NEW_COMMIT
  OLD_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
  retry git -C "$REPO_DIR" pull --ff-only
  NEW_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
  ok "Repo: ${OLD_COMMIT} -> ${NEW_COMMIT}"

  local -a CONFIG_DIRS=(
    "hypr" "waybar" "alacritty" "wlogout" "mako" "wofi"
    "gtk-3.0" "Kvantum" "SpeedCrunch" "fastfetch" "pcmanfm-qt" "yazi"
    "xdg-desktop-portal" "qt5ct" "qt6ct" "lsfg-vk" "wiremix" "cava" "YouTube Music"
  )

  log "Deploying managed files and configs"

  sync_one "$REPO_DIR" "$OLD_COMMIT" "bashrc"       "${HOME_DIR}/.bashrc"
  sync_one "$REPO_DIR" "$OLD_COMMIT" "bash_profile" "${HOME_DIR}/.bash_profile"

  for d in "${CONFIG_DIRS[@]}"; do
    sync_tree "$REPO_DIR" "$OLD_COMMIT" "config/${d}" "${HOME_DIR}/.config/${d}"
  done

  sync_one "$REPO_DIR" "$OLD_COMMIT" "Xresources"           "${HOME_DIR}/.Xresources"
  sync_one "$REPO_DIR" "$OLD_COMMIT" "config/mimeapps.list" "${HOME_DIR}/.config/mimeapps.list"
  sync_one "$REPO_DIR" "$OLD_COMMIT" "config/gamemode.ini"  "${HOME_DIR}/.config/gamemode.ini"

  create_dir_user "${HOME_DIR}/.local/share/nwg-look"
  sync_one "$REPO_DIR" "$OLD_COMMIT" "local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/gsettings"

  create_dir_user "${HOME_DIR}/.local/share/SpeedCrunch"
  create_dir_user "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"
  sync_tree "$REPO_DIR" "$OLD_COMMIT" "local/share/SpeedCrunch/color-schemes" "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes"
  retry chown -R "${SUDO_USER}:${SUDO_USER}" "${HOME_DIR}/.local/share/SpeedCrunch" || true
  find "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes" -type f -exec chmod 644 {} + || true

  create_dir_user "${HOME_DIR}/.local/share/applications"
  sync_tree "$REPO_DIR" "$OLD_COMMIT" "local/share/applications" "${HOME_DIR}/.local/share/applications"
  find "${HOME_DIR}/.local/share/applications" -type f -exec chmod 644 {} + || true
  retry chown -R "${SUDO_USER}:${SUDO_USER}" "${HOME_DIR}/.local/share/applications" || true

  create_dir_user "${HOME_DIR}/Pictures/wallpapers"
  create_dir_user "${HOME_DIR}/Pictures/Screenshots"
  sync_one "$REPO_DIR" "$OLD_COMMIT" "awtarchy_geology.png" "${HOME_DIR}/Pictures/wallpapers/awtarchy_geology.png"

  create_dir_user "${HOME_DIR}/.local/share/icons/ComixCursors-White"
  if [[ -d "/usr/share/icons/ComixCursors-White" ]]; then
    retry cp -a /usr/share/icons/ComixCursors-White/. "${HOME_DIR}/.local/share/icons/ComixCursors-White/"
    retry chown -R "${SUDO_USER}:${SUDO_USER}" "${HOME_DIR}/.local/share/icons/ComixCursors-White" || true
  else
    warn "Missing /usr/share/icons/ComixCursors-White (install xcursor-comix). Skipping user cursor copy."
  fi

  create_dir_root "/usr/share/icons/default"
  cat >/usr/share/icons/default/index.theme <<EOF2
[Icon Theme]
Inherits=ComixCursors-White
EOF2
  chown root:root /usr/share/icons/default/index.theme 2>/dev/null || true
  chmod 644 /usr/share/icons/default/index.theme 2>/dev/null || true

  if command -v flatpak >/dev/null 2>&1; then
    sudo -u "${SUDO_USER}" flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White || true
  fi

  fix_managed_perms "$HOME_DIR" "${CONFIG_DIRS[@]}"

  retry chown "${SUDO_USER}:${SUDO_USER}" "$HOME_DIR/.Xresources" || true
  retry chown -R "${SUDO_USER}:${SUDO_USER}" "$HOME_DIR/.config" || true
  retry chown -R "${SUDO_USER}:${SUDO_USER}" "$HOME_DIR/.local/share/nwg-look" || true
  retry chown -R "${SUDO_USER}:${SUDO_USER}" "$HOME_DIR/Pictures" || true

  if (( ${#BACKUPS[@]} )); then
    warn "Backups created:"
    for b in "${BACKUPS[@]}"; do
      echo "  $b"
    done
  else
    ok "No backups created (no user-modified managed files detected since last repo state)."
  fi

  ok "Update complete."
}

main "$@"
