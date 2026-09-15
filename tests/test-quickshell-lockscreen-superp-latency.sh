#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_capture.sh"
POWER_MENU="${ROOT}/config/hypr/scripts/quickshell_power_menu.sh"
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

[[ -f "$HELPER" ]] || fail 'lockscreen capture helper is missing'
[[ -f "$POWER_MENU" ]] || fail 'Quickshell Power Menu helper is missing'

require_text "$HELPER" 'stage-promote-clean' \
    'capture helper has no one-snapshot clean-desktop promotion path'
require_text "$POWER_MENU" 'editorHidden' \
    'SUPER+P does not check whether the first snapshot is already a clean desktop'
require_text "$POWER_MENU" 'stage-promote-clean' \
    'SUPER+P does not use the one-snapshot fast path'

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
parallel_capture="$(
    PATH="$TMP/bin:$PATH" \
    XDG_RUNTIME_DIR="$TMP/runtime" \
    FAKE_MONITORS="$TMP/monitors.json" \
    GRIM_LOG="$TMP/grim-parallel.log" \
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
case " $* " in
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
# desktop. SUPER+P must promote that snapshot and open the Power Menu without
# suppressing/restoring the editor or taking a second screenshot pass.
rm -rf -- "$TMP/runtime/awtarchy-lock-transition" "$TMP/barrier-fast"
: >"$TMP/grim-fast.log"
: >"$TMP/qs.log"
PATH="$TMP/bin:$PATH" \
XDG_RUNTIME_DIR="$TMP/runtime" \
XDG_CONFIG_HOME="$TMP/config" \
FAKE_MONITORS="$TMP/monitors.json" \
GRIM_LOG="$TMP/grim-fast.log" \
GRIM_BARRIER_DIR="$TMP/barrier-fast" \
GRIM_EXPECTED_CONCURRENCY=2 \
QS_LOG="$TMP/qs.log" \
QS_BIN=qs \
    bash "$POWER_MENU" >/dev/null \
    || fail 'SUPER+P clean-desktop fast path failed'

[[ "$(wc -l <"$TMP/grim-fast.log")" -eq 2 ]] \
    || fail 'SUPER+P clean fast path performed more than one capture pass'
require_text "$TMP/qs.log" 'lockcapture editorHidden' \
    'SUPER+P did not query clean-desktop readiness'
require_text "$TMP/qs.log" 'powermenu toggle' \
    'SUPER+P did not open the Power Menu after preparing the clean bundle'
forbid_log_text "$TMP/qs.log" 'lockcapture suppressEditor' \
    'SUPER+P unnecessarily suppressed an already-hidden editor'
forbid_log_text "$TMP/qs.log" 'lockcapture restoreEditor' \
    'SUPER+P unnecessarily restored an editor that was never suppressed'

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

printf '%s\n' 'PASS: SUPER+P capture latency fast path'
