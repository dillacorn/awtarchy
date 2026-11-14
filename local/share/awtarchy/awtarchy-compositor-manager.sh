#!/usr/bin/env bash
# Sway trial compositor management. Protect personal configs and package ownership.
set -euo pipefail

[[ $(id -u) -ne 0 ]] || { printf 'Run as your normal user.\n' >&2; exit 1; }
operation="$1"
mode="$2"
remove_deps="$3"
[[ "$mode" == plan || "$mode" == apply ]] || { printf 'Invalid mode.\n' >&2; exit 2; }
[[ "$remove_deps" == yes || "$remove_deps" == no ]] || { printf 'Invalid dependency choice.\n' >&2; exit 2; }
ledger=/var/lib/awtarchy/managed-packages
source_file="$HOME/.local/state/awtarchy/compositor-trial-source"
session_file=/usr/share/wayland-sessions/awtarchy-sway-trial.desktop
fail() { printf 'Awtarchy compositor: %s\n' "$*" >&2; return 1; }
installed() { pacman -Qq "$1" >/dev/null 2>&1; }
owned() { [[ -f "$ledger" && ! -L "$ledger" ]] && grep -Fxq -- "$1" "$ledger"; }
status() {
  for pkg in hyprland sway; do
    if installed "$pkg"; then printf '%s: installed\n' "$pkg"; else printf '%s: absent\n' "$pkg"; fi
  done
  if [[ -f "$session_file" ]]; then printf 'Sway Ly entry: present\n'; else printf 'Sway Ly entry: missing\n'; fi
  for pkg in vulkan-radeon vulkan-intel nvidia-utils vulkan-nouveau; do
    if installed "$pkg"; then printf 'GPU Vulkan package: %s\n' "$pkg"; fi
  done
  printf 'Sway uses current Mesa/DRM drivers; no GPU stack changes are made.\n'
}
if [[ "$operation" == status ]]; then status; exit 0; fi
case "$operation" in
  install-sway|install-hyprland|remove-sway|remove-hyprland|update-sway) ;;
  *) fail 'Unknown operation'; exit 2 ;;
esac
[[ -f "$source_file" && ! -L "$source_file" && -O "$source_file" ]] ||
  { fail 'Source not registered; refresh command from Sway trial checkout'; exit 1; }
IFS= read -r repo < "$source_file" || :
[[ "$repo" == /* && -d "$repo/.git" && ! -L "$repo" ]] ||
  { fail 'Trial source checkout no longer available'; exit 1; }
[[ "$(git -C "$repo" branch --show-current)" == SwayWM_Migration_Trial_Investigation ]] ||
  { fail 'Trial source changed branch'; exit 1; }
[[ -f "$repo/trials/sway/setup.sh" && -f "$repo/config/hypr/hyprland.lua" ]] ||
  { fail 'Trial source incomplete'; exit 1; }
printf 'Action: %s\n' "$operation"
printf 'Personal configs are preserved. Shared packages are preserved.\n'
if [[ "$operation" == update-sway ]]; then
  printf 'Review/apply Sway managed helper and Quickshell updates; personal TOML and modified files remain preserved.\n'
elif [[ "$operation" == install-sway ]]; then
  printf 'Sway and session dependencies via official Arch packages only.\n'
elif [[ "$operation" == install-hyprland ]]; then
  printf 'Hyprland and its compositor packages via pacman; existing config preserved.\n'
else
  if [[ "$operation" == remove-sway ]]; then
    if [[ "$remove_deps" == yes ]]; then
      packages='swaybg swayidle swaylock xdg-desktop-portal-wlr lxqt-policykit sway'
    else packages='sway'; fi
  else
    if [[ "$remove_deps" == yes ]]; then
      packages='hyprland-qt-support hyprpaper hypridle hyprpicker hyprsunset xdg-desktop-portal-hyprland hyprland'
    else packages='hyprland'; fi
  fi
  for pkg in $packages; do
    if ! installed "$pkg"; then printf 'Absent: %s\n' "$pkg"
    elif owned "$pkg"; then printf 'Eligible (Awtarchy-owned): %s\n' "$pkg"
    else printf 'PRESERVE untracked: %s\n' "$pkg"; fi
  done
  printf 'Removal uses pacman -R; never -Rns or cascade.\n'
fi
if [[ "$mode" == plan ]]; then
  case "$operation" in
    update-sway)
      python3 "$repo/trials/sway/sync.py" review --repo "$repo" ;;
    install-hyprland)
      python3 "$repo/trials/sway/stage-hyprland.py" --preview --repo "$repo" ;;
    *) : ;;
  esac
  printf 'Preview only; nothing changed.\n'
  exit 0
fi
[[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] ||
  { fail 'Changes require interactive confirmation'; exit 1; }
printf 'Type %s to authorize: ' "$operation" >/dev/tty
IFS= read -r approval </dev/tty || :
[[ "$approval" == "$operation" ]] || { printf 'Canceled.\n'; exit 1; }
record() {
  local pkg="$1"
  [[ ! -L "$ledger" && ( ! -e "$ledger" || -f "$ledger" ) ]] ||
    { fail 'Ownership ledger is unsafe'; return 1; }
  if [[ -e "$ledger" ]] && [[ "$(stat -c '%u' "$ledger")" != 0 ]]; then
    fail 'Existing ownership ledger is not root-owned'; return 1
  fi
  sudo install -d -m 0755 /var/lib/awtarchy
  if ! owned "$pkg"; then
    printf '%s\n' "$pkg" | sudo tee -a "$ledger" >/dev/null
    sudo chmod 0644 "$ledger"
  fi
}
add_pkg() {
  local pkg="$1"
  if installed "$pkg"; then printf 'Keep existing: %s\n' "$pkg"; return 0; fi
  sudo pacman -S --needed --noconfirm "$pkg"
  installed "$pkg" || { fail "Install unverified: $pkg"; return 1; }
  record "$pkg"
}
drop_pkg() {
  local pkg="$1" targets=""
  installed "$pkg" || return 0
  if ! owned "$pkg"; then printf 'Keep untracked: %s\n' "$pkg"; return 0; fi
  # Confirm the exact removal transaction before writing any package state.
  # -R --print performs no changes and -R never cascades or removes dependencies.
  targets="$(pacman -R --print --print-format '%n' -- "$pkg")" ||
    { fail "Pacman dependency preflight blocked removal: $pkg"; return 1; }
  [[ "$targets" == "$pkg" ]] ||
    { fail "Unexpected pacman removal targets for $pkg; refused"; return 1; }
  sudo pacman -R --noconfirm -- "$pkg" ||
    { fail "Pacman blocked removal: $pkg"; return 1; }
  if installed "$pkg"; then fail "Removal unverified: $pkg"; return 1; fi
  sudo sed -i "\|^$pkg$|d" "$ledger"
  printf 'Removed: %s\n' "$pkg"
}
if [[ "$operation" == install-sway ]]; then
  for pkg in sway swaybg swayidle swaylock xdg-desktop-portal-wlr \
      quickshell qt6-multimedia qt6-multimedia-ffmpeg foot fuzzel mako \
      grim slurp satty wl-clipboard cliphist xdg-desktop-portal-gtk \
      libnotify jq python pipewire lxqt-policykit playerctl; do
    add_pkg "$pkg"
  done
  bash "$repo/trials/sway/setup.sh" --check
  # Check root destinations before any file installation. Do not overwrite others.
  for pair in \
      "$repo/trials/sway/sway.desktop:$session_file" \
      "$repo/trials/sway/session-launch.sh:/usr/local/bin/awtarchy-sway-session"; do
    source_descriptor="${pair%%:*}"
    installed_descriptor="${pair#*:}"
    [[ -f "$source_descriptor" && ! -L "$source_descriptor" ]] ||
      { fail "Missing session source: $source_descriptor"; exit 1; }
    if [[ -e "$installed_descriptor" || -L "$installed_descriptor" ]]; then
      [[ -f "$installed_descriptor" && ! -L "$installed_descriptor" ]] &&
        cmp -s "$source_descriptor" "$installed_descriptor" ||
        { fail "Existing session file must be reviewed: $installed_descriptor"; exit 1; }
    fi
  done
  bash "$repo/trials/sway/setup.sh" --install
  if [[ "${XDG_CURRENT_DESKTOP:-}" == Hyprland && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    config="$HOME/.config/sway/awtarchy-trial/config"
    if python3 - "$config" <<'PY'
from pathlib import Path
import sys
body = Path(sys.argv[1]).read_text(encoding="utf-8")
start, end = "# AWTARCHY-SWAY-OUTPUTS-BEGIN", "# AWTARCHY-SWAY-OUTPUTS-END"
assert body.count(start) == 1 and body.count(end) == 1
between = body.split(start, 1)[1].split(end, 1)[0]
sys.exit(0 if not any(line.strip() and not line.lstrip().startswith("#")
                      for line in between.splitlines()) else 2)
PY
    then
      python3 "$repo/trials/sway/import-hypr-monitors.py" --preview
      python3 "$repo/trials/sway/import-hypr-monitors.py" --apply
    fi
  else
    printf 'Sway output profile not imported; run one-time importer from Hyprland.\n'
  fi
  sudo install -d -m 0755 /usr/local/bin /usr/share/wayland-sessions
  [[ -e /usr/local/bin/awtarchy-sway-session ]] ||
    sudo install -m 0755 "$repo/trials/sway/session-launch.sh" /usr/local/bin/awtarchy-sway-session
  [[ -e "$session_file" ]] ||
    sudo install -m 0644 "$repo/trials/sway/sway.desktop" "$session_file"
  baseline="$HOME/.local/state/awtarchy/sway-managed-baseline.json"
  if [[ ! -e "$baseline" && ! -L "$baseline" ]]; then
    python3 "$repo/trials/sway/sync.py" record --repo "$repo"
  fi
elif [[ "$operation" == update-sway ]]; then
  # Apply the previewed managed diff; no package operations or compositor
  # removals are reachable through this branch.
  python3 "$repo/trials/sway/sync.py" apply --repo "$repo"
elif [[ "$operation" == install-hyprland ]]; then
  # Validate every destination before installing anything. Copy only missing
  # Awtarchy scripts, shaders, configuration and shared shell files.
  python3 "$repo/trials/sway/stage-hyprland.py" --preview --repo "$repo"
  for pkg in hyprland hyprland-qt-support hyprpaper hypridle hyprpicker hyprsunset \
      xdg-desktop-portal-hyprland quickshell foot fuzzel mako grim slurp \
      wl-clipboard cliphist jq python pipewire playerctl; do
    add_pkg "$pkg"
  done
  python3 "$repo/trials/sway/stage-hyprland.py" --apply --repo "$repo"
  [[ -f /usr/share/wayland-sessions/hyprland.desktop ]] ||
    { fail 'The Hyprland package did not provide a usable Ly Wayland session entry'; exit 1; }
else
  desktop_name=""
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then desktop_name="$XDG_CURRENT_DESKTOP"; fi
  if [[ "$operation" == remove-sway ]]; then
    other=hyprland
    target=sway
    [[ "$desktop_name" != sway ]] || { fail 'Cannot remove running Sway'; exit 1; }
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$(id -u)" -x sway >/dev/null 2>&1; then
      fail 'Sway is still running on another TTY. Stop that session before removal.'; exit 1
    fi
  else
    other=sway
    target=hyprland
    [[ "$desktop_name" != Hyprland && "$desktop_name" != hyprland ]] ||
      { fail 'Cannot remove running Hyprland'; exit 1; }
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$(id -u)" -x Hyprland >/dev/null 2>&1; then
      fail 'Hyprland is still running on another TTY. Stop that session before removal.'; exit 1
    fi
  fi
  installed "$other" || { fail "Cannot remove last compositor; install $other first"; exit 1; }
  # A removal must not start with optional components and only later find that
  # the compositor cannot be removed. Remove the compositor first.
  if installed "$target" && ! owned "$target"; then
    fail "Compositor $target was not installed by Awtarchy; no package removed."; exit 1
  fi
  drop_pkg "$target"
  if [[ "$remove_deps" == yes ]]; then
    for pkg in $packages; do
      [[ "$pkg" == "$target" ]] && continue
      # Keep explicitly shared runtime dependencies, even when tracked.
      case "$pkg" in
        quickshell|foot|fuzzel|mako|grim|slurp|wl-clipboard|cliphist|xdg-desktop-portal-gtk|jq|python|pipewire|playerctl)
          printf 'Preserving shared dependency: %s\n' "$pkg"
          continue ;;
      esac
      drop_pkg "$pkg"
    done
  fi
  if [[ "$target" == sway ]] && ! installed sway; then
    for pair in \
        "$repo/trials/sway/sway.desktop:$session_file" \
        "$repo/trials/sway/session-launch.sh:/usr/local/bin/awtarchy-sway-session"; do
      source_descriptor="${pair%%:*}"
      installed_descriptor="${pair#*:}"
      if [[ -f "$installed_descriptor" && ! -L "$installed_descriptor" &&
            -f "$source_descriptor" && ! -L "$source_descriptor" ]] &&
            cmp -s "$source_descriptor" "$installed_descriptor" &&
            ! pacman -Qo -- "$installed_descriptor" >/dev/null 2>&1; then
        sudo rm -- "$installed_descriptor"
        printf 'Removed exact Sway session file: %s\n' "$installed_descriptor"
      fi
    done
  fi
fi
if [[ "$operation" == update-sway ]]; then
  printf 'Sway managed files updated. Log out and back into Sway to reload them.\n'
else
  printf 'Reboot recommended to refresh Ly sessions. No automatic reboot.\n'
fi
printf 'Personal compositor configs retained.\n'
