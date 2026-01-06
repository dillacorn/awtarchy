#!/usr/bin/env bash
# FILE: ~/awtarchy/update.sh
# Purpose: Update Awtarchy-managed files to repo origin/main.
#
# Backup rule:
# - No backup if destination already equals NEW repo file.
# - Backup ONLY if destination differs from BASELINE (repo HEAD before update).
#   Baseline content is pulled from git via OLD_COMMIT:path.
#
# Special:
# - ~/.config/hypr/hyprland.conf is merged (preserve monitor=, exec-once, and safe unique scalar prefs),
#   then hyprctl reload is attempted.
#
# Run:
#   cd ~/awtarchy
#   chmod +x update.sh
#   ./update.sh
#
# Optional (for system cursor file):
#   sudo ./update.sh

set -Eeuo pipefail
umask 022

RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[1;36m'
NC=$'\033[0m'

die() { printf '%sERROR:%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
log() { printf '%s%s%s\n' "$CYAN" "$*" "$NC"; }
ok()  { printf '%s%s%s\n' "$GREEN" "$*" "$NC"; }
warn(){ printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
timestamp() { date +%Y%m%d-%H%M%S; }

TARGET_USER=""
HOME_DIR=""
RUN_AS_USER=()

init_target_user() {
  if [[ "${EUID}" -eq 0 ]]; then
    [[ -n "${SUDO_USER:-}" ]] || die "Run with sudo from a real user account (SUDO_USER missing)."
    [[ "${SUDO_USER}" != "root" ]] || die "Refusing to target root."
    TARGET_USER="${SUDO_USER}"
    HOME_DIR="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
    [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "Home directory not found for ${TARGET_USER}."
    RUN_AS_USER=(sudo -u "${TARGET_USER}" -H)
  else
    TARGET_USER="${USER}"
    HOME_DIR="${HOME}"
    [[ -n "${HOME_DIR}" && -d "${HOME_DIR}" ]] || die "Home directory not found."
    RUN_AS_USER=()
  fi
}

run_user() { "${RUN_AS_USER[@]}" "$@"; }

repo_dir_detect() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -d "${script_dir}/.git" ]]; then
    printf '%s\n' "$script_dir"
  else
    printf '%s\n' "${HOME_DIR}/awtarchy"
  fi
}

backup_name_for() {
  local dest="$1"
  local base="${dest}.backup"
  if [[ -e "$base" ]]; then
    printf '%s.backup.%s\n' "$dest" "$(timestamp)"
  else
    printf '%s\n' "$base"
  fi
}

BACKUPS=()

make_backup() {
  local dest="$1"
  local b
  b="$(backup_name_for "$dest")"
  cp -a -- "$dest" "$b"
  BACKUPS+=("$b")
  warn "Backup: $b"
}

files_equal() { cmp -s -- "$1" "$2"; }

ensure_dir_user() { run_user install -d -m 755 -- "$1"; }

repo_ensure_and_update() {
  # Echoes: "<old_commit> <new_commit>" ONLY. No logs on stdout.
  local repo_dir="$1"
  local repo_url="https://github.com/dillacorn/awtarchy.git"
  local branch="main"
  local old="" new=""

  if [[ -d "${repo_dir}/.git" ]]; then
    old="$(run_user git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    run_user git -C "$repo_dir" fetch --prune origin >/dev/null
    run_user git -C "$repo_dir" reset --hard "origin/${branch}" >/dev/null
    new="$(run_user git -C "$repo_dir" rev-parse HEAD)"
    [[ -n "$old" ]] || old="$new"
    printf '%s %s\n' "$old" "$new"
    return 0
  fi

  if [[ -e "$repo_dir" && ! -d "$repo_dir" ]]; then
    die "Repo path exists but is not a directory: $repo_dir"
  fi
  if [[ -d "$repo_dir" && ! -d "$repo_dir/.git" ]]; then
    die "Directory exists but is not a git repo: $repo_dir"
  fi

  run_user git clone --depth 1 --branch "$branch" "$repo_url" "$repo_dir" >/dev/null
  new="$(run_user git -C "$repo_dir" rev-parse HEAD)"
  old="$new"
  printf '%s %s\n' "$old" "$new"
}

git_path_exists_in_commit() {
  local repo_dir="$1" commit="$2" path="$3"
  run_user git -C "$repo_dir" cat-file -e "${commit}:${path}" 2>/dev/null
}

git_show_to_file() {
  local repo_dir="$1" commit="$2" path="$3" out="$4"
  run_user git -C "$repo_dir" show "${commit}:${path}" >"$out"
}

read_baseline_symlink_target() {
  local repo_dir="$1" commit="$2" path="$3"
  local tmp
  tmp="$(mktemp)"
  git_show_to_file "$repo_dir" "$commit" "$path" "$tmp"
  tr -d '\n' <"$tmp"
  rm -f -- "$tmp"
}

dest_matches_src() {
  local src="$1" dest="$2"
  if [[ -L "$src" ]]; then
    [[ -L "$dest" ]] || return 1
    [[ "$(readlink -- "$dest")" == "$(readlink -- "$src")" ]]
    return $?
  fi
  [[ -f "$src" && -f "$dest" ]] || return 1
  cmp -s -- "$dest" "$src"
}

dest_modified_since_baseline() {
  # returns 0 if modified, 1 if not modified
  local repo_dir="$1" old_commit="$2" repo_rel="$3" dest="$4" tmpd="$5"

  [[ -e "$dest" || -L "$dest" ]] || return 1

  if git_path_exists_in_commit "$repo_dir" "$old_commit" "$repo_rel"; then
    if [[ -L "$dest" ]]; then
      local base_tgt
      base_tgt="$(read_baseline_symlink_target "$repo_dir" "$old_commit" "$repo_rel" || true)"
      [[ "$(readlink -- "$dest")" == "$base_tgt" ]] && return 1
      return 0
    fi

    if [[ -f "$dest" ]]; then
      local safe_rel base_tmp
      safe_rel="$(printf '%s' "$repo_rel" | tr '/ ' '__')"
      base_tmp="${tmpd}/baseline.${safe_rel}.tmp"
      git_show_to_file "$repo_dir" "$old_commit" "$repo_rel" "$base_tmp" || return 0
      cmp -s -- "$dest" "$base_tmp" && return 1
      return 0
    fi

    return 0
  fi

  return 0
}

replace_dest_with_src() {
  local src="$1" dest="$2" mode="${3:-644}"

  ensure_dir_user "$(dirname -- "$dest")"

  if [[ -L "$src" ]]; then
    rm -rf -- "$dest" 2>/dev/null || true
    run_user ln -s -- "$(readlink -- "$src")" "$dest"
    return 0
  fi

  if [[ -d "$dest" && -f "$src" ]]; then
    rm -rf -- "$dest"
  fi

  run_user install -m "$mode" -- "$src" "$dest"
}

sync_one_file() {
  local repo_dir="$1" old_commit="$2" repo_rel="$3" dest="$4" tmpd="$5" mode="${6:-644}"
  local src="${repo_dir}/${repo_rel}"

  [[ -e "$src" || -L "$src" ]] || die "Missing in repo: $src"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if dest_matches_src "$src" "$dest"; then
      return 0
    fi
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    if dest_modified_since_baseline "$repo_dir" "$old_commit" "$repo_rel" "$dest" "$tmpd"; then
      make_backup "$dest"
    fi
  fi

  replace_dest_with_src "$src" "$dest" "$mode"
}

sync_tree() {
  local repo_dir="$1" old_commit="$2" repo_root_rel="$3" dest_root="$4" tmpd="$5" skip_rel="${6:-}"
  local src_root="${repo_dir}/${repo_root_rel}"

  [[ -d "$src_root" ]] || die "Missing dir in repo: $src_root"

  ensure_dir_user "$dest_root"

  while IFS= read -r -d '' d; do
    local rel="${d#"$src_root"/}"
    [[ "$rel" == "$d" ]] && continue
    ensure_dir_user "${dest_root}/${rel}"
  done < <(find "$src_root" -type d -print0)

  while IFS= read -r -d '' p; do
    local rel="${p#"$src_root"/}"
    [[ -n "$skip_rel" && "$rel" == "$skip_rel" ]] && continue
    local repo_rel="${repo_root_rel}/${rel}"
    local dest="${dest_root}/${rel}"
    sync_one_file "$repo_dir" "$old_commit" "$repo_rel" "$dest" "$tmpd" 644
  done < <(find "$src_root" \( -type f -o -type l \) -print0)
}

merge_hyprland_conf() {
  local user_conf="$1"
  local template_conf="$2"
  local out_conf="$3"

  awk '
    function trim(s){ sub(/^[[:space:]]+/,"",s); sub(/[[:space:]]+$/,"",s); return s }
    function ltrim(s){ sub(/^[[:space:]]+/,"",s); return s }

    function is_section(line, name){
      return (line ~ "^[[:space:]]*#[[:space:]]*" name "[[:space:]]*$")
    }

    function is_mon(line, t){
      t=line
      sub(/^[[:space:]]*/,"",t)
      sub(/^#[[:space:]]*/,"",t)
      return (t ~ /^monitor[[:space:]]*=/)
    }

    function is_exec(line, t){
      t=line
      sub(/^[[:space:]]*/,"",t)
      sub(/^#[[:space:]]*/,"",t)
      return (t ~ /^exec-once[[:space:]]*=/)
    }

    function norm_exec_cmd(line, s){
      s=line
      sub(/^[[:space:]]*/,"",s)
      sub(/^#[[:space:]]*/,"",s)
      if (s !~ /^exec-once[[:space:]]*=/) return ""
      sub(/^exec-once[[:space:]]*=[[:space:]]*/, "", s)
      s=trim(s)
      sub(/[[:space:]]*&[[:space:]]*$/, "", s)
      s=trim(s)
      gsub(/[[:space:]]+/, " ", s)
      return s
    }

    function scalar_excluded(k){
      return (k=="env" || k=="monitor" || k=="exec-once" || k=="bezier" || k=="animation" || k=="source" || k=="submap" || k=="workspace" || k=="device" || k=="layerrule" || k ~ /^bind/ || k ~ /^windowrule/)
    }

    function parse_scalar(line,   t,a,k,rest,cpos){
      t=line
      sub(/^[[:space:]]+/,"",t)
      if (t ~ /^#/) return 0
      if (t ~ /^\$/) return 0
      if (t !~ /^[A-Za-z0-9_.-]+[[:space:]]*=/) return 0

      split(t, a, "=")
      k=trim(a[1])
      if (scalar_excluded(k)) return 0

      rest=substr(t, index(t, "=")+1)
      rest=trim(rest)

      cpos=index(rest, "#")
      if (cpos>0) rest=trim(substr(rest, 1, cpos-1))

      if (rest=="") return 0

      _scalar_k=k
      _scalar_v=rest
      return 1
    }

    FNR==1 { filei++ }

    filei==1{
      line=$0

      if (is_mon(line)) {
        key=trim(line)
        if (!(key in mon_seen)) {
          mon_seen[key]=1
          mon_list[++mon_n]=line
        }
      }

      if (is_section(line, "AUTOSTART")) { user_in_as=1; user_saw_as=1; next }
      if (user_in_as && is_section(line, "LOOK[[:space:]]*&[[:space:]]*FEEL")) { user_in_as=0; next }

      if (is_exec(line)) {
        cmd=norm_exec_cmd(line)
        if (cmd!="") {
          if (!(cmd in ex_all_seen)) {
            ex_all_seen[cmd]=1
            ex_all_order[++ex_all_n]=cmd
            ex_all_raw[cmd]=line
          }
          if (user_saw_as && user_in_as) {
            if (!(cmd in ex_as_seen)) {
              ex_as_seen[cmd]=1
              ex_as_order[++ex_as_n]=cmd
              ex_as_raw[cmd]=line
            }
          }
        }
      }

      if (parse_scalar(line)) {
        user_cnt[_scalar_k]++
        user_val[_scalar_k]=_scalar_v
      }

      next
    }

    filei==2{
      line=$0
      if (parse_scalar(line)) tpl_cnt[_scalar_k]++
      next
    }

    filei==3{
      line=$0

      if (is_section(line, "MONITORS")) { in_mon=1; mon_inserted=0 }
      if (is_section(line, "AUTOSTART")) { in_as=1 }

      if (in_as && is_section(line, "LOOK[[:space:]]*&[[:space:]]*FEEL")) {
        use_as = (ex_as_n>0 ? 1 : 0)
        if (use_as) {
          for (i=1;i<=ex_as_n;i++) {
            cmd=ex_as_order[i]
            if (!(cmd in ex_used)) print ex_as_raw[cmd]
          }
        } else {
          for (i=1;i<=ex_all_n;i++) {
            cmd=ex_all_order[i]
            if (!(cmd in ex_used)) print ex_all_raw[cmd]
          }
        }
        in_as=0
        print line
        next
      }

      if (in_mon) {
        if (is_mon(line)) {
          if (!mon_inserted && mon_n>0) {
            for (i=1;i<=mon_n;i++) print mon_list[i]
            mon_inserted=1
          }
          next
        }

        if (is_section(line, "ENV")) {
          if (!mon_inserted && mon_n>0) {
            for (i=1;i<=mon_n;i++) print mon_list[i]
            mon_inserted=1
          }
          in_mon=0
          print line
          next
        }

        print line
        next
      }

      if (in_as && is_exec(line)) {
        use_as = (ex_as_n>0 ? 1 : 0)
        cmd=norm_exec_cmd(line)
        if (cmd!="") {
          if (use_as && (cmd in ex_as_raw)) {
            match(line, /^[[:space:]]*/)
            ind=substr(line, RSTART, RLENGTH)
            print ind ltrim(ex_as_raw[cmd])
            ex_used[cmd]=1
            next
          }
          if (!use_as && (cmd in ex_all_raw)) {
            match(line, /^[[:space:]]*/)
            ind=substr(line, RSTART, RLENGTH)
            print ind ltrim(ex_all_raw[cmd])
            ex_used[cmd]=1
            next
          }
        }
        print line
        next
      }

      if (parse_scalar(line)) {
        k=_scalar_k
        if (user_cnt[k]==1 && tpl_cnt[k]==1) {
          match(line, /^[[:space:]]*/)
          ind=substr(line, RSTART, RLENGTH)

          t=line
          sub(/^[[:space:]]+/,"",t)
          split(t, a, "=")
          key_txt=trim(a[1])

          rest=substr(t, index(t, "=")+1)
          cpos=index(rest, "#")
          cmt=""
          if (cpos>0) cmt=substr(rest, cpos)

          print ind key_txt " = " user_val[k] (cmt!="" ? cmt : "")
          next
        }
      }

      print line
      next
    }
  ' "$user_conf" "$template_conf" "$template_conf" >"$out_conf"
}

sync_hyprland_conf_merged() {
  local repo_dir="$1" old_commit="$2" tmpd="$3"
  local repo_rel="config/hypr/hyprland.conf"
  local src="${repo_dir}/${repo_rel}"
  local dest="${HOME_DIR}/.config/hypr/hyprland.conf"

  [[ -f "$src" ]] || die "Missing template in repo: $src"
  ensure_dir_user "${HOME_DIR}/.config/hypr"

  local next_conf="${tmpd}/hyprland.next.conf"
  if [[ -f "$dest" ]]; then
    merge_hyprland_conf "$dest" "$src" "$next_conf"
  else
    merge_hyprland_conf /dev/null "$src" "$next_conf"
  fi

  if [[ -f "$dest" ]] && cmp -s -- "$dest" "$next_conf"; then
    return 0
  fi

  if [[ -f "$dest" ]]; then
    if dest_modified_since_baseline "$repo_dir" "$old_commit" "$repo_rel" "$dest" "$tmpd"; then
      make_backup "$dest"
    fi
  fi

  run_user install -m 644 -- "$next_conf" "$dest"
}

fix_managed_perms() {
  local -a dirs=("$@")

  for d in "${dirs[@]}"; do
    local root="${HOME_DIR}/.config/${d}"
    [[ -d "$root" ]] || continue
    find "$root" -type d -exec chmod 755 {} + 2>/dev/null || true
    find "$root" -type f -exec chmod 644 {} + 2>/dev/null || true
  done

  [[ -d "${HOME_DIR}/.config/hypr/scripts"    ]] && find "${HOME_DIR}/.config/hypr/scripts"    -type f -exec chmod +x {} + 2>/dev/null || true
  [[ -d "${HOME_DIR}/.config/hypr/themes"     ]] && find "${HOME_DIR}/.config/hypr/themes"     -type f -exec chmod +x {} + 2>/dev/null || true
  [[ -d "${HOME_DIR}/.config/waybar/scripts"  ]] && find "${HOME_DIR}/.config/waybar/scripts"  -type f -exec chmod +x {} + 2>/dev/null || true
}

maybe_hyprctl_reload() {
  if command -v hyprctl >/dev/null 2>&1; then
    run_user hyprctl reload >/dev/null 2>&1 || true
  fi
}

main() {
  need_cmd git
  need_cmd find
  need_cmd cmp
  need_cmd awk
  need_cmd mktemp
  need_cmd install
  need_cmd getent
  need_cmd chmod
  need_cmd tr
  need_cmd readlink

  init_target_user

  local tmpd=""
  trap '[[ -n "${tmpd:-}" && -d "${tmpd:-}" ]] && rm -rf -- "${tmpd:-}" || true' EXIT
  tmpd="$(mktemp -d)"

  local repo_dir old_commit new_commit
  repo_dir="$(repo_dir_detect)"

  if [[ -d "${repo_dir}/.git" ]]; then
    log "Repo: ${repo_dir}"
    if [[ -n "$(run_user git -C "$repo_dir" status --porcelain 2>/dev/null || true)" ]]; then
      warn "Repo has local edits. Discarding them (git reset --hard)."
    fi
  else
    log "Repo: ${repo_dir} (cloning)"
  fi

  read -r old_commit new_commit < <(repo_ensure_and_update "$repo_dir")
  ok "Repo: ${old_commit} -> ${new_commit}"

  log "Deploying managed files"

  local -a CONFIG_DIRS=(
    "hypr" "waybar" "alacritty" "wlogout" "mako" "wofi"
    "gtk-3.0" "Kvantum" "SpeedCrunch" "fastfetch" "pcmanfm-qt" "yazi"
    "xdg-desktop-portal" "qt5ct" "qt6ct" "lsfg-vk" "wiremix" "cava" "YouTube Music"
  )

  sync_one_file "$repo_dir" "$old_commit" "bashrc"       "${HOME_DIR}/.bashrc" "$tmpd" 644
  sync_one_file "$repo_dir" "$old_commit" "bash_profile" "${HOME_DIR}/.bash_profile" "$tmpd" 644
  sync_one_file "$repo_dir" "$old_commit" "Xresources"   "${HOME_DIR}/.Xresources" "$tmpd" 644

  sync_one_file "$repo_dir" "$old_commit" "config/mimeapps.list" "${HOME_DIR}/.config/mimeapps.list" "$tmpd" 644
  sync_one_file "$repo_dir" "$old_commit" "config/gamemode.ini"  "${HOME_DIR}/.config/gamemode.ini"  "$tmpd" 644

  for d in "${CONFIG_DIRS[@]}"; do
    if [[ "$d" == "hypr" ]]; then
      sync_tree "$repo_dir" "$old_commit" "config/${d}" "${HOME_DIR}/.config/${d}" "$tmpd" "hyprland.conf"
    else
      sync_tree "$repo_dir" "$old_commit" "config/${d}" "${HOME_DIR}/.config/${d}" "$tmpd"
    fi
  done

  sync_hyprland_conf_merged "$repo_dir" "$old_commit" "$tmpd"

  sync_one_file "$repo_dir" "$old_commit" "local/share/nwg-look/gsettings" "${HOME_DIR}/.local/share/nwg-look/gsettings" "$tmpd" 644
  sync_tree "$repo_dir" "$old_commit" "local/share/SpeedCrunch/color-schemes" "${HOME_DIR}/.local/share/SpeedCrunch/color-schemes" "$tmpd"
  sync_tree "$repo_dir" "$old_commit" "local/share/applications" "${HOME_DIR}/.local/share/applications" "$tmpd"

  ensure_dir_user "${HOME_DIR}/Pictures/wallpapers"
  ensure_dir_user "${HOME_DIR}/Pictures/Screenshots"
  sync_one_file "$repo_dir" "$old_commit" "awtarchy_geology.png" "${HOME_DIR}/Pictures/wallpapers/awtarchy_geology.png" "$tmpd" 644

  ensure_dir_user "${HOME_DIR}/.local/share/icons/ComixCursors-White"
  if [[ -d "/usr/share/icons/ComixCursors-White" ]]; then
    run_user cp -a /usr/share/icons/ComixCursors-White/. "${HOME_DIR}/.local/share/icons/ComixCursors-White/" 2>/dev/null || true
  fi

  if [[ "${EUID}" -eq 0 ]]; then
    install -d -m 755 /usr/share/icons/default
    cat >/usr/share/icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=ComixCursors-White
EOF
    chmod 644 /usr/share/icons/default/index.theme 2>/dev/null || true
  fi

  if command -v flatpak >/dev/null 2>&1; then
    run_user flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White >/dev/null 2>&1 || true
  fi

  fix_managed_perms "${CONFIG_DIRS[@]}"
  maybe_hyprctl_reload

  if (( ${#BACKUPS[@]} )); then
    warn "Backups created (only when you changed the file since last update):"
    for b in "${BACKUPS[@]}"; do
      printf '  %s\n' "$b"
    done
  else
    ok "No backups created."
  fi

  ok "Update complete."
}

main "$@"
