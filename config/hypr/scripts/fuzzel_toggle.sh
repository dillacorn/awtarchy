#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/fuzzel_toggle.sh
#
# Toggle a dedicated fuzzel launcher instance (only the instance launched by this script).
#
# Anchor rules:
# - If user passes --anchor/--anchor=..., never override.
# - If --from-waybar is set: always compute a corner anchor based on focused monitor bar position.
# - Otherwise:
#     - If fuzzel.ini has an active anchor= in [main] AND waybar is running, compute a side anchor.
#     - If anchor= is missing/commented OR waybar is not running, do not force anchor (center/default).

set -euo pipefail

FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/fuzzel-toggle"
RUNTIME_CFG="${RUNTIME_DIR}/fuzzel-toggle.ini"

DEFAULT_ARGS=()

DEBUG="${DEBUG:-0}"   # 0=quiet, 1=log, 2=log + run fuzzel in foreground (no nohup)

need() { command -v "$1" >/dev/null 2>&1 || { printf 'missing: %s\n' "$1" >&2; exit 127; }; }
need "$FUZZEL_BIN"
need awk
need pgrep
need pkill
need nohup

log() { [[ "$DEBUG" != "0" ]] && printf '[fuzzel_toggle] %s\n' "$*" >&2 || true; }

usage() {
  cat <<'USAGE'
fuzzel_toggle.sh [--from-waybar] [--focus-loss-exit] [--no-focus-loss-exit] [FUZZEL_ARGS...]

--from-waybar            Force anchor near bar button (corner mapping)
--focus-loss-exit        Force exit-on-keyboard-focus-loss=yes for this launch
--no-focus-loss-exit     Force exit-on-keyboard-focus-loss=no  for this launch

Debug:
  DEBUG=1 fuzzel_toggle.sh --from-waybar
  DEBUG=2 fuzzel_toggle.sh --from-waybar   (foreground, shows real errors)
USAGE
}

EXIT_ON_FOCUS_LOSS_OVERRIDE=""
FROM_WAYBAR="0"
PASSTHRU=()

while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --from-waybar) FROM_WAYBAR="1"; shift ;;
    --focus-loss-exit) EXIT_ON_FOCUS_LOSS_OVERRIDE="yes"; shift ;;
    --no-focus-loss-exit) EXIT_ON_FOCUS_LOSS_OVERRIDE="no"; shift ;;
    *) PASSTHRU+=("$1"); shift ;;
  esac
done

mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

passthru_has_anchor() {
  local a
  for a in "${PASSTHRU[@]}"; do
    case "$a" in
      --anchor|--anchor=*) return 0 ;;
    esac
  done
  return 1
}

waybar_running() {
  pgrep -x waybar >/dev/null 2>&1
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

bar_pos() {
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

ANCHOR_OVERRIDE=""

if ! passthru_has_anchor; then
  if [[ "$FROM_WAYBAR" == "1" ]]; then
    ANCHOR_OVERRIDE="$(compute_anchor "$(bar_pos)")"
  else
    if waybar_running && user_anchor_opt_in; then
      ANCHOR_OVERRIDE="$(compute_anchor "$(bar_pos)")"
    fi
  fi
fi

# Build runtime config without include= (portable).
# fuzzel.ini explicitly allows reopening [main] after other sections. :contentReference[oaicite:1]{index=1}
{
  if [[ -f "$USER_FUZZEL_CFG" ]]; then
    cat "$USER_FUZZEL_CFG"
    echo
  else
    echo "[main]"
  fi

  echo "[main]"
  [[ -n "$ANCHOR_OVERRIDE" ]] && echo "anchor=$ANCHOR_OVERRIDE"
  [[ -n "$EXIT_ON_FOCUS_LOSS_OVERRIDE" ]] && echo "exit-on-keyboard-focus-loss=$EXIT_ON_FOCUS_LOSS_OVERRIDE"
} > "$RUNTIME_CFG"

log "runtime cfg: $RUNTIME_CFG"
log "from_waybar=$FROM_WAYBAR anchor_override=${ANCHOR_OVERRIDE:-<none>} focus_loss=${EXIT_ON_FOCUS_LOSS_OVERRIDE:-<none>}"
log "launch args: ${PASSTHRU[*]:-<none>}"

if [[ "$DEBUG" != "0" ]]; then
  # validates config syntax; exits 0 if ok, 1 otherwise :contentReference[oaicite:2]{index=2}
  if ! "$FUZZEL_BIN" --check-config --config="$RUNTIME_CFG" >/dev/null 2>&1; then
    log "config check failed (run: $FUZZEL_BIN --check-config --config=\"$RUNTIME_CFG\")"
  else
    log "config check ok"
  fi
fi

# Only close the instance launched by this script (matched by --config path).
pids="$(
  (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
  | awk -v m="$RUNTIME_CFG" 'index($0,m){print $1}'
)"

if [[ -n "${pids:-}" ]]; then
  log "closing existing instance: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  for _ in {1..40}; do
    (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
      | awk -v m="$RUNTIME_CFG" 'index($0,m){found=1} END{exit !found}' \
      || exit 0
    sleep 0.025
  done

  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
  exit 0
fi

if [[ "$DEBUG" == "2" ]]; then
  exec "$FUZZEL_BIN" --config="$RUNTIME_CFG" "${DEFAULT_ARGS[@]}" "${PASSTHRU[@]}"
fi

nohup "$FUZZEL_BIN" --config="$RUNTIME_CFG" "${DEFAULT_ARGS[@]}" "${PASSTHRU[@]}" >/dev/null 2>&1 &
disown || true
