#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_capture.sh"
POWER_MENU="${ROOT}/config/hypr/scripts/quickshell_power_menu.sh"
POWER_MENU_QML="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

forbid_log_text() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

first_line_number() {
    grep -Fn -- "$2" "$1" | head -n1 | cut -d: -f1
}

last_line_number() {
    grep -Fn -- "$2" "$1" | tail -n1 | cut -d: -f1
}

[[ -f "$HELPER" ]] || fail 'lockscreen capture helper is missing'
[[ -f "$POWER_MENU" ]] || fail 'Quickshell Power Menu helper is missing'
[[ -f "$POWER_MENU_QML" ]] || fail 'Quickshell Power Menu QML is missing'

require_text "$HELPER" 'stage-promote-clean' \
    'capture helper has no one-snapshot clean-desktop promotion path'
require_text "$POWER_MENU" 'editorHidden' \
    'SUPER+P does not check whether the first snapshot is already a clean desktop'
require_text "$POWER_MENU" 'stage-promote-clean' \
    'SUPER+P does not use the one-snapshot fast path'
require_text "$POWER_MENU_QML" 'property bool visualReady: false' \
    'Power Menu cannot arm keyboard input before its visuals are revealed'
require_text "$POWER_MENU_QML" 'property var queuedAction: null' \
    'Power Menu cannot retain an action pressed while capture is still preparing'
require_text "$POWER_MENU_QML" 'function begin(): bool' \
    'Power Menu IPC has no immediate input-arm entrypoint'
require_text "$POWER_MENU_QML" 'function capturePrepared(): bool' \
    'Power Menu IPC cannot release a queued action when capture becomes ready'
require_text "$POWER_MENU_QML" 'if (capturePreparing && action.key === "l")' \
    'Power Menu does not queue an immediate Lock key while secure capture is preparing'
require_text "$POWER_MENU_QML" 'queuedAction = action;' \
    'Power Menu drops an action pressed before the visible menu appears'

mkdir -p "$TMP/bin" "$TMP/runtime" "$TMP/config/hypr/scripts"
chmod 700 "$TMP/runtime"
printf '%s\n' '[{"name":"DP-1"},{"name":"HDMI-A-1"}]' >"$TMP/monitors.json"

cat >"$TMP/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == monitors && "${2:-}" == -j ]] || exit 2
cat -- "$FAKE_MONITORS"
SH
chmod +x "$TMP/bin/hyprctl"

cat >"$TMP/bin/grim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
destination=""
while (($#)); do
    case "$1" in
        -l)
            shift 2
            ;;
        -o)
            output="${2:-}"
            shift 2
            ;;
        *)
            destination="$1"
            shift
            ;;
    esac
done
[[ -n "$output" && -n "$destination" ]] || exit 2
printf '%s\n' "$output" >>"$GRIM_LOG"
printf 'grim:%s\n' "$output" >>"$EVENT_LOG"
if [[ -n "${GRIM_BARRIER_DIR:-}" ]]; then
    mkdir -p -- "$GRIM_BARRIER_DIR"
    : >"$GRIM_BARRIER_DIR/$output"
    ready=0
    for _ in {1..100}; do
        ready="$(find "$GRIM_BARRIER_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l)"
        (( ready >= GRIM_EXPECTED_CONCURRENCY )) && break
        sleep 0.01
    done
    (( ready >= GRIM_EXPECTED_CONCURRENCY )) || exit 70
fi
printf 'PNG:%s\n' "$output" >"$destination"
SH
chmod +x "$TMP/bin/grim"

# A multi-monitor capture must launch all grim workers before waiting for any
# one of them. The barrier deliberately makes a serial loop fail.
: >"$TMP/grim-parallel.log"
: >"$TMP/events-parallel.log"
parallel_capture="$(
    PATH="$TMP/bin:$PATH" \
    XDG_RUNTIME_DIR="$TMP/runtime" \
    FAKE_MONITORS="$TMP/monitors.json" \
    GRIM_LOG="$TMP/grim-parallel.log" \
    EVENT_LOG="$TMP/events-parallel.log" \
    GRIM_BARRIER_DIR="$TMP/barrier-parallel" \
    GRIM_EXPECTED_CONCURRENCY=2 \
        bash "$HELPER" prepare
)" || fail 'multi-monitor capture is still serialized'
[[ "$(wc -l <"$TMP/grim-parallel.log")" -eq 2 ]] \
    || fail 'parallel capture did not invoke exactly one grim worker per output'
PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" cleanup "$parallel_capture"

cp -- "$HELPER" "$TMP/config/hypr/scripts/quickshell_lockscreen_capture.sh"
chmod +x "$TMP/config/hypr/scripts/quickshell_lockscreen_capture.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'exit 0' \
    >"$TMP/config/hypr/scripts/quickshell.sh"
chmod +x "$TMP/config/hypr/scripts/quickshell.sh"

cat >"$TMP/bin/qs" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$QS_LOG"
printf '\n' >>"$QS_LOG"
printf 'qs:%s\n' "$*" >>"$EVENT_LOG"
case " $* " in
    *' powermenu begin '*)
        printf '%s\n' "${POWER_BEGIN_RESPONSE:-true}"
        ;;
    *' powermenu captureWanted '*)
        printf '%s\n' true
        ;;
    *' powermenu capturePrepared '*)
        printf '%s\n' true
        ;;
    *' lockcapture editorHidden '*)
        printf '%s\n' true
        ;;
    *' lockcapture suppressEditor '*)
        printf '%s\n' true
        ;;
    *' lockcapture restoreEditor '*)
        printf '%s\n' true
        ;;
esac
SH
chmod +x "$TMP/bin/qs"

# With no editor backing window mapped, the first capture is already a clean
# desktop. SUPER+P must arm the invisible keyboard surface before grim starts,
# then promote that one snapshot and only reveal visuals after capture is ready.
rm -rf -- "$TMP/runtime/awtarchy-lock-transition" "$TMP/barrier-fast"
: >"$TMP/grim-fast.log"
: >"$TMP/qs.log"
: >"$TMP/events-fast.log"
PATH="$TMP/bin:$PATH" \
XDG_RUNTIME_DIR="$TMP/runtime" \
XDG_CONFIG_HOME="$TMP/config" \
FAKE_MONITORS="$TMP/monitors.json" \
GRIM_LOG="$TMP/grim-fast.log" \
EVENT_LOG="$TMP/events-fast.log" \
GRIM_BARRIER_DIR="$TMP/barrier-fast" \
GRIM_EXPECTED_CONCURRENCY=2 \
QS_LOG="$TMP/qs.log" \
QS_BIN=qs \
    bash "$POWER_MENU" >/dev/null \
    || fail 'SUPER+P clean-desktop fast path failed'

[[ "$(wc -l <"$TMP/grim-fast.log")" -eq 2 ]] \
    || fail 'SUPER+P clean fast path performed more than one capture pass'
require_text "$TMP/qs.log" 'powermenu begin' \
    'SUPER+P does not arm Power Menu keyboard input before capture'
require_text "$TMP/qs.log" 'powermenu captureWanted' \
    'SUPER+P cannot cancel capture after an early non-lock action'
require_text "$TMP/qs.log" 'lockcapture editorHidden' \
    'SUPER+P did not query clean-desktop readiness'
require_text "$TMP/qs.log" 'powermenu capturePrepared' \
    'SUPER+P does not release queued input after publishing the secure capture'
require_text "$TMP/qs.log" 'powermenu reveal' \
    'SUPER+P does not reveal the Power Menu after capture preparation'
forbid_log_text "$TMP/qs.log" 'powermenu toggle' \
    'SUPER+P still waits until after capture before activating the Power Menu'
forbid_log_text "$TMP/qs.log" 'lockcapture suppressEditor' \
    'SUPER+P unnecessarily suppressed an already-hidden editor'
forbid_log_text "$TMP/qs.log" 'lockcapture restoreEditor' \
    'SUPER+P unnecessarily restored an editor that was never suppressed'

begin_line="$(first_line_number "$TMP/events-fast.log" 'powermenu begin')"
first_grim_line="$(first_line_number "$TMP/events-fast.log" 'grim:')"
last_grim_line="$(last_line_number "$TMP/events-fast.log" 'grim:')"
reveal_line="$(first_line_number "$TMP/events-fast.log" 'powermenu reveal')"
[[ -n "$begin_line" && -n "$first_grim_line" && "$begin_line" -lt "$first_grim_line" ]] \
    || fail 'Power Menu keyboard input is not armed before the screenshot latency window'
[[ -n "$reveal_line" && -n "$last_grim_line" && "$reveal_line" -gt "$last_grim_line" ]] \
    || fail 'Power Menu visuals are revealed before the clean screenshot finishes'

prepared="$(
    PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
        bash "$TMP/config/hypr/scripts/quickshell_lockscreen_capture.sh" consume-prepared
)" || fail 'SUPER+P fast path did not publish a consumable capture bundle'
for output in DP-1 HDMI-A-1; do
    [[ -s "$prepared/$output.transition.png" ]] \
        || fail "fast path transition frame is missing for $output"
    [[ -s "$prepared/$output.png" ]] \
        || fail "fast path clean desktop frame is missing for $output"
done
PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$TMP/config/hypr/scripts/quickshell_lockscreen_capture.sh" cleanup "$prepared"

# SUPER+P is still a toggle. If begin reports that it closed an already-open
# menu, the helper must stop immediately and must not pay for any grim capture.
rm -rf -- "$TMP/runtime/awtarchy-lock-transition" "$TMP/barrier-close"
: >"$TMP/grim-close.log"
: >"$TMP/qs-close.log"
: >"$TMP/events-close.log"
PATH="$TMP/bin:$PATH" \
XDG_RUNTIME_DIR="$TMP/runtime" \
XDG_CONFIG_HOME="$TMP/config" \
FAKE_MONITORS="$TMP/monitors.json" \
GRIM_LOG="$TMP/grim-close.log" \
EVENT_LOG="$TMP/events-close.log" \
GRIM_BARRIER_DIR="$TMP/barrier-close" \
GRIM_EXPECTED_CONCURRENCY=2 \
QS_LOG="$TMP/qs-close.log" \
QS_BIN=qs \
POWER_BEGIN_RESPONSE=false \
    bash "$POWER_MENU" >/dev/null \
    || fail 'SUPER+P close toggle path failed'

[[ ! -s "$TMP/grim-close.log" ]] \
    || fail 'SUPER+P close toggle still performs screenshot work after closing the menu'
require_text "$TMP/qs-close.log" 'powermenu begin' \
    'SUPER+P close toggle did not use the immediate begin entrypoint'
forbid_log_text "$TMP/qs-close.log" 'powermenu captureWanted' \
    'SUPER+P close toggle continued into capture coordination'
forbid_log_text "$TMP/qs-close.log" 'powermenu reveal' \
    'SUPER+P close toggle reopened visuals after closing the menu'

printf '%s\n' 'PASS: SUPER+P capture latency and immediate input arming'
