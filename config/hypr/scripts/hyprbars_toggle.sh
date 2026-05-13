#!/usr/bin/env bash
# ~/.config/hypr/scripts/hyprbars_toggle.sh
#
# Safer hyprbars toggle.
# - Enabling can be applied immediately with hyprpm reload.
# - Disabling is staged for next Hyprland restart to avoid hot-unloading hyprbars and crashing Hyprland.

set -euo pipefail

TERM_CLASS="hyprbars"
TERM_TITLE="hyprbars"

ALACRITTY="$(command -v alacritty || true)"
HYPRPM_BIN="$(command -v hyprpm || true)"

[[ -n "$ALACRITTY" ]] || { printf 'hyprbars-toggle: alacritty not found\n' >&2; exit 1; }
[[ -n "$HYPRPM_BIN" ]] || { printf 'hyprbars-toggle: hyprpm not found\n' >&2; exit 1; }

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCKFILE="${RUNTIME_DIR}/hyprbars-toggle.lockfile"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  flock -n 9 || exit 0
fi

TMP="${RUNTIME_DIR}/hyprbars-toggle.$$.$RANDOM.sh"

cat >"$TMP" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

PLUGIN="hyprbars"
REPO_URL="https://github.com/hyprwm/hyprland-plugins"

HYPRPM_BIN="$(command -v hyprpm)"
HYPRCTL_BIN="$(command -v hyprctl || true)"
SUDO_BIN="$(command -v sudo || true)"

cleanup() {
  [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  rm -f "$0" 2>/dev/null || true
}
trap cleanup EXIT

pause_exit() {
  printf '\nPress ENTER to close...'
  read -r _ || true
}

if [[ -z "$SUDO_BIN" ]]; then
  printf 'ERROR: sudo not found. hyprpm requires sudo.\n' >&2
  pause_exit
  exit 1
fi

"$SUDO_BIN" -v

(
  while true; do
    "$SUDO_BIN" -n true 2>/dev/null || true
    sleep 60
  done
) &
SUDO_KEEPALIVE_PID="$!"

have_hyprbars_in_hyprpm() {
  "$HYPRPM_BIN" list 2>/dev/null | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

repo_already_added() {
  "$HYPRPM_BIN" list 2>/dev/null | grep -qiE '(Repository[[:space:]]+hyprland-plugins:|hyprwm/hyprland-plugins|https://github.com/hyprwm/hyprland-plugins)'
}

hyprbars_loaded() {
  [[ -n "$HYPRCTL_BIN" ]] || return 1
  "$HYPRCTL_BIN" plugin list 2>/dev/null | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'
}

install_official_plugins_repo() {
  printf '\n%s is not available yet.\n' "$PLUGIN"
  printf 'The Hyprland plugins repo is probably not added to hyprpm.\n\n'
  printf 'This will run:\n'
  printf '  hyprpm update\n'
  printf '  hyprpm add %s\n' "$REPO_URL"
  printf '  hyprpm enable %s\n' "$PLUGIN"
  printf '  hyprpm reload\n\n'

  local ans=""
  read -r -p "Install Hyprland plugins now? [y/N] " ans
  case "${ans,,}" in
    y|yes) ;;
    *) printf 'Cancelled. No changes made.\n'; pause_exit; exit 0 ;;
  esac

  "$HYPRPM_BIN" update

  if ! "$HYPRPM_BIN" add "$REPO_URL"; then
    if repo_already_added; then
      printf '(repo already added)\n'
    else
      printf 'ERROR: failed to add plugins repo.\n' >&2
      pause_exit
      exit 1
    fi
  fi
}

printf '\nChecking hyprbars...\n\n'

if hyprbars_loaded; then
  printf 'hyprbars is currently loaded.\n'
  printf 'Not hot-unloading it. Hot-unloading hyprbars can crash Hyprland.\n\n'
  printf 'This will run:\n'
  printf '  hyprpm disable hyprbars\n\n'
  printf 'It will take effect after you log out and back in.\n\n'

  local_ans=""
  read -r -p "Disable hyprbars for next session? [y/N] " local_ans
  case "${local_ans,,}" in
    y|yes) ;;
    *) printf 'Cancelled. No changes made.\n'; pause_exit; exit 0 ;;
  esac

  "$HYPRPM_BIN" disable "$PLUGIN"

  printf '\nHyprbars disabled for next session.\n'
  printf 'Log out and back in. Do not run hyprpm reload to hot-unload it.\n'

  pause_exit
  exit 0
fi

printf 'hyprbars is not currently loaded.\n'

if ! have_hyprbars_in_hyprpm; then
  install_official_plugins_repo
fi

printf '\nhyprpm enable %s\n' "$PLUGIN"
"$HYPRPM_BIN" enable "$PLUGIN"

printf '\nhyprpm reload\n'
"$HYPRPM_BIN" reload

if [[ -n "$HYPRCTL_BIN" ]]; then
  printf '\nhyprctl reload\n'
  "$HYPRCTL_BIN" reload || true

  printf '\nLoaded plugins:\n\n'
  "$HYPRCTL_BIN" plugin list 2>/dev/null || true

  printf '\nConfig errors:\n\n'
  "$HYPRCTL_BIN" configerrors || true
fi

printf '\nHyprbars enabled.\n'
pause_exit
BASH

chmod +x "$TMP"

exec "$ALACRITTY" \
  --class "${TERM_CLASS},${TERM_CLASS}" \
  -T "${TERM_TITLE}" \
  -e bash --noprofile --norc "$TMP"
