#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/fuzzel_toggle.sh
#
# Toggle a dedicated fuzzel launcher instance (only the instance launched by this script).
#
# New behavior:
# - If THIS launcher is already open -> close it and exit (toggle).
# - If ANOTHER fuzzel is open (cliphist/select_theme/etc) -> close it, then open the launcher.
#
# Anchor rules:
# - If user passes --anchor/--anchor=..., never override.
# - If --from-waybar is set: compute a corner anchor based on focused monitor bar position,
#   but ONLY if waybar is visible on the focused monitor.
# - Otherwise:
#     - If fuzzel.ini has an active anchor= in [main] AND waybar is visible on the focused monitor,
#       compute a side anchor.
#     - If anchor= is missing/commented OR waybar is not visible on the focused monitor,
#       do not force anchor (your fuzzel.ini anchor applies, e.g. center).

set -euo pipefail
exec </dev/null

FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

SCRIPTS_DIR="${SCRIPTS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts}"
WAYBAR_SH="${WAYBAR_SH:-${SCRIPTS_DIR}/waybar.sh}"

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
RUNTIME_DIR="${RUNTIME_DIR:-$RUNTIME_BASE/fuzzel-toggle}"
RUNTIME_CFG="${RUNTIME_CFG:-$RUNTIME_DIR/fuzzel-toggle.ini}"

# If any other fuzzel is open (cliphist/select_theme/etc), kill it so app launcher can open.
KILL_OTHER_FUZZEL="${KILL_OTHER_FUZZEL:-1}"   # 1=yes, 0=no

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

--from-waybar            Force anchor near bar button (corner mapping) if waybar is visible on focused monitor
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

kill_pids() {
  local pids="${1:-}"
  [[ -n "$pids" ]] || return 0

  log "killing fuzzel pid(s): $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  for _ in {1..12}; do
    local alive=0 pid
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null && alive=1 || true
    done
    [[ "$alive" == "0" ]] && break
    sleep 0.05
  done

  local still=0 pid
  for pid in $pids; do
    kill -0 "$pid" 2>/dev/null && still=1 || true
  done

  if [[ "$still" == "1" ]]; then
    log "still alive after TERM; sending KILL"
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null || true
    sleep 0.05
  fi

  # If no fuzzel is running, clean stale lock(s) so new instance can start.
  if ! pgrep -u "$UID" -x fuzzel >/dev/null 2>&1; then
    rm -f -- "$RUNTIME_BASE"/fuzzel-*.lock 2>/dev/null || true
  fi
}

ours_pids() {
  (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" 'index($0,m){print $1}'
}

other_pids() {
  (pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true) \
    | awk -v m="$RUNTIME_CFG" '!index($0,m){print $1}'
}

# Detect if waybar is actually visible on the focused monitor by matching the
# per-output config path in the waybar process cmdline.
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

# Toggle: if OUR instance is open, close it and exit.
pids="$(ours_pids || true)"
if [[ -n "${pids:-}" ]]; then
  log "closing existing launcher instance: $pids"
  kill_pids "$pids"
  exit 0
fi

# If opening, kill OTHER fuzzel instances first so this launcher actually appears.
if [[ "$KILL_OTHER_FUZZEL" == "1" ]]; then
  opids="$(other_pids || true)"
  [[ -n "${opids:-}" ]] && kill_pids "$opids"
fi

ANCHOR_OVERRIDE=""
if ! passthru_has_anchor; then
  if [[ "$FROM_WAYBAR" == "1" ]]; then
    if waybar_visible_on_focused_monitor; then
      ANCHOR_OVERRIDE="$(compute_anchor "$(bar_pos)")"
    fi
  else
    if waybar_visible_on_focused_monitor && user_anchor_opt_in; then
      ANCHOR_OVERRIDE="$(compute_anchor "$(bar_pos)")"
    fi
  fi
fi

# Build runtime config without include= (portable).
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
  if ! "$FUZZEL_BIN" --check-config --config="$RUNTIME_CFG" >/dev/null 2>&1; then
    log "config check failed (run: $FUZZEL_BIN --check-config --config=\"$RUNTIME_CFG\")"
  else
    log "config check ok"
  fi
fi

if [[ "$DEBUG" == "2" ]]; then
  exec "$FUZZEL_BIN" --config="$RUNTIME_CFG" "${DEFAULT_ARGS[@]}" "${PASSTHRU[@]}"
fi

nohup "$FUZZEL_BIN" --config="$RUNTIME_CFG" "${DEFAULT_ARGS[@]}" "${PASSTHRU[@]}" >/dev/null 2>&1 &
disown || true
