#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/quickshell_floating_windows.sh"
HYPR_LUA="$ROOT/config/hypr/hyprland.lua"
BAR="$ROOT/config/quickshell/awtarchy/Bar.qml"
CARD="$ROOT/config/quickshell/awtarchy/FloatingWindowsCard.qml"
STATE_QML="$ROOT/config/quickshell/awtarchy/FloatingWindowsState.qml"
HISTORY="$ROOT/local/share/awtarchy/quickshell-managed-history.sha256"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

[[ -f "$STATE_QML" ]] || fail 'shared FloatingWindowsState singleton is missing'

contains "$HELPER" 'toggle)' \
    'Floating Windows helper has no global toggle action'
contains "$HELPER" 'AWTARCHY_FLOATING_STATE_FILE' \
    'Floating Windows helper does not publish shared runtime state'
contains "$HELPER" '--notify' \
    'Floating Windows helper has no notification-capable toggle path'
contains "$HELPER" 'title="Floating windows: ON"' \
    'Floating Windows enable feedback does not clearly identify global mode'
contains "$HELPER" 'body="Global floating mode is active. New windows will float. Use Quick Settings to restore tiling."' \
    'Floating Windows enable feedback does not explain how to restore tiling'
contains "$HELPER" 'timeout=5000' \
    'Floating Windows enable feedback is too brief to be useful'
if grep -Fq -- '-a Awtarchy' "$HELPER"; then
    fail 'Floating Windows feedback still uses the persistent Awtarchy notification identity'
fi

if grep -Fq 'floating_windows_toggle' "$HYPR_LUA"; then
    fail 'global/noalt floating-spawn keyboard toggle returned'
fi
bind_count="$(grep -Fc '{ "SUPER + ALT + F", floating_windows_toggle },' "$HYPR_LUA" || true)"
[[ "$bind_count" == 0 ]] \
    || fail 'SUPER+ALT+F must not toggle persistent floating-spawn mode outside VM'
contains "$HYPR_LUA" '{ "SUPER + F", hl.dsp.window.float({ action = "toggle" }) },' \
    'existing SUPER+F focused-window float/tile bind changed or disappeared'
contains "$HYPR_LUA" '{ "SUPER + ALT + F", hl.dsp.window.float({ action = "toggle" }), {} },' \
    'VM SUPER+ALT+F active-window floating bind changed or disappeared'

contains "$STATE_QML" 'pragma Singleton' \
    'FloatingWindowsState is not a singleton'
contains "$STATE_QML" 'readonly property bool enabled: state === "enabled"' \
    'FloatingWindowsState does not expose enabled state'
contains "$STATE_QML" 'function setEnabled(enabled)' \
    'FloatingWindowsState cannot set global floating-spawn mode'
contains "$STATE_QML" 'function toggle()' \
    'FloatingWindowsState cannot toggle global floating-spawn mode'
contains "$STATE_QML" 'watchChanges: true' \
    'FloatingWindowsState does not react to helper state publication'
if grep -Fq 'repeat: true' "$STATE_QML"; then
    fail 'FloatingWindowsState must not add repeating status polling'
fi

contains "$CARD" 'FloatingWindowsState.state' \
    'Quick Settings Floating Windows card does not consume shared state'
contains "$CARD" 'FloatingWindowsState.toggle()' \
    'Quick Settings Floating Windows card does not use the shared toggle path'
contains "$CARD" 'return "FLOATING ON";' \
    'Quick Settings does not make global Floating Windows state obvious'
contains "$CARD" 'label: root.floatingState === "enabled" ? "Restore tiling" : "Enable floating"' \
    'Quick Settings does not expose an explicit restore-tiling action'
contains "$CARD" 'GLOBAL MODE ACTIVE: new windows open floating by default.' \
    'Quick Settings enabled-state explanation is not prominent enough'
if grep -Fq 'interval: 3000' "$CARD"; then
    fail 'Quick Settings Floating Windows card still polls status every 3 seconds'
fi

contains "$BAR" 'label: "Floating"' \
    'horizontal bar does not expose the persistent Floating indicator'
contains "$BAR" 'label: "Float"' \
    'vertical bar does not expose a compact floating-mode indicator'
visible_count="$(grep -Fc 'visible: FloatingWindowsState.enabled' "$BAR" || true)"
[[ "$visible_count" == 2 ]] \
    || fail 'Floating bar indicators must only appear while global floating-spawn mode is enabled'
disable_count="$(grep -Fc 'onClicked: FloatingWindowsState.setEnabled(false)' "$BAR" || true)"
[[ "$disable_count" == 2 ]] \
    || fail 'clicking either Floating indicator must restore normal tiling'

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
TEST_LUA="$TMP/hyprland.lua"
FAKE_HYPRCTL="$TMP/hyprctl"
FAKE_NOTIFY="$TMP/notify-send"
HYPRCTL_LOG="$TMP/hyprctl.log"
NOTIFY_LOG="$TMP/notify.log"
STATE_FILE="$TMP/floating-state"
CONFIGERROR_COUNT="$TMP/configerrors.count"
cp -- "$HYPR_LUA" "$TEST_LUA"
: >"$HYPRCTL_LOG"
: >"$NOTIFY_LOG"
printf '0\n' >"$CONFIGERROR_COUNT"

cat >"$FAKE_HYPRCTL" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${FAKE_HYPRCTL_LOG:?}"
case "${1:-}" in
    configerrors)
        count="$(cat "${FAKE_CONFIGERROR_COUNT:?}")"
        count=$((count + 1))
        printf '%s\n' "$count" >"${FAKE_CONFIGERROR_COUNT}"
        ;;
    reload)
        ;;
esac
FAKE
chmod +x "$FAKE_HYPRCTL"

cat >"$FAKE_NOTIFY" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${FAKE_NOTIFY_LOG:?}"
FAKE
chmod +x "$FAKE_NOTIFY"

run_helper() {
    HYPRLAND_LUA="$TEST_LUA" \
    HYPRCTL="$FAKE_HYPRCTL" \
    NOTIFY_SEND="$FAKE_NOTIFY" \
    AWTARCHY_FLOATING_STATE_FILE="$STATE_FILE" \
    FAKE_HYPRCTL_LOG="$HYPRCTL_LOG" \
    FAKE_CONFIGERROR_COUNT="$CONFIGERROR_COUNT" \
    FAKE_NOTIFY_LOG="$NOTIFY_LOG" \
    "$HELPER" "$@"
}

[[ "$(run_helper status)" == "disabled" ]] \
    || fail 'status did not report stock disabled state'
[[ "$(cat "$STATE_FILE")" == "disabled" ]] \
    || fail 'status did not publish disabled runtime state'

printf '0\n' >"$CONFIGERROR_COUNT"
[[ "$(run_helper toggle --notify)" == "enabled" ]] \
    || fail 'toggle --notify did not enable global floating-spawn mode'
[[ "$(cat "$STATE_FILE")" == "enabled" ]] \
    || fail 'toggle did not publish enabled runtime state'
contains "$TEST_LUA" 'local awtarchy_floating_windows = true -- AWTARCHY_FLOATING_WINDOWS' \
    'toggle did not persist the enabled marker'
contains "$NOTIFY_LOG" '-a Hyprland -t 5000 Floating windows: ON Global floating mode is active. New windows will float. Use Quick Settings to restore tiling.' \
    'enable feedback does not provide an obvious global-mode warning'

printf '0\n' >"$CONFIGERROR_COUNT"
[[ "$(run_helper toggle --notify)" == "disabled" ]] \
    || fail 'second toggle --notify did not restore normal tiling'
[[ "$(cat "$STATE_FILE")" == "disabled" ]] \
    || fail 'second toggle did not publish disabled runtime state'
contains "$TEST_LUA" 'local awtarchy_floating_windows = false -- AWTARCHY_FLOATING_WINDOWS' \
    'second toggle did not persist the disabled marker'
contains "$NOTIFY_LOG" '-a Hyprland -t 2500 Floating windows: OFF Normal tiling is restored for new windows.' \
    'keyboard disable feedback does not confirm restored tiling'

missing_history=0
for rel in \
    .config/quickshell/awtarchy/Bar.qml \
    .config/quickshell/awtarchy/FloatingWindowsCard.qml \
    .config/quickshell/awtarchy/FloatingWindowsState.qml
do
    source_file="$ROOT/config/${rel#.config/}"
    digest="$(sha256sum "$source_file" | awk '{print $1}')"
    if ! grep -Fq -- "$digest"$'\t'"$rel" "$HISTORY"; then
        printf 'MISSING_MANAGED_HASH %s\t%s\n' "$digest" "$rel" >&2
        missing_history=1
    fi
done
(( missing_history == 0 )) \
    || fail 'managed history is missing current global Floating Windows QML hashes'

printf '%s\n' 'PASS: global Floating Windows mode has shared state, obvious active-state feedback, Quick Settings ownership, and no ambiguous normal/noalt hotkey.'
