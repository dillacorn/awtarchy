#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/waybar_flip.sh
#
# Flips Waybar position top<->bottom.
#
# fuzzel behavior:
# - Waybar module "custom/apps" (the launcher button) gets:
#     Waybar TOP    -> --anchor=top-left
#     Waybar BOTTOM -> --anchor=bottom-left
# - Keyboard binds (no explicit --anchor) should follow fuzzel.ini:
#     Waybar TOP    -> anchor=top
#     Waybar BOTTOM -> anchor=bottom
# - If Waybar is NOT running, fuzzel.ini anchor (if present+active) is set to "center".
# - If the user removes or comments out anchor= in fuzzel.ini, this script will NOT add it back.
#
# Waybar restart:
# - Only restarts Waybar if it was already running.

set -euo pipefail

# ───────────────────────────────────────────────────────────────────────────────
# EASY MODIFIERS
# ───────────────────────────────────────────────────────────────────────────────

WAYBAR_CONFIG_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"
WAYBAR_CONFIG_FALLBACK="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"

# Waybar relaunch settings (used only for pkill+nohup path)
WAYBAR_BIN="${WAYBAR_BIN:-waybar}"
WAYBAR_STYLE_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/style.css"
WAYBAR_EXTRA_ARGS=( )

# fuzzel ini (persistent default spawn anchor for binds that don't pass --anchor)
FUZZEL_INI_PATH="${FUZZEL_INI_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

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

waybar_is_running() {
  need_cmd pgrep
  pgrep -u "$UID" -x waybar >/dev/null 2>&1
}

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

  local step_ms=25
  local steps=$(( (FUZZEL_KILL_TIMEOUT_MS + step_ms - 1) / step_ms ))
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

# Update ONLY the "custom/apps" module's command strings to the provided anchor.
set_waybar_custom_apps_anchor() {
  need_cmd awk
  local anchor="$1"
  local tmp="${cfg}.tmp.$$"

  awk -v a="$anchor" '
    function sub_anchor(line,   l) {
      l=line
      gsub(/--anchor=[^"'\''[:space:]]+/, "--anchor=" a, l)
      gsub(/--anchor[[:space:]]+[^"'\''[:space:]]+/, "--anchor " a, l)
      return l
    }

    BEGIN { in_apps=0; depth=0 }

    {
      line=$0

      if (!in_apps && line ~ /"custom\/apps"[[:space:]]*:[[:space:]]*{/) {
        in_apps=1
        depth=0
      }

      if (in_apps) {
        if (line ~ /fuzzel_toggle\.sh/ || line ~ /(^|[^[:alnum:]_])fuzzel([^[:alnum:]_]|$)/) {
          line=sub_anchor(line)
        }

        # naive brace depth; good enough for typical waybar configs
        tmpc=line
        opens=gsub(/{/,"{",tmpc)
        closes=gsub(/}/,"}",tmpc)
        depth += opens - closes
        if (depth == 0) {
          in_apps=0
        }
      }

      print line
    }
  ' "$cfg" >"$tmp" && mv "$tmp" "$cfg"
}

has_active_fuzzel_anchor_in_main() {
  local ini="$1"
  awk '
    BEGIN { inmain=0; found=0 }
    /^\[main\]$/ { inmain=1; next }
    /^\[/        { inmain=0; next }
    {
      if (inmain &&
          $0 ~ /^[[:space:]]*anchor[[:space:]]*=/ &&
          $0 !~ /^[[:space:]]*[#;]/) { found=1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$ini"
}

set_fuzzel_ini_anchor_if_user_has_one() {
  need_cmd awk
  local anchor="$1"
  local ini="$FUZZEL_INI_PATH"

  [[ -f "$ini" ]] || return 0
  has_active_fuzzel_anchor_in_main "$ini" || return 0

  awk -v a="$anchor" '
    BEGIN { inmain=0 }
    /^\[main\]$/ { inmain=1; print; next }
    /^\[/        { inmain=0; print; next }
    {
      if (inmain &&
          $0 ~ /^[[:space:]]*anchor[[:space:]]*=/ &&
          $0 !~ /^[[:space:]]*[#;]/) {
        sub(/^[[:space:]]*anchor[[:space:]]*=.*/, "anchor=" a)
        print
        next
      }
      print
    }
  ' "$ini" >"$ini.tmp" && mv "$ini.tmp" "$ini"
}

WAYBAR_WAS_RUNNING=0
if waybar_is_running; then
  WAYBAR_WAS_RUNNING=1
fi

# Close launcher fuzzel first so it can’t stay open with the old anchor.
close_fuzzel_if_open

# Flip and compute anchors based on the NEW bar position.
if grep -qE '^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"top"' "$cfg"; then
  # top -> bottom
  sed -i -E 's/^([[:space:]]*)"position"[[:space:]]*:[[:space:]]*"top"/\1"position": "bottom"/' "$cfg"

  # Waybar launcher button: bottom-left
  set_waybar_custom_apps_anchor "bottom-left"

  # Binds default (fuzzel.ini): bottom, or center if waybar not running
  if [[ "$WAYBAR_WAS_RUNNING" == "1" ]]; then
    set_fuzzel_ini_anchor_if_user_has_one "bottom"
  else
    set_fuzzel_ini_anchor_if_user_has_one "center"
  fi

elif grep -qE '^[[:space:]]*"position"[[:space:]]*:[[:space:]]*"bottom"' "$cfg"; then
  # bottom -> top
  sed -i -E 's/^([[:space:]]*)"position"[[:space:]]*:[[:space:]]*"bottom"/\1"position": "top"/' "$cfg"

  # Waybar launcher button: top-left
  set_waybar_custom_apps_anchor "top-left"

  # Binds default (fuzzel.ini): top, or center if waybar not running
  if [[ "$WAYBAR_WAS_RUNNING" == "1" ]]; then
    set_fuzzel_ini_anchor_if_user_has_one "top"
  else
    set_fuzzel_ini_anchor_if_user_has_one "center"
  fi

else
  echo "waybar_flip: no top-level position key found in $cfg" >&2
  exit 1
fi

# Only restart Waybar if it was already running.
if [[ "$WAYBAR_WAS_RUNNING" == "1" ]]; then
  restart_waybar
fi
