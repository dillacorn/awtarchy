#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/fuzzel_toggle.sh
# Toggle the *app-launcher* fuzzel instance (close if running, otherwise launch).
# Uses a per-script runtime config so toggle only kills the instance this script launched.

set -euo pipefail

# ───────────────────────────────────────────────────────────────────────────────
# EASY MODIFIERS
# ───────────────────────────────────────────────────────────────────────────────

FUZZEL_BIN="${FUZZEL_BIN:-fuzzel}"
USER_FUZZEL_CFG="${USER_FUZZEL_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/fuzzel/fuzzel.ini}"

# runtime marker config (used to identify this script's instance)
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
RUNTIME_CFG="${RUNTIME_CFG:-$RUNTIME_BASE/fuzzel-toggle.runtime.ini}"

KILL_TIMEOUT_MS="${KILL_TIMEOUT_MS:-250}"
DEFAULT_ARGS=( )   # e.g.: ( --prompt "Apps" )

# ───────────────────────────────────────────────────────────────────────────────

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 127; }; }
need_cmd pgrep
need_cmd pkill
need_cmd awk
need_cmd "$FUZZEL_BIN"

usage() {
  cat <<'EOF'
fuzzel_toggle.sh [--focus-loss-exit] [--no-focus-loss-exit] [FUZZEL_ARGS...]

--focus-loss-exit         Force exit-on-keyboard-focus-loss=yes for this launch
--no-focus-loss-exit      Force exit-on-keyboard-focus-loss=no  for this launch

Notes:
- Do NOT pass --config/--config=... to this script. It uses a runtime config as an instance marker.
- Pass normal fuzzel args normally, e.g.:
    fuzzel_toggle.sh --anchor=bottom-left
    fuzzel_toggle.sh --anchor=bottom-left --focus-loss-exit
EOF
}

# internal override (empty means: don't override, use whatever user config says)
EXIT_ON_FOCUS_LOSS_OVERRIDE=""

# parse our flags, keep the rest for fuzzel
PASSTHRU_ARGS=()
while (($#)); do
  case "$1" in
    --focus-loss-exit)
      EXIT_ON_FOCUS_LOSS_OVERRIDE="yes"
      shift
      ;;
    --no-focus-loss-exit)
      EXIT_ON_FOCUS_LOSS_OVERRIDE="no"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --config|--config=*)
      echo "fuzzel_toggle: refusing --config (script uses its own runtime config marker)" >&2
      exit 2
      ;;
    *)
      PASSTHRU_ARGS+=("$1")
      shift
      ;;
  esac
done

mkdir -p "$RUNTIME_BASE" 2>/dev/null || true

# Build runtime config (always), so we can reliably detect/kill only our own instance.
# This does NOT change your real fuzzel.ini.
{
  echo "[main]"
  [[ -f "$USER_FUZZEL_CFG" ]] && echo "include=$USER_FUZZEL_CFG"
  if [[ -n "$EXIT_ON_FOCUS_LOSS_OVERRIDE" ]]; then
    echo "exit-on-keyboard-focus-loss=$EXIT_ON_FOCUS_LOSS_OVERRIDE"
  fi
} > "$RUNTIME_CFG"

# If our fuzzel instance is running, close it.
# IMPORTANT: neutralize pgrep exit codes under set -e.
pids="$(
  pgrep -u "$UID" -x fuzzel -a 2>/dev/null || true \
  | awk -v m="$RUNTIME_CFG" 'index($0,m){print $1}'
)"

if [[ -n "${pids:-}" ]]; then
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true

  step_ms=25
  steps=$(( (KILL_TIMEOUT_MS + step_ms - 1) / step_ms ))
  for _ in $(seq 1 "$steps"); do
    pgrep -u "$UID" -x fuzzel -a 2>/dev/null | awk -v m="$RUNTIME_CFG" 'index($0,m){found=1} END{exit !found}' || exit 0
    sleep 0.025
  done

  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
  exit 0
fi

# Otherwise, launch it.
# Use "--config <file>" so the runtime cfg path appears in the cmdline for reliable toggling.
nohup "$FUZZEL_BIN" --config "$RUNTIME_CFG" "${DEFAULT_ARGS[@]}" "${PASSTHRU_ARGS[@]}" >/dev/null 2>&1 &
disown
