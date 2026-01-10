#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# FILE: ~/.config/hypr/scripts/select_theme.sh
#
# Theme picker.
# - Uses fuzzel if available, otherwise wofi.
# - When using fuzzel:
#   - If your fuzzel.ini has an active (uncommented) anchor= in [main] AND waybar is enabled on the focused monitor,
#     this script forces fuzzel's anchor to match the focused monitor's waybar position (top/bottom/left/right).
#   - If anchor= is commented out/removed OR waybar isn't enabled on the focused monitor, it does NOT force an anchor
#     (center/default behavior).
#
# Optional:
#   --from-waybar  Force corner anchor mapping (top-left/bottom-left/etc). Use only when called from waybar button.

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

waybar_enabled_focused() {
  [[ -x "$WAYBAR_SH" ]] || return 1
  [[ "$("$WAYBAR_SH" getenabled-focused 2>/dev/null || echo false)" == "true" ]]
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
    echo "[main]"
    [[ -f "$USER_FUZZEL_CFG" ]] && echo "include=$USER_FUZZEL_CFG"
    [[ -n "$anchor_override" ]] && echo "anchor=$anchor_override"
  } > "$RUNTIME_CFG"

  log "runtime cfg: $RUNTIME_CFG"
  log "anchor_override=${anchor_override:-<none>}"
}

pick_with_fuzzel() {
  local anchor_override=""

  # Only force anchor when user has anchor= active AND waybar is enabled on focused monitor.
  if user_anchor_opt_in && waybar_enabled_focused; then
    anchor_override="$(compute_anchor "$(bar_pos_focused)")"
  fi

  build_runtime_cfg "$anchor_override"

  themes_list \
    | "$FUZZEL_BIN" --dmenu --config "$RUNTIME_CFG" \
        --prompt "Choose theme: " --lines 12 --width 40
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
