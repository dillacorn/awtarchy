#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/hyprbars-toggle.sh

# Toggle hyprbars via hyprpm in a floating Alacritty (hyprpm prompts for password itself).
# No shell init (no fastfetch): bash --noprofile --norc.

set -euo pipefail

TERM_CLASS="hyprbars"
TERM_TITLE="hyprbars"

ALACRITTY="$(command -v alacritty || true)"
HYPRPM="$(command -v hyprpm || true)"

[[ -n "$ALACRITTY" ]] || { printf 'hyprbars-toggle: alacritty not found\n' >&2; exit 1; }
[[ -n "$HYPRPM" ]] || { printf 'hyprbars-toggle: hyprpm not found\n' >&2; exit 1; }

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
HYPRPM="$(command -v hyprpm)"
HYPRCTL="$(command -v hyprctl || true)"

cleanup() {
  rm -f "$0" 2>/dev/null || true
}
trap cleanup EXIT

action="enable"
if [[ -n "$HYPRCTL" ]]; then
  if "$HYPRCTL" plugin list 2>/dev/null | grep -qi "$PLUGIN"; then
    action="disable"
  fi
fi

printf 'hyprpm %s %s\n' "$action" "$PLUGIN"
printf 'When prompted, type your password.\n'

"$HYPRPM" "$action" "$PLUGIN"
"$HYPRPM" reload
BASH
chmod +x "$TMP"

exec "$ALACRITTY" \
  --class "${TERM_CLASS},${TERM_CLASS}" \
  -T "${TERM_TITLE}" \
  -e bash --noprofile --norc "$TMP"
