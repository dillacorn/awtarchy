#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/waybar_flip.sh
#
# Flips Waybar position top<->bottom, updates fuzzel anchor in launcher command(s),
# and closes the *launcher* fuzzel instance (the one started by fuzzel_toggle.sh)
# so it can’t stay open with an old anchor.
#
# Default restart method is pkill+nohup (no systemd dependency).
# Optional: set USE_SYSTEMD=1 to try systemd first (auto-fallback if it fails).

set -euo pipefail

# ───────────────────────────────────────────────────────────────────────────────
# EASY MODIFIERS
# ───────────────────────────────────────────────────────────────────────────────

WAYBAR_CONFIG_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"
WAYBAR_CONFIG_FALLBACK="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"

# Waybar relaunch settings (used only for pkill+nohup path)
WAYBAR_BIN="${WAYBAR_BIN:-waybar}"
WAYBAR_STYLE_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/style.css"
# Extra args if you need them, ex: WAYBAR_EXTRA_ARGS=( -l info )
WAYBAR_EXTRA_ARGS=( )

# Anchor that should be set when Waybar is TOP/BOTTOM
FUZZEL_ANCHOR_FOR_WAYBAR_TOP="top-left"
FUZZEL_ANCHOR_FOR_WAYBAR_BOTTOM="bottom-left"

# Close fuzzel launched by fuzzel_toggle.sh (marker is its runtime --config path)
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
FUZZEL_TOGGLE_RUNTIME_CFG="${FUZZEL_TOGGLE_RUNTIME_CFG:-$RUNTIME_BASE/fuzzel-toggle.runtime.ini}"

# If set to 1, kill ANY fuzzel instance (not just the launcher marker)
KILL_ALL_FUZZEL="${KILL_ALL_FUZZEL:-0}"

FUZZEL_PROC="${FUZZEL_PROC:-fuzzel}"
FUZZEL_KILL_TIMEOUT_MS="${FUZZEL_KILL_TIMEOUT_MS:-250}"

USE_SYSTEMD="${USE_SYSTEMD:-0}"

# ───────────────────────────────────────────────────────────────────────────────

cfg="${WAYBAR_CONFIG:-$WAYBAR_CONFIG_DEFAULT}"
if [[ ! -f "$cfg" && -f "$WAYBAR_CONFIG_FALLBACK" ]]; then
  cfg="$WAYBAR_CONFIG_FALLBACK"
fi

if [[ ! -f "$cfg" ]]; then
  echo "waybar_flip: config not found: $cfg" >&2
  exit 1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "waybar_flip: missing: $1" >&2; exit 127; }; }

close_fuzzel_if_open() {
  need_cmd pgrep
  need_cmd pkill
  need_cmd awk

  local pids=""

  if [[ "$KILL_ALL_FUZZEL" == "1" ]]; then
    if ! pgrep -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1; then
      return 0
    fi
    pkill -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || true
  else
    # Kill only the fuzzel instance launched by fuzzel_toggle.sh (marker in argv).
    # Must neutralize pgrep exit code under set -e.
    local out
    out="$(pgrep -u "$UID" -x "$FUZZEL_PROC" -a 2>/dev/null || true)"

    # match both: --config /path and --config=/path
    pids="$(
      awk -v p="$FUZZEL_TOGGLE_RUNTIME_CFG" '
        index($0,"--config " p) || index($0,"--config=" p) { print $1 }
      ' <<<"$out"
    )"

    [[ -n "${pids:-}" ]] || return 0
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi

  step_ms=25
  steps=$(( (FUZZEL_KILL_TIMEOUT_MS + step_ms - 1) / step_ms ))
  for _ in $(seq 1 "$steps"); do
    pgrep -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || return 0
    sleep 0.025
  done

  pkill -KILL -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || true
}

restart_waybar_pkill() {
  local style="${WAYBAR_STYLE:-$WAYBAR_STYLE_DEFAULT}"
  local args=()

  if [[ "$cfg" != "$WAYBAR_CONFIG_DEFAULT" ]]; then
    args+=( -c "$cfg" )
  fi
  if [[ -f "$style" ]]; then
    args+=( -s "$style" )
  fi
  if (( ${#WAYBAR_EXTRA_ARGS[@]} )); then
    args+=( "${WAYBAR_EXTRA_ARGS[@]}" )
  fi

  pkill -x waybar 2>/dev/null || true
  nohup "$WAYBAR_BIN" "${args[@]}" >/dev/null 2>&1 &
}

restart_waybar() {
  if [[ "$USE_SYSTEMD" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    if systemctl --user cat waybar.service >/dev/null 2>&1; then
      if systemctl --user restart waybar.service >/dev/null 2>&1; then
        return 0
      fi
    fi
  fi
  restart_waybar_pkill
}

set_fuzzel_anchor() {
  local anchor="$1"

  # Handles current Waybar command style:
  #   fuzzel_toggle.sh --anchor=bottom-left --focus-loss-exit
  # and older styles with quoting:
  #   fuzzel_toggle.sh '--anchor=bottom-left'
  # plus direct fuzzel:
  #   fuzzel --anchor=bottom-left
  sed -i -E \
    -e '/fuzzel_toggle\.sh|(^|[^[:alnum:]_])fuzzel([^[:alnum:]_]|$)/{
          s/(--anchor=)[^"'\''[:space:]]+/\1'"${anchor}"'/g;
          s/(--anchor[[:space:]]+)[^"'\''[:space:]]+/\1'"${anchor}"'/g
        }' \
    "$cfg"
}

# Close fuzzel first so it can’t stay open with old anchor.
close_fuzzel_if_open

# Toggle "position": "top" <-> "position": "bottom" and apply matching fuzzel anchor.
if grep -qE '^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"top"' "$cfg"; then
  sed -i -E 's/^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"top"/"position": "bottom"/' "$cfg"
  set_fuzzel_anchor "$FUZZEL_ANCHOR_FOR_WAYBAR_BOTTOM"
elif grep -qE '^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"bottom"' "$cfg"; then
  sed -i -E 's/^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"bottom"/"position": "top"/' "$cfg"
  set_fuzzel_anchor "$FUZZEL_ANCHOR_FOR_WAYBAR_TOP"
else
  echo "waybar_flip: no top-level position key found in $cfg" >&2
  exit 1
fi

restart_waybar
