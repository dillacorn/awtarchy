#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/hyprbars_toggle.sh
#
# Toggle hyprbars via hyprpm in a floating Alacritty.
# If hyprbars isn't available yet, offer to add the official Hyprland plugins repo via hyprpm.
# Pre-authenticates sudo once so hyprpm's internal sudo calls don't keep prompting.

set -euo pipefail

TERM_CLASS="hyprbars"
TERM_TITLE="hyprbars"

ALACRITTY="$(command -v alacritty || true)"
HYPRPM_BIN="$(command -v hyprpm || true)"

[[ -n "$ALACRITTY" ]] || { printf 'hyprbars-toggle: alacritty not found\n' >&2; exit 1; }
[[ -n "$HYPRPM_BIN" ]] || { printf 'hyprbars-toggle: hyprpm not found\n' >&2; exit 1; }

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCKFILE="${RUNTIME_DIR}/hyprbars-toggle.lockfile"

# prevent double-tap spam
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

# Cache sudo once so hyprpm's internal sudo calls don't keep prompting.
if [[ -z "$SUDO_BIN" ]]; then
  printf 'ERROR: sudo not found (hyprpm requires sudo for plugin install/enable steps).\n' >&2
  exit 1
fi
"$SUDO_BIN" -v

# Keep sudo timestamp alive while this terminal is open.
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
    *) printf 'Cancelled. No changes made.\n'; exit 0 ;;
  esac

  printf '\nhyprpm update\n'
  "$HYPRPM_BIN" update

  printf '\nhyprpm add %s\n' "$REPO_URL"
  if ! "$HYPRPM_BIN" add "$REPO_URL"; then
    if repo_already_added; then
      printf '(repo already added)\n'
    else
      printf 'ERROR: failed to add plugins repo.\n' >&2
      exit 1
    fi
  fi

  printf '\nhyprpm enable %s\n' "$PLUGIN"
  "$HYPRPM_BIN" enable "$PLUGIN"

  printf '\nhyprpm reload\n'
  "$HYPRPM_BIN" reload

  printf '\nInstalled and enabled.\n'
  printf 'Press Super+Alt+T again to toggle hyprbars.\n'
  exit 0
}

action="enable"
if [[ -n "$HYPRCTL_BIN" ]]; then
  if "$HYPRCTL_BIN" plugin list 2>/dev/null | grep -qiE '(^|[^a-zA-Z0-9_])hyprbars([^a-zA-Z0-9_]|$)'; then
    action="disable"
  fi
fi

if [[ "$action" == "enable" ]]; then
  if ! have_hyprbars_in_hyprpm; then
    install_official_plugins_repo
  fi
fi

printf 'hyprpm %s %s\n' "$action" "$PLUGIN"
"$HYPRPM_BIN" "$action" "$PLUGIN"
"$HYPRPM_BIN" reload
BASH
chmod +x "$TMP"

exec "$ALACRITTY" \
  --class "${TERM_CLASS},${TERM_CLASS}" \
  -T "${TERM_TITLE}" \
  -e bash --noprofile --norc "$TMP"
