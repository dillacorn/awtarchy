#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SHELL_QML="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
BARSTATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
SAVE="$ROOT/config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
TZ_HELPER="$ROOT/config/hypr/scripts/quickshell_lockscreen_timezones.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    grep -Fq -- "$2" "$1" || fail "$3"
}

contains "$EDITOR" 'property var draftTimezoneClocks: []' \
    'editor has no timezone-clock draft state'
contains "$EDITOR" 'property var draftCustomTexts: []' \
    'editor has no arbitrary-text draft state'
contains "$EDITOR" 'function addTimezoneClock()' \
    'editor cannot add optional timezone clocks'
contains "$EDITOR" 'function addCustomText()' \
    'editor cannot add arbitrary text elements'
contains "$EDITOR" 'timezone:' \
    'timezone clock elements do not retain an IANA timezone field'
contains "$EDITOR" 'variants:' \
    'custom text elements do not retain user text variants'
contains "$EDITOR" 'randomize:' \
    'custom text elements do not expose random selection state'
contains "$EDITOR" 'alignment:' \
    'custom text elements do not expose left/center/right alignment state'
contains "$EDITOR" 'name.startsWith("timezone:")' \
    'editor does not dispatch stable timezone element identities'
contains "$EDITOR" 'name.startsWith("text:")' \
    'editor does not dispatch stable arbitrary-text element identities'
contains "$EDITOR" 'function resetDynamicElementPosition(name)' \
    'timezone/text elements cannot safely reset their position'
contains "$EDITOR" 'function resetDynamicElementToDefault(name)' \
    'timezone/text elements cannot safely restore their own defaults'
contains "$EDITOR" 'function applyDynamicSelectionVisibility(names, visible)' \
    'multi-select visibility does not include timezone/text elements'
contains "$EDITOR" 'function applyDynamicColorToAll(value)' \
    'global element color changes do not include timezone/text elements'

contains "$SCENE" 'required property var timezoneClocks' \
    'shared scene has no timezone-clock input'
contains "$SCENE" 'required property var timezoneValues' \
    'shared scene has no formatted timezone value input'
contains "$SCENE" 'required property var customTexts' \
    'shared scene has no arbitrary-text input'
contains "$SCENE" 'property int textReplayEpoch:' \
    'shared scene cannot hold a stable random-text choice per presentation epoch'
cmp -s "$SCENE" "$PREVIEW" || fail 'secure and preview scene diverged'

contains "$SHELL_QML" 'property var lockTimezoneClocks: []' \
    'secure shell does not own normalized timezone-clock state'
contains "$SHELL_QML" 'property var lockCustomTexts: []' \
    'secure shell does not own normalized custom-text state'
contains "$BARSTATE" 'lockscreen_timezone_clocks' \
    'desktop state loader does not read persisted timezone clocks'
contains "$BARSTATE" 'lockscreen_custom_texts' \
    'desktop state loader does not read persisted custom text'
contains "$SAVE" 'lockscreen_timezone_clocks' \
    'editor save wrapper does not atomically persist timezone clocks'
contains "$SAVE" 'lockscreen_custom_texts' \
    'editor save wrapper does not atomically persist custom text'

test -x "$TZ_HELPER" || fail 'timezone helper is missing or not executable'
contains "$TZ_HELPER" '/usr/share/zoneinfo' \
    'timezone helper does not validate against local zoneinfo data'
# This test intentionally searches for a literal shell assignment.
# shellcheck disable=SC2016
contains "$TZ_HELPER" 'TZ="$zone"' \
    'timezone helper does not use the validated local timezone with date'
if grep -Eq '(^|[[:space:]])eval([[:space:]]|$)' "$TZ_HELPER"; then
    fail 'timezone helper uses eval'
fi

printf 'PASS: lockscreen timezone-clock and arbitrary-text contracts\n'
