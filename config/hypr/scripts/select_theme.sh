#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/select_theme.sh
#
# Theme picker.
# - Uses fuzzel if available, otherwise wofi.
# - Waybar-aware anchoring (same detection logic as the fixed cliphist/fuzzel_toggle):
#   - If --from-waybar is set: override anchor to a CORNER near the bar ONLY if waybar is visible on the focused monitor.
#   - Otherwise: override anchor to the bar SIDE (top/bottom/left/right) ONLY if:
#       - your fuzzel.ini has an active (uncommented) anchor= in [main] (opt-in), AND
#       - waybar is visible on the focused monitor.
#   - If waybar is not visible on the focused monitor: do NOT force anchor (your fuzzel.ini anchor=center stays).
#
# Note: avoids relying on fuzzel include=; it copies your fuzzel.ini contents then appends overrides.

set -euo pipefail

DEBUG="${DEBUG:-0}"
log() { [[ "$DEBUG" == "1" ]] && printf '[select_theme] %s\n' "$*" >&2 || true; }

THEME_DIR="${THEME_DIR:-$HOME/.config/hypr/themes}"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPTS_DIR="${CONF_DIR}/hypr/scripts"
WAYBAR_SH="${WAYBAR_SH:-$SCRIPTS_DIR/waybar.sh}"

FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-$CONF_DIR/fuzzel/fuzzel.ini}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/awtarchy"
RUNTIME_CFG="${RUNTIME_DIR}/select_theme.fuzzel.ini"

# Keep the old UI sizing behavior, but do it via config (not CLI flags).
FUZZEL_PROMPT="${FUZZEL_PROMPT:-Choose theme: }"
FUZZEL_LINES="${FUZZEL_LINES:-12}"
FUZZEL_WIDTH="${FUZZEL_WIDTH:-40}"

FROM_WAYBAR="0"
while (( $# )); do
  case "$1" in
    --from-waybar) FROM_WAYBAR="1"; shift ;;
    *) shift ;;
  esac
done

[[ -d "$THEME_DIR" ]] || { printf 'select_theme: missing theme dir: %s\n' "$THEME_DIR" >&2; exit 1; }

themes_list() {
  find "$THEME_DIR" -maxdepth 1 -type f -executable -printf '%f\n' 2>/dev/null | LC_ALL=C sort
}

user_anchor_opt_in() {
  local f="$USER_FUZZEL_CFG"
  [[ -f "$f" ]] || return 1
  awk '
    BEGIN{in_main=0}
    /^[[:space:]]*\[main\][[:space:]]*$/ {in_main=1; next}
    /^[[:space:]]*\[/ {in_main=0}
    in_main {
      if ($0 ~ /^[[:space:]]*[#;]/) next
      if ($0 ~ /^[[:space:]]*anchor[[:space:]]*=/) { found=1; exit }
    }
    END{ exit(found?0:1) }
  ' "$f"
}

# Detect if waybar is actually visible on the focused monitor by matching the
# per-output config path in the waybar process cmdline (same approach you’re using elsewhere).
waybar_visible_on_focused_monitor() {
  local mon safe cache cfg pid comm cmdline

  [[ -x "$WAYBAR_SH" ]] || return 1
  mon="$("$WAYBAR_SH" focused-monitor 2>/dev/null || true)"
  [[ -n "$mon" ]] || return 1

  cache="${XDG_CACHE_HOME:-$HOME/.cache}"
  safe="$(printf '%s' "$mon" | tr $'/ \t' '___')"
  cfg="${cache}/waybar/per-output/${safe}.json"

  [[ -f "$cfg" ]] || return 1

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    [[ -r "/proc/$pid/comm" ]] || continue
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    [[ "$comm" == "waybar" ]] || continue

    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    [[ "$cmdline" == *"$cfg"* ]] && return 0
  done < <(pgrep -x waybar 2>/dev/null || true)

  return 1
}

bar_pos_focused() {
  if [[ -x "$WAYBAR_SH" ]]; then
    "$WAYBAR_SH" getpos-focused 2>/dev/null || echo top
  else
    echo top
  fi
}

compute_anchor() {
  local pos="${1:-top}"
  if [[ "$FROM_WAYBAR" == "1" ]]; then
    case "$pos" in
      top) echo top-left ;;
      bottom) echo bottom-left ;;
      left) echo top-left ;;
      right) echo top-right ;;
      *) echo top-left ;;
    esac
  else
    case "$pos" in
      top|bottom|left|right) echo "$pos" ;;
      *) echo top ;;
    esac
  fi
}

build_runtime_cfg() {
  local anchor_override="${1:-}"

  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

  {
    if [[ -f "$USER_FUZZEL_CFG" ]]; then
      cat "$USER_FUZZEL_CFG"
      echo
    else
      echo "[main]"
    fi

    # Append overrides so they win.
    echo "[main]"
    echo "lines=$FUZZEL_LINES"
    echo "width=$FUZZEL_WIDTH"
    [[ -n "$anchor_override" ]] && echo "anchor=$anchor_override"
    echo

    echo "[dmenu]"
    echo "prompt=$FUZZEL_PROMPT"
  } > "$RUNTIME_CFG"

  log "runtime cfg: $RUNTIME_CFG"
  log "anchor_override=${anchor_override:-<none>}"
}

pick_with_fuzzel() {
  local anchor_override=""

  if [[ "$FROM_WAYBAR" == "1" ]]; then
    if waybar_visible_on_focused_monitor; then
      anchor_override="$(compute_anchor "$(bar_pos_focused)")"
    fi
  else
    if waybar_visible_on_focused_monitor && user_anchor_opt_in; then
      anchor_override="$(compute_anchor "$(bar_pos_focused)")"
    fi
  fi

  build_runtime_cfg "$anchor_override"
  themes_list | "$FUZZEL_BIN" --dmenu --config "$RUNTIME_CFG"
}

pick_with_wofi() {
  themes_list | wofi --dmenu -i -p "Choose theme"
}

THEME=""

if command -v "$FUZZEL_BIN" >/dev/null 2>&1; then
  THEME="$(pick_with_fuzzel || true)"
elif command -v wofi >/dev/null 2>&1; then
  THEME="$(pick_with_wofi || true)"
else
  printf 'select_theme: need fuzzel or wofi\n' >&2
  exit 127
fi

if [[ -n "${THEME:-}" ]]; then
  exec "${THEME_DIR}/${THEME}"
fi
