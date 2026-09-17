#!/usr/bin/env python3
from pathlib import Path
import re

helper_path = Path("config/hypr/scripts/quickshell_lockscreen_contrast.sh")
desktop_cache_path = Path("config/quickshell/awtarchy/LockscreenContrast.qml")
secure_cache_path = Path("config/quickshell/awtarchy-lock/LockContrastCache.qml")
editor_path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")

# ---------------------------------------------------------------------------
# Persisted v3 contrast cache: Shared colors stay at top level for compatibility,
# while each persisted monitor override receives its own independently sampled
# color map. --stdout remains a single-profile draft calculation for the editor.
# ---------------------------------------------------------------------------
helper = helper_path.read_text(encoding="utf-8")
if 'monitor_colors="$' not in helper and '{version:3' not in helper:
    marker = '\nbackground="black"\n'
    pos = helper.find(marker)
    if pos < 0:
        raise SystemExit("contrast helper tail anchor missing")
    helper = helper[:pos] + r'''

profile_colors() {
    local background="$1" background_color="$2" wallpaper="$3" layout="$4"
    local colors='{}' color element
    # Bash dynamic scoping lets prepare_wallpaper_sample update these locals,
    # keeping each profile's temporary representative frame isolated.
    local TMP_DIR=""
    local WALLPAPER_SAMPLE="$wallpaper"

    case "$background" in
        black|wallpaper|color) ;;
        *) background="black" ;;
    esac
    valid_hex "$background_color" || background_color="#000000"
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$layout"; then
        layout="$DEFAULT_LAYOUT"
    fi

    if [[ "$background" == "wallpaper" ]]; then
        prepare_wallpaper_sample "$wallpaper"
    fi

    for element in $ELEMENTS; do
        case "$background" in
            black) color="#ffffff" ;;
            color) color="$(contrast_for_hex "$background_color")" ;;
            wallpaper) color="$(sample_wallpaper_contrast "$WALLPAPER_SAMPLE" "$layout" "$element")" ;;
        esac
        colors="$(jq -c --arg element "$element" --arg color "$color" \
            '. + {($element): $color}' <<<"$colors")"
    done

    [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"
    printf '%s\n' "$colors"
}

profile_fields() {
    local profile="$1"
    jq -c --argjson defaults "$DEFAULT_LAYOUT" '
        {
            background: (.lockscreen_background // "black"),
            background_color: (.lockscreen_background_color // "#000000"),
            wallpaper: (.lockscreen_wallpaper_path // ""),
            layout: (.lockscreen_layout // $defaults)
        }
    ' <<<"$profile" 2>/dev/null || jq -cn --argjson defaults "$DEFAULT_LAYOUT" \
        '{background:"black",background_color:"#000000",wallpaper:"",layout:$defaults}'
}

state='{}'
if [[ -s "$STATE_FILE" ]] && jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    state="$(cat -- "$STATE_FILE")"
fi

shared_profile="$(jq -c '.' <<<"$state")"
shared_fields="$(profile_fields "$shared_profile")"
background="$(jq -r '.background' <<<"$shared_fields")"
background_color="$(jq -r '.background_color' <<<"$shared_fields")"
wallpaper="$(jq -r '.wallpaper' <<<"$shared_fields")"
layout="$(jq -c '.layout' <<<"$shared_fields")"

[[ -z "$OVERRIDE_BACKGROUND" ]] || background="$OVERRIDE_BACKGROUND"
[[ -z "$OVERRIDE_BACKGROUND_COLOR" ]] || background_color="$OVERRIDE_BACKGROUND_COLOR"
[[ -z "$OVERRIDE_WALLPAPER" ]] || wallpaper="$OVERRIDE_WALLPAPER"
[[ -z "$OVERRIDE_LAYOUT" ]] || layout="$OVERRIDE_LAYOUT"

colors="$(profile_colors "$background" "$background_color" "$wallpaper" "$layout")"

if ((OUTPUT_STDOUT == 1)); then
    payload="$(jq -cn \
        --arg provider 'awtarchy-local-contrast' \
        --arg background "$background" \
        --arg background_color "$background_color" \
        --arg wallpaper "$wallpaper" \
        --argjson colors "$colors" \
        '{version:2, provider:$provider, background:$background,
          background_color:$background_color, wallpaper:$wallpaper, colors:$colors}')"
    printf '%s\n' "$payload"
    exit 0
fi

monitor_colors='{}'
monitor_overrides="$(jq -c '
    if (.lockscreen_monitor_overrides | type) == "object"
    then .lockscreen_monitor_overrides else {} end
' <<<"$state")"
while IFS= read -r monitor; do
    [[ -n "$monitor" ]] || continue
    profile="$(jq -c --arg monitor "$monitor" '.[$monitor]' <<<"$monitor_overrides")"
    fields="$(profile_fields "$profile")"
    monitor_background="$(jq -r '.background' <<<"$fields")"
    monitor_background_color="$(jq -r '.background_color' <<<"$fields")"
    monitor_wallpaper="$(jq -r '.wallpaper' <<<"$fields")"
    monitor_layout="$(jq -c '.layout' <<<"$fields")"
    monitor_profile_colors="$(profile_colors "$monitor_background" "$monitor_background_color" "$monitor_wallpaper" "$monitor_layout")"
    monitor_colors="$(jq -c --arg monitor "$monitor" --argjson colors "$monitor_profile_colors" \
        '. + {($monitor): $colors}' <<<"$monitor_colors")"
done < <(jq -r 'keys[]' <<<"$monitor_overrides")

payload="$(jq -cn \
    --arg provider 'awtarchy-local-contrast' \
    --arg background "$background" \
    --arg background_color "$background_color" \
    --arg wallpaper "$wallpaper" \
    --argjson colors "$colors" \
    --argjson monitor_colors "$monitor_colors" \
    '{version:3, provider:$provider, background:$background,
      background_color:$background_color, wallpaper:$wallpaper,
      colors:$colors, monitor_colors:$monitor_colors}')"

mkdir -p "$CACHE_DIR"
TMP_FILE="$(mktemp "${CACHE_FILE}.tmp.XXXXXX")"
printf '%s\n' "$payload" >"$TMP_FILE"
mv -f -- "$TMP_FILE" "$CACHE_FILE"
TMP_FILE=""
'''
    helper_path.write_text(helper, encoding="utf-8")

# ---------------------------------------------------------------------------
# Unlocked persisted-cache service: retain Shared accents API and add per-output
# maps so editor sessions can seed their derived values from the last save.
# ---------------------------------------------------------------------------
desktop_cache = desktop_cache_path.read_text(encoding="utf-8")
if 'property var monitorAccents:' not in desktop_cache:
    desktop_cache = desktop_cache.replace(
        '    property var accents: ({\n',
        '    property var monitorAccents: ({})\n\n    property var accents: ({\n',
        1,
    )
    old = '''    function colorFor(name) {\n        const value = String(accents && accents[name] !== undefined ? accents[name] : "#ffffff");\n        return /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";\n    }\n\n'''
    new = '''    function normalizedColors(value) {\n        const next = ({});\n        const source = value && typeof value === "object" && !Array.isArray(value) ? value : ({});\n        for (const name of elementNames) {\n            const color = String(source[name] || "").toLowerCase();\n            next[name] = /^#[0-9a-f]{6}$/.test(color) ? color : "#ffffff";\n        }\n        return next;\n    }\n\n    function colorFor(name) {\n        const value = String(accents && accents[name] !== undefined ? accents[name] : "#ffffff");\n        return /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";\n    }\n\n    function colorsForMonitor(name) {\n        const key = String(name || "");\n        const value = monitorAccents && monitorAccents[key];\n        return value && typeof value === "object" && !Array.isArray(value)\n            ? normalizedColors(value) : normalizedColors(accents);\n    }\n\n'''
    if old not in desktop_cache:
        raise SystemExit("desktop contrast colorFor anchor missing")
    desktop_cache = desktop_cache.replace(old, new, 1)
    old_refresh = re.compile(r'    function refreshAccent\(\) \{.*?\n    \}\n\n    function requestRefresh', re.S)
    new_refresh = '''    function refreshAccent() {\n        const text = String(contrastFile.text() || "").trim();\n        if (text.length === 0)\n            return;\n        try {\n            const parsed = JSON.parse(text);\n            if (!parsed || parsed.provider !== "awtarchy-local-contrast"\n                    || !parsed.colors || typeof parsed.colors !== "object")\n                return;\n            accents = normalizedColors(parsed.colors);\n            const nextMonitors = ({});\n            if (parsed.monitor_colors && typeof parsed.monitor_colors === "object"\n                    && !Array.isArray(parsed.monitor_colors)) {\n                for (const name of Object.keys(parsed.monitor_colors))\n                    nextMonitors[name] = normalizedColors(parsed.monitor_colors[name]);\n            }\n            monitorAccents = nextMonitors;\n        } catch (error) {\n            // Keep existing safe contrast values if the local cache is malformed.\n        }\n    }\n\n    function requestRefresh'''
    desktop_cache, count = old_refresh.subn(new_refresh, desktop_cache, count=1)
    if count != 1:
        raise SystemExit("desktop contrast refresh anchor missing")
    desktop_cache_path.write_text(desktop_cache, encoding="utf-8")

# ---------------------------------------------------------------------------
# Secure cache reader: v2 continues to use Shared colors. v3 selects the current
# output map when present and otherwise falls back to the Shared map.
# ---------------------------------------------------------------------------
secure_cache = secure_cache_path.read_text(encoding="utf-8")
if 'property string monitorName: ""' not in secure_cache:
    secure_cache = secure_cache.replace(
        '    readonly property var elementNames:',
        '    property string monitorName: ""\n    readonly property var elementNames:',
        1,
    )
    old_refresh = re.compile(r'    function refresh\(\) \{.*?\n    \}\n\n    FileView', re.S)
    new_refresh = '''    function refresh() {\n        const text = String(cacheFile.text() || "").trim();\n        if (text.length === 0)\n            return;\n        try {\n            const parsed = JSON.parse(text);\n            if (!parsed || parsed.provider !== "awtarchy-local-contrast"\n                    || !parsed.colors || typeof parsed.colors !== "object")\n                return;\n            let selected = parsed.colors;\n            if (parsed.monitor_colors && typeof parsed.monitor_colors === "object"\n                    && !Array.isArray(parsed.monitor_colors)\n                    && parsed.monitor_colors[root.monitorName]\n                    && typeof parsed.monitor_colors[root.monitorName] === "object"\n                    && !Array.isArray(parsed.monitor_colors[root.monitorName]))\n                selected = parsed.monitor_colors[root.monitorName];\n            const next = ({});\n            for (const name of elementNames) {\n                const value = String(selected[name] || "");\n                next[name] = /^#[0-9a-fA-F]{6}$/.test(value)\n                    ? value.toLowerCase() : "#ffffff";\n            }\n            colors = next;\n        } catch (error) {\n            // Keep safe white fallbacks for malformed or partial local cache data.\n        }\n    }\n\n    FileView'''
    secure_cache, count = old_refresh.subn(new_refresh, secure_cache, count=1)
    if count != 1:
        raise SystemExit("secure contrast refresh anchor missing")
    secure_cache_path.write_text(secure_cache, encoding="utf-8")

# ---------------------------------------------------------------------------
# Editor: current draftAutoAccents stays the active-profile facade. Shared and
# monitor maps preserve unsaved derived colors across monitor switches/copies.
# ---------------------------------------------------------------------------
editor = editor_path.read_text(encoding="utf-8")
if 'property var draftSharedAutoAccents:' not in editor:
    anchor = '    property var draftAutoAccents: defaultAutoAccents()\n'
    if editor.count(anchor) != 1:
        raise SystemExit("editor accent property anchor missing")
    editor = editor.replace(
        anchor,
        anchor
        + '    property var draftSharedAutoAccents: defaultAutoAccents()\n'
        + '    property var draftMonitorAutoAccents: ({})\n',
        1,
    )

if '    function cloneAutoAccents(value) {' not in editor:
    anchor = '    function validHex(value) {\n'
    if editor.count(anchor) != 1:
        raise SystemExit("editor clone accents anchor missing")
    block = '''    function cloneAutoAccents(value) {\n        const source = value && typeof value === "object" && !Array.isArray(value)\n            ? value : defaultAutoAccents();\n        const next = defaultAutoAccents();\n        for (const name of elementNames) {\n            const color = String(source[name] || "").toLowerCase();\n            next[name] = validHex(color) ? color : "#ffffff";\n        }\n        const visualizer = String(source.visualizer || source.logo || "#ffffff").toLowerCase();\n        next.visualizer = validHex(visualizer) ? visualizer : "#ffffff";\n        return next;\n    }\n\n'''
    editor = editor.replace(anchor, block + anchor, 1)

if '    function stashAutoAccentsForActiveProfile() {' not in editor:
    anchor = '    function activeProfileKey() {\n'
    if editor.count(anchor) != 1:
        raise SystemExit("editor active profile accent anchor missing")
    block = '''    function stashAutoAccentsForActiveProfile() {\n        const accents = cloneAutoAccents(draftAutoAccents);\n        if (hasIndividualConfiguration(activeMonitorName)) {\n            const next = Object.assign({}, draftMonitorAutoAccents);\n            next[activeMonitorName] = accents;\n            draftMonitorAutoAccents = next;\n        } else {\n            draftSharedAutoAccents = accents;\n        }\n    }\n\n    function loadAutoAccentsForActiveProfile() {\n        if (hasIndividualConfiguration(activeMonitorName)) {\n            const stored = draftMonitorAutoAccents[activeMonitorName];\n            draftAutoAccents = cloneAutoAccents(stored || LockscreenContrast.colorsForMonitor(activeMonitorName));\n        } else {\n            draftAutoAccents = cloneAutoAccents(draftSharedAutoAccents);\n        }\n    }\n\n    function autoAccentsForMonitor(name) {\n        const key = String(name || "");\n        if (key === activeMonitorName)\n            return cloneAutoAccents(draftAutoAccents);\n        if (hasIndividualConfiguration(key)) {\n            const stored = draftMonitorAutoAccents[key];\n            return cloneAutoAccents(stored || LockscreenContrast.colorsForMonitor(key));\n        }\n        if (!hasIndividualConfiguration(activeMonitorName))\n            return cloneAutoAccents(draftAutoAccents);\n        return cloneAutoAccents(draftSharedAutoAccents);\n    }\n\n'''
    editor = editor.replace(anchor, block + anchor, 1)

# Mode/switch/copy paths preserve derived accents with the same profile identity.
editor = editor.replace(
    '        stashHistoryForActiveProfile();\n        flushActiveProfile();\n        const next = Object.assign({}, draftMonitorOverrides);\n        next[activeMonitorName] = cloneSnapshot(profileFromDraftScalars());',
    '        stashHistoryForActiveProfile();\n        stashAutoAccentsForActiveProfile();\n        flushActiveProfile();\n        const next = Object.assign({}, draftMonitorOverrides);\n        next[activeMonitorName] = cloneSnapshot(profileFromDraftScalars());\n        const nextAccents = Object.assign({}, draftMonitorAutoAccents);\n        nextAccents[activeMonitorName] = cloneAutoAccents(draftAutoAccents);\n        draftMonitorAutoAccents = nextAccents;',
    1,
)
editor = editor.replace(
    '        stashHistoryForActiveProfile();\n        flushActiveProfile();\n        const next = Object.assign({}, draftMonitorOverrides);\n        delete next[activeMonitorName];\n        draftMonitorOverrides = next;\n        loadProfileIntoDraft(draftSharedProfile);\n        restoreHistoryForActiveProfile();',
    '        stashHistoryForActiveProfile();\n        stashAutoAccentsForActiveProfile();\n        flushActiveProfile();\n        const next = Object.assign({}, draftMonitorOverrides);\n        delete next[activeMonitorName];\n        draftMonitorOverrides = next;\n        const nextAccents = Object.assign({}, draftMonitorAutoAccents);\n        delete nextAccents[activeMonitorName];\n        draftMonitorAutoAccents = nextAccents;\n        loadProfileIntoDraft(draftSharedProfile);\n        loadAutoAccentsForActiveProfile();\n        restoreHistoryForActiveProfile();',
    1,
)

# copyConfigurationTo: copy current derived value alongside the profile snapshot.
old = '        next[targetName] = cloneSnapshot(source);\n        draftMonitorOverrides = next;\n        const undo = Object.assign({}, profileUndoStacks);'
new = '        next[targetName] = cloneSnapshot(source);\n        draftMonitorOverrides = next;\n        const accentCopies = Object.assign({}, draftMonitorAutoAccents);\n        accentCopies[targetName] = cloneAutoAccents(draftAutoAccents);\n        draftMonitorAutoAccents = accentCopies;\n        const undo = Object.assign({}, profileUndoStacks);'
if old in editor:
    editor = editor.replace(old, new, 1)
elif new not in editor:
    raise SystemExit("editor copy target accent anchor missing")

# Copy-all gets one independent clone per target.
old = '            next[name] = cloneSnapshot(source);\n            delete undo["monitor:" + name];'
new = '            next[name] = cloneSnapshot(source);\n            const accentCopies = Object.assign({}, draftMonitorAutoAccents);\n            accentCopies[name] = cloneAutoAccents(draftAutoAccents);\n            draftMonitorAutoAccents = accentCopies;\n            delete undo["monitor:" + name];'
if old in editor:
    editor = editor.replace(old, new, 1)
elif new not in editor:
    raise SystemExit("editor copy-all accent anchor missing")

# Both switch paths stash outgoing accents then load incoming ones.
switch_old = '        stashHistoryForActiveProfile();\n        flushActiveProfile();\n        activeMonitorName = String(name);'
switch_new = '        stashHistoryForActiveProfile();\n        stashAutoAccentsForActiveProfile();\n        flushActiveProfile();\n        activeMonitorName = String(name);'
if switch_old in editor:
    editor = editor.replace(switch_old, switch_new, 1)
elif switch_new not in editor:
    raise SystemExit("editor switch accent stash anchor missing")

reconcile_old = '        stashHistoryForActiveProfile();\n        flushActiveProfile();\n        const target = focusedScreen();'
reconcile_new = '        stashHistoryForActiveProfile();\n        stashAutoAccentsForActiveProfile();\n        flushActiveProfile();\n        const target = focusedScreen();'
if reconcile_old in editor:
    editor = editor.replace(reconcile_old, reconcile_new, 1)
elif reconcile_new not in editor:
    raise SystemExit("editor reconcile accent stash anchor missing")

# Insert loading after each target profile load in switch/reconcile. Do not touch
# loadProfileIntoDraft itself because its normal contrast debounce recomputes active.
editor = editor.replace(
    '        loadProfileIntoDraft(profile);\n        restoreHistoryForActiveProfile();\n        statusMessage = "Editing " + activeMonitorName;',
    '        loadProfileIntoDraft(profile);\n        loadAutoAccentsForActiveProfile();\n        restoreHistoryForActiveProfile();\n        statusMessage = "Editing " + activeMonitorName;',
    2,
)

# Seed draft accent maps from the persisted contrast cache once per editor session.
load_anchor = '        draftMonitorOverrides = cloneSnapshot(overrides) || ({});\n'
load_insert = '''        draftMonitorOverrides = cloneSnapshot(overrides) || ({});\n        draftSharedAutoAccents = cloneAutoAccents(LockscreenContrast.accents);\n        const persistedMonitorAccents = ({});\n        for (const name of Object.keys(draftMonitorOverrides))\n            persistedMonitorAccents[name] = cloneAutoAccents(LockscreenContrast.colorsForMonitor(name));\n        draftMonitorAutoAccents = persistedMonitorAccents;\n'''
if load_anchor in editor:
    editor = editor.replace(load_anchor, load_insert, 1)
elif 'draftSharedAutoAccents = cloneAutoAccents(LockscreenContrast.accents)' not in editor:
    raise SystemExit("editor persisted accent seed anchor missing")

load_active_anchor = '        loadProfileIntoDraft(profile);\n        profileUndoStacks = ({});'
load_active_new = '        loadProfileIntoDraft(profile);\n        loadAutoAccentsForActiveProfile();\n        profileUndoStacks = ({});'
if load_active_anchor in editor:
    editor = editor.replace(load_active_anchor, load_active_new, 1)
elif load_active_new not in editor:
    raise SystemExit("editor initial active accent load anchor missing")

# Active helper result is immediately stashed into the matching draft profile.
apply_old = '            draftAutoAccents = next;\n        } catch (error) {}'
apply_new = '            draftAutoAccents = next;\n            stashAutoAccentsForActiveProfile();\n        } catch (error) {}'
if apply_old in editor:
    editor = editor.replace(apply_old, apply_new, 1)
elif apply_new not in editor:
    raise SystemExit("editor preview contrast stash anchor missing")

# Passive monitor scenes must use their own effective derived accent map.
editor = editor.replace(
    'autoAccents: root.draftAutoAccents; layout: secondaryPreviewWindow.monitorProfile.lockscreen_layout;',
    'autoAccents: root.autoAccentsForMonitor(modelData.name); layout: secondaryPreviewWindow.monitorProfile.lockscreen_layout;',
    1,
)

if 'autoAccents: root.autoAccentsForMonitor(modelData.name)' not in editor:
    raise SystemExit("editor passive accent binding replacement failed")

editor_path.write_text(editor, encoding="utf-8")
