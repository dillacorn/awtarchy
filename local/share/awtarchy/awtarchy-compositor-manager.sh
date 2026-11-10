#!/usr/bin/env bash
# Jay trial compositor management. Protect personal configs and package ownership.
set -euo pipefail

[[ $(id -u) -ne 0 ]] || { printf 'Run as your normal user.\n' >&2; exit 1; }
operation="$1"
mode="$2"
remove_deps="$3"
[[ "$mode" == plan || "$mode" == apply ]] || { printf 'Invalid mode.\n' >&2; exit 2; }
[[ "$remove_deps" == yes || "$remove_deps" == no ]] || { printf 'Invalid dependency choice.\n' >&2; exit 2; }
ledger=/var/lib/awtarchy/managed-packages
source_file="$HOME/.local/state/awtarchy/compositor-trial-source"
session_file=/usr/share/wayland-sessions/awtarchy-jay-trial.desktop
fail() { printf 'Awtarchy compositor: %s\n' "$*" >&2; return 1; }
installed() { pacman -Qq "$1" >/dev/null 2>&1; }
owned() { [[ -f "$ledger" && ! -L "$ledger" ]] && grep -Fxq -- "$1" "$ledger"; }
status() {
  for pkg in hyprland jay; do
    if installed "$pkg"; then printf '%s: installed\n' "$pkg"; else printf '%s: absent\n' "$pkg"; fi
  done
  if [[ -f "$session_file" ]]; then printf 'Jay Ly entry: present\n'; else printf 'Jay Ly entry: missing\n'; fi
  for pkg in vulkan-radeon vulkan-intel nvidia-utils vulkan-nouveau; do
    if installed "$pkg"; then printf 'GPU Vulkan package: %s\n' "$pkg"; fi
  done
  printf 'Jay uses upstream Vulkan defaults; graphics driver selection is not changed.\n'
}
if [[ "$operation" == status ]]; then status; exit 0; fi
case "$operation" in
  install-jay|install-hyprland|remove-jay|remove-hyprland|update-jay) ;;
  *) fail 'Unknown operation'; exit 2 ;;
esac
[[ -f "$source_file" && ! -L "$source_file" && -O "$source_file" ]] ||
  { fail 'Source not registered; refresh command from Jay trial checkout'; exit 1; }
IFS= read -r repo < "$source_file" || :
[[ "$repo" == /* && -d "$repo/.git" && ! -L "$repo" ]] ||
  { fail 'Trial source checkout no longer available'; exit 1; }
[[ "$(git -C "$repo" branch --show-current)" == JayWM_Migration_Trial_Investigation ]] ||
  { fail 'Trial source changed branch'; exit 1; }
[[ -f "$repo/trials/jay/setup.sh" && -f "$repo/config/hypr/hyprland.lua" ]] ||
  { fail 'Trial source incomplete'; exit 1; }
printf 'Action: %s\n' "$operation"
printf 'Personal configs are preserved. Shared packages are preserved.\n'
if [[ "$operation" == update-jay ]]; then
  printf 'Review/apply Jay managed helper and Quickshell updates; personal TOML and modified files remain preserved.\n'
elif [[ "$operation" == install-jay ]]; then
  printf 'Jay via aur-scan; Arch/Quickshell dependencies via pacman.\n'
elif [[ "$operation" == install-hyprland ]]; then
  printf 'Hyprland and its compositor packages via pacman; existing config preserved.\n'
else
  if [[ "$operation" == remove-jay ]]; then
    if [[ "$remove_deps" == yes ]]; then
      packages='swaylock lxqt-policykit jay'
    else packages='jay'; fi
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
    update-jay)
      python3 "$repo/trials/jay/sync.py" review --repo "$repo" ;;
    install-hyprland)
      python3 "$repo/trials/jay/stage-hyprland.py" --preview --repo "$repo" ;;
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
if [[ "$operation" == install-jay ]]; then
  for pkg in quickshell qt6-multimedia qt6-multimedia-ffmpeg foot fuzzel mako swaylock grim slurp wl-clipboard cliphist xdg-desktop-portal-gtk libnotify jq python pipewire lxqt-policykit playerctl; do
    add_pkg "$pkg"
  done
  if ! installed jay; then
    command -v aur-scan >/dev/null 2>&1 || { fail 'aur-scan required for Jay'; exit 1; }
    aur-scan install jay --noconfirm
    installed jay || { fail 'Jay installation unverified'; exit 1; }
    record jay
  fi
  bash "$repo/trials/jay/setup.sh" --check
  bash "$repo/trials/jay/setup.sh" --install
  baseline="$HOME/.local/state/awtarchy/jay-managed-baseline.json"
  if [[ ! -e "$baseline" && ! -L "$baseline" ]]; then
    python3 "$repo/trials/jay/sync.py" record --repo "$repo"
  fi
elif [[ "$operation" == update-jay ]]; then
  # Apply the previewed managed diff; no package operations or compositor
  # removals are reachable through this branch.
  python3 "$repo/trials/jay/sync.py" apply --repo "$repo"
elif [[ "$operation" == install-hyprland ]]; then
  # Validate every destination before installing anything. Copy only missing
  # Awtarchy scripts, shaders, configuration and shared shell files.
  python3 "$repo/trials/jay/stage-hyprland.py" --preview --repo "$repo"
  for pkg in hyprland hyprland-qt-support hyprpaper hypridle hyprpicker hyprsunset \
      xdg-desktop-portal-hyprland quickshell foot fuzzel mako grim slurp \
      wl-clipboard cliphist jq python pipewire playerctl; do
    add_pkg "$pkg"
  done
  python3 "$repo/trials/jay/stage-hyprland.py" --apply --repo "$repo"
  [[ -f /usr/share/wayland-sessions/hyprland.desktop ]] ||
    { fail 'The Hyprland package did not provide a usable Ly Wayland session entry'; exit 1; }
else
  desktop_name=""
  if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then desktop_name="$XDG_CURRENT_DESKTOP"; fi
  if [[ "$operation" == remove-jay ]]; then
    other=hyprland
    target=jay
    [[ "$desktop_name" != jay ]] || { fail 'Cannot remove running Jay'; exit 1; }
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$(id -u)" -x jay >/dev/null 2>&1; then
      fail 'Jay is still running on another TTY. Stop that session before removal.'; exit 1
    fi
  else
    other=jay
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
  if [[ "$target" == jay ]] && ! installed jay; then
    # Remove only exact unmanaged fallback descriptors from this trial.
    # A descriptor still owned by any package must be left to pacman.
    for descriptor in "jay.desktop:$session_file" \
        "jay.portal:/usr/share/xdg-desktop-portal/portals/jay.portal"; do
      source_descriptor="${descriptor%%:*}"
      installed_descriptor="${descriptor#*:}"
      if [[ -f "$installed_descriptor" && ! -L "$installed_descriptor" ]] &&
          [[ -f "$repo/trials/jay/$source_descriptor" &&
             ! -L "$repo/trials/jay/$source_descriptor" ]] &&
          cmp -s "$repo/trials/jay/$source_descriptor" "$installed_descriptor" &&
          ! pacman -Qo -- "$installed_descriptor" >/dev/null 2>&1; then
        sudo rm -- "$installed_descriptor"
        printf 'Removed exact unowned Jay session descriptor: %s\n' "$installed_descriptor"
      fi
    done
  fi
fi
if [[ "$operation" == update-jay ]]; then
  printf 'Jay managed files updated. Log out and back into Jay to reload them.\n'
else
  printf 'Reboot recommended to refresh Ly sessions. No automatic reboot.\n'
fi
printf 'Personal compositor configs retained.\n'
