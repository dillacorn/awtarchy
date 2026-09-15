#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_capture.sh"
POWER_MENU="${ROOT}/config/hypr/scripts/quickshell_power_menu.sh"
POWER_MENU_KEY="${ROOT}/config/hypr/scripts/quickshell_power_menu_key.sh"
POWER_MENU_QML="${ROOT}/config/quickshell/awtarchy/PowerMenu.qml"
HYPR_CONFIG="${ROOT}/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

forbid_text() {
    if grep -Fq -- "$2" "$1"; then
        fail "$3"
    fi
}

first_line_number() {
    grep -Fn -- "$2" "$1" | head -n1 | cut -d: -f1
}

[[ -f "$HELPER" ]] || fail 'lockscreen capture helper is missing'
[[ -f "$POWER_MENU" ]] || fail 'Quickshell Power Menu helper is missing'
[[ -f "$POWER_MENU_KEY" ]] || fail 'pre-map Power Menu key bridge is missing'
[[ -f "$POWER_MENU_QML" ]] || fail 'Quickshell Power Menu QML is missing'
[[ -f "$HYPR_CONFIG" ]] || fail 'Hyprland config is missing'

# The secure capture helper itself must keep the parallel multi-monitor path.
# Intentional literal source-code match.
# shellcheck disable=SC2016
require_text "$HELPER" 'grim -l 1 -o "$output" "$output_file" &' \
    'multi-monitor capture no longer launches grim workers concurrently'

# The compositor must continue owning immediate follow-up action keys before
# Quickshell maps so SUPER+P -> L cannot disappear into the old focused client.
forbid_text "$HYPR_CONFIG" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \
    'SUPER+P still launches Power Menu without first installing compositor key ownership'
require_text "$HYPR_CONFIG" 'hl.define_submap("power-menu-fast"' \
    'default Power Menu path has no compositor-owned pre-map key submap'
require_text "$HYPR_CONFIG" 'hl.define_submap("power-menu-fast-noalt"' \
    'noalt Power Menu path has no compositor-owned pre-map key submap'
require_text "$HYPR_CONFIG" 'hl.dispatch(hl.dsp.submap("power-menu-fast"))' \
    'SUPER+P does not enter the pre-map key submap synchronously'
require_text "$HYPR_CONFIG" 'hl.dispatch(hl.dsp.submap("power-menu-fast-noalt"))' \
    'noalt SUPER+P does not enter its pre-map key submap synchronously'
require_text "$HYPR_CONFIG" 'hl.dispatch(hl.dsp.exec_cmd(power_menu))' \
    'SUPER+P no longer launches the Power Menu after arming compositor input'
require_text "$HYPR_CONFIG" '{ ignore_mods = true }' \
    'pre-map Power Menu actions do not accept a key pressed while SUPER is still held'
require_text "$HYPR_CONFIG" 'quickshell_power_menu_key.sh' \
    'pre-map Power Menu submap does not hand captured actions to the retry bridge'

submap_line="$(first_line_number "$HYPR_CONFIG" 'hl.dispatch(hl.dsp.submap("power-menu-fast"))')"
exec_line="$(first_line_number "$HYPR_CONFIG" 'hl.dispatch(hl.dsp.exec_cmd(power_menu))')"
[[ -n "$submap_line" && -n "$exec_line" && "$submap_line" -lt "$exec_line" ]] \
    || fail 'SUPER+P launches process work before compositor key ownership is active'

require_text "$POWER_MENU_KEY" 'powermenu fastKey' \
    'pre-map key bridge does not target the Power Menu action path'
require_text "$POWER_MENU_KEY" 'sleep ' \
    'pre-map key bridge does not retry while Quickshell/window activation catches up'

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

# Direct secure capture must remain parallel across outputs.
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

# SUPER+P itself must now be capture-free. Opening the Power Menu should only
# start Quickshell and ask QML to show the menu; grim belongs to the later lock
# action, not to menu presentation.
rm -rf -- "$TMP/runtime/awtarchy-lock-transition"
: >"$TMP/grim-open.log"
: >"$TMP/qs-open.log"
PATH="$TMP/bin:$PATH" \
XDG_RUNTIME_DIR="$TMP/runtime" \
XDG_CONFIG_HOME="$TMP/config" \
FAKE_MONITORS="$TMP/monitors.json" \
GRIM_LOG="$TMP/grim-open.log" \
QS_LOG="$TMP/qs-open.log" \
QS_BIN=qs \
    bash "$POWER_MENU" >/dev/null \
    || fail 'SUPER+P immediate-open path failed'

[[ ! -s "$TMP/grim-open.log" ]] \
    || fail 'SUPER+P still performs screenshot work before showing the Power Menu'
require_text "$TMP/qs-open.log" 'powermenu begin' \
    'SUPER+P no longer opens the Power Menu through its immediate IPC entrypoint'
forbid_text "$TMP/qs-open.log" 'powermenu captureWanted' \
    'SUPER+P still coordinates secure capture before displaying the menu'
forbid_text "$TMP/qs-open.log" 'powermenu capturePrepared' \
    'SUPER+P still publishes a prepared capture while opening the menu'
forbid_text "$TMP/qs-open.log" 'powermenu captureFailed' \
    'SUPER+P still treats opening the menu as a capture operation'
forbid_text "$TMP/qs-open.log" 'lockcapture ' \
    'SUPER+P still manipulates lockscreen-editor capture state before displaying the menu'
forbid_text "$TMP/qs-open.log" 'powermenu reveal' \
    'SUPER+P still has a second post-capture reveal phase instead of opening immediately'

# SUPER+P remains a toggle and closing it must also remain capture-free.
: >"$TMP/grim-close.log"
: >"$TMP/qs-close.log"
PATH="$TMP/bin:$PATH" \
XDG_RUNTIME_DIR="$TMP/runtime" \
XDG_CONFIG_HOME="$TMP/config" \
FAKE_MONITORS="$TMP/monitors.json" \
GRIM_LOG="$TMP/grim-close.log" \
QS_LOG="$TMP/qs-close.log" \
QS_BIN=qs \
POWER_BEGIN_RESPONSE=false \
    bash "$POWER_MENU" >/dev/null \
    || fail 'SUPER+P close-toggle path failed'
[[ ! -s "$TMP/grim-close.log" ]] \
    || fail 'SUPER+P close toggle performs screenshot work'

# Lock is the only Power Menu action that must hand off to the fresh secure
# capture path. QML must hide the real layer-surface backing window and any
# open lockscreen editor preview before starting the frozen desktop capture.
require_text "$POWER_MENU_QML" 'function beginFocused()' \
    'Power Menu has no immediate focused-open entrypoint'
require_text "$POWER_MENU_QML" 'openForScreen(focusedScreen());' \
    'SUPER+P does not open the visual Power Menu immediately'
forbid_text "$POWER_MENU_QML" 'armForScreen(focusedScreen());' \
    'SUPER+P still arms a hidden pre-capture Power Menu instead of opening immediately'
require_text "$POWER_MENU_QML" 'function beginLockAction(action)' \
    'Lock action has no deferred capture handoff'
require_text "$POWER_MENU_QML" 'powerWindow.visible = false;' \
    'Lock action does not close the Power Menu before capture'
require_text "$POWER_MENU_QML" 'powerWindow.backingWindowVisible' \
    'Lock action does not verify the real Power Menu backing window is gone before capture'
require_text "$POWER_MENU_QML" 'LockscreenEditor.suppressForLockCapture()' \
    'Lock action does not suppress an open lockscreen editor before capture'
require_text "$POWER_MENU_QML" 'LockscreenEditor.lockCaptureBackingHidden()' \
    'Lock action does not verify editor backing windows are gone before capture'
require_text "$POWER_MENU_QML" 'LockscreenEditor.restoreAfterLockCapture()' \
    'Lock action cannot restore editor state after secure handoff or failure'
require_text "$POWER_MENU_QML" 'startAction(action, freshLockCommand);' \
    'Lock action does not use the fresh secure capture path after closing the menu'
require_text "$POWER_MENU_QML" 'Behavior on opacity' \
    'Power Menu immediate-open path has no fade-in animation'

printf '%s\n' 'PASS: SUPER+P opens capture-free and lock capture is deferred until L'
