#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/waybar_flip.sh
#
# Flips Waybar position top<->bottom, updates fuzzel anchor in launcher command(s),
# and closes fuzzel if it's open (to avoid stale anchor / visual weirdness).
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

# Anchor that should be set when Waybar is TOP/BOTTOM (set these how you want).
# If you want "opposite" behavior, swap them:
#   FUZZEL_ANCHOR_FOR_WAYBAR_TOP="bottom-left"
#   FUZZEL_ANCHOR_FOR_WAYBAR_BOTTOM="top-left"
FUZZEL_ANCHOR_FOR_WAYBAR_TOP="top-left"
FUZZEL_ANCHOR_FOR_WAYBAR_BOTTOM="bottom-left"

# Close fuzzel when flipping.
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

  if ! pgrep -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1; then
    return 0
  fi

  pkill -u "$UID" -x "$FUZZEL_PROC" >/dev/null 2>&1 || true

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

  # Update anchor only on lines that mention fuzzel or your toggle script.
  # Handles:
  #   fuzzel --anchor=top-left
  #   fuzzel_toggle.sh '--anchor=top-left'
  #   fuzzel_toggle.sh "--anchor=top-left"
  #   --anchor top-left
  sed -i -E \
    -e '/fuzzel_toggle\.sh|(^|[^[:alnum:]_])fuzzel([^[:alnum:]_]|$)/{
          s/(--anchor=)[^"'\''[:space:]]+/\1'"${anchor}"'/g;
          s/(--anchor[[:space:]]+)[^"'\''[:space:]]+/\1'"${anchor}"'/g
        }' \
    "$cfg"
}

# Always close fuzzel first so it doesn't stay open with old anchor.
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
