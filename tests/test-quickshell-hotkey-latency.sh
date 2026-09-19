#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

CONFIG_HOME="$TMP/config"
BIN="$TMP/bin"
LOG="$TMP/calls.log"
COUNT="$TMP/qs-count"

mkdir -p "$CONFIG_HOME/hypr/scripts" "$BIN"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

cat >"$BIN/qs" <<'EOF_QS'
#!/usr/bin/env bash
set -euo pipefail

count=0
if [[ -r "${AWTARCHY_TEST_QS_COUNT:?}" ]]; then
    read -r count <"${AWTARCHY_TEST_QS_COUNT}"
fi
count=$((count + 1))
printf '%s\n' "$count" >"${AWTARCHY_TEST_QS_COUNT}"

{
    printf 'qs'
    printf ' %s' "$@"
    printf '\n'
} >>"${AWTARCHY_TEST_LOG:?}"

if [[ ${AWTARCHY_TEST_QS_FAIL_FIRST:-0} == 1 && $count -eq 1 ]]; then
    exit 1
fi

if [[ -n ${AWTARCHY_TEST_QS_RESULT:-} ]]; then
    printf '%s\n' "$AWTARCHY_TEST_QS_RESULT"
fi
EOF_QS

cat >"$BIN/hyprctl" <<'EOF_HYPR'
#!/usr/bin/env bash
exit 0
EOF_HYPR

cat >"$CONFIG_HOME/hypr/scripts/quickshell.sh" <<'EOF_MANAGER'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'manager'
    printf ' %s' "$@"
    printf '\n'
} >>"${AWTARCHY_TEST_LOG:?}"
EOF_MANAGER

chmod 0755 "$BIN/qs" "$BIN/hyprctl" "$CONFIG_HOME/hypr/scripts/quickshell.sh"

TEST_ENV=(
    "XDG_CONFIG_HOME=$CONFIG_HOME"
    "PATH=$BIN:$PATH"
    "AWTARCHY_TEST_LOG=$LOG"
    "AWTARCHY_TEST_QS_COUNT=$COUNT"
    "AWTARCHY_TEST_QS_RESULT=true"
)

run_script() {
    local script="$1"
    shift
    env "${TEST_ENV[@]}" "$@" bash "$ROOT/$script"
}

assert_hot_path() {
    local script="$1"
    shift
    : >"$LOG"
    rm -f -- "$COUNT"
    run_script "$script" "$@"
    if grep -Fq -- 'manager ' "$LOG"; then
        fail "$script invoked quickshell.sh on the running-shell hot path"
    fi
    grep -Fq -- 'qs -c awtarchy ipc call' "$LOG" \
        || fail "$script did not attempt direct Quickshell IPC"
}

for script in \
    config/hypr/scripts/quickshell_quick_settings_toggle.sh \
    config/hypr/scripts/quickshell_notifications_toggle.sh \
    config/hypr/scripts/quickshell_clipboard_toggle.sh \
    config/hypr/scripts/quickshell_lockscreen_editor.sh \
    config/hypr/scripts/theme_select.sh \
    config/hypr/scripts/quickshell_notification_dismiss.sh \
    config/hypr/scripts/quickshell_bar_flip.sh \
    config/hypr/scripts/quickshell_bar_rotate.sh \
    config/hypr/scripts/quickshell_bar_toggle.sh
do
    assert_hot_path "$script"
done

assert_hot_path config/hypr/scripts/quickshell_power_menu.sh

: >"$LOG"
rm -f -- "$COUNT"
run_script config/hypr/scripts/quickshell_quick_settings_toggle.sh AWTARCHY_TEST_QS_FAIL_FIRST=1
grep -Fq -- 'manager start' "$LOG" \
    || fail 'Quick Settings cold-start fallback did not invoke quickshell.sh start'
[[ "$(grep -Fc -- 'qs -c awtarchy ipc call quicksettings toggle' "$LOG")" -eq 2 ]] \
    || fail 'Quick Settings cold-start fallback did not retry IPC exactly once'

: >"$LOG"
rm -f -- "$COUNT"
run_script config/hypr/scripts/quickshell_bar_flip.sh AWTARCHY_TEST_QS_FAIL_FIRST=1
grep -Fq -- 'manager flip-focused' "$LOG" \
    || fail 'bar flip cold-start fallback did not preserve the manager command'

: >"$LOG"
rm -f -- "$COUNT"
run_script config/hypr/scripts/quickshell_power_menu.sh AWTARCHY_TEST_QS_FAIL_FIRST=1
grep -Fq -- 'manager start' "$LOG" \
    || fail 'Power Menu cold-start fallback did not invoke quickshell.sh start'
[[ "$(grep -Fc -- 'qs -c awtarchy ipc call powermenu begin' "$LOG")" -eq 2 ]] \
    || fail 'Power Menu cold-start fallback did not retry begin IPC exactly once'

SHELL_QML="$ROOT/config/quickshell/awtarchy/shell.qml"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"

for method in flipBarFocused rotateBarFocused toggleBarAutoHideFocused; do
    grep -Fq -- "function ${method}()" "$SHELL_QML" \
        || fail "shell control path is missing ${method}()"
done

grep -Fq -- 'BarState.setLivePosition(monitor, target);' "$SHELL_QML" \
    || fail 'bar position hotkeys do not update live QML state first'
grep -Fq -- 'BarState.setLiveAutoHide(monitor, target);' "$SHELL_QML" \
    || fail 'bar auto-hide hotkey does not update live QML state first'
grep -Fq -- 'property var liveAutoHide: ({})' "$BAR_STATE" \
    || fail 'BarState is missing the live auto-hide override'
grep -Fq -- 'function reconcileHotkeyOverrides()' "$BAR_STATE" \
    || fail 'BarState does not reconcile hotkey overrides after persistence'

printf '%s\n' 'PASS: Quickshell hotkeys use direct IPC with recovery fallbacks'
