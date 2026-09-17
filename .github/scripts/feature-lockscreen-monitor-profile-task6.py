#!/usr/bin/env python3
from pathlib import Path

weather_helper = Path("config/hypr/scripts/quickshell_lockscreen_weather.sh")
weather_qml = Path("config/quickshell/awtarchy/LockscreenWeather.qml")
cache_qml = Path("config/quickshell/awtarchy-lock/LockWeatherCache.qml")
editor_qml = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
surface_qml = Path("config/quickshell/awtarchy-lock/LockSurface.qml")
shell_qml = Path("config/quickshell/awtarchy-lock/shell.qml")

weather_helper.write_text(r'''#!/usr/bin/env bash
# Refresh the lockscreen's display-only weather cache while the desktop is unlocked.

set -euo pipefail

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE_DIR="${CACHE_HOME}/awtarchy"
CACHE_FILE="${CACHE_DIR}/lockscreen-weather.json"
TMP_FILE=""

cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
trap cleanup EXIT

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'quickshell_lockscreen_weather.sh: missing: %s\n' "$1" >&2
        exit 127
    }
}

validate_location() {
    local value="$1"
    if ! jq -e -n --arg value "$value" '
        ($value | explode) as $points
        | ($points | length) <= 96
        and ($points | all(. >= 32 and (. < 127 or . > 159)))
    ' >/dev/null 2>&1; then
        printf 'weather location must be at most 96 Unicode code points with no control characters\n' >&2
        exit 2
    fi
}

resolve_units() {
    local requested="$1" locale
    case "$requested" in
        fahrenheit|celsius)
            printf '%s' "$requested"
            ;;
        auto)
            locale="${LC_ALL:-${LC_MEASUREMENT:-${LANG:-}}}"
            case "$locale" in
                *_US*) printf '%s' 'fahrenheit' ;;
                *) printf '%s' 'celsius' ;;
            esac
            ;;
        *)
            printf 'invalid weather units: %s\n' "$requested" >&2
            exit 2
            ;;
    esac
}

weather_description() {
    case "$1" in
        0) printf '%s' 'Clear' ;;
        1) printf '%s' 'Mostly clear' ;;
        2) printf '%s' 'Partly cloudy' ;;
        3) printf '%s' 'Cloudy' ;;
        45|48) printf '%s' 'Fog' ;;
        51|53|55|56|57) printf '%s' 'Drizzle' ;;
        61|63|65|66|67) printf '%s' 'Rain' ;;
        71|73|75|77) printf '%s' 'Snow' ;;
        80|81|82) printf '%s' 'Rain showers' ;;
        85|86) printf '%s' 'Snow showers' ;;
        95|96|99) printf '%s' 'Thunderstorms' ;;
        *) printf '%s' 'Weather' ;;
    esac
}

resolve_location() {
    local requested="$1"
    local location_json latitude longitude resolved_name admin1

    validate_location "$requested"
    if [[ -n "$requested" ]]; then
        location_json="$(curl --fail --silent --show-error \
            --connect-timeout 4 --max-time 8 \
            --get 'https://geocoding-api.open-meteo.com/v1/search' \
            --data-urlencode "name=$requested" \
            --data 'count=1' \
            --data 'language=en' \
            --data 'format=json')"

        latitude="$(jq -er '.results[0].latitude | select(type == "number")' <<<"$location_json")"
        longitude="$(jq -er '.results[0].longitude | select(type == "number")' <<<"$location_json")"
        resolved_name="$(jq -er '.results[0].name | select(type == "string" and length > 0)' <<<"$location_json")"
        admin1="$(jq -r '.results[0].admin1 // "" | select(type == "string")' <<<"$location_json")"
    else
        location_json="$(curl --fail --silent --show-error \
            --connect-timeout 4 --max-time 8 'https://ipwho.is/')"

        jq -e '.success == true' <<<"$location_json" >/dev/null
        latitude="$(jq -er '.latitude | select(type == "number")' <<<"$location_json")"
        longitude="$(jq -er '.longitude | select(type == "number")' <<<"$location_json")"
        resolved_name="$(jq -er '.city | select(type == "string" and length > 0)' <<<"$location_json")"
        admin1="$(jq -r '.region // "" | select(type == "string")' <<<"$location_json")"
    fi

    if [[ -n "$admin1" ]]; then
        printf '%s\t%s\t%s, %s\n' "$latitude" "$longitude" "$resolved_name" "$admin1"
    else
        printf '%s\t%s\t%s\n' "$latitude" "$longitude" "$resolved_name"
    fi
}

validate_requested_modes() {
    local value="$1"
    jq -ce -n --argjson candidate "$value" '
        if (($candidate | type) == "array"
            and ($candidate | length) >= 1
            and ($candidate | length) <= 16
            and all($candidate[];
                type == "string"
                and (. == "auto" or . == "fahrenheit" or . == "celsius")))
        then reduce $candidate[] as $mode ([];
            if index($mode) == null then . + [$mode] else . end)
        else error("invalid weather unit set") end
    '
}

forecast_for_units() {
    local latitude="$1" longitude="$2" resolved_units="$3"
    curl --fail --silent --show-error \
        --connect-timeout 4 --max-time 8 \
        --get 'https://api.open-meteo.com/v1/forecast' \
        --data-urlencode "latitude=$latitude" \
        --data-urlencode "longitude=$longitude" \
        --data 'current=temperature_2m,weather_code' \
        --data-urlencode "temperature_unit=$resolved_units" \
        --data 'timezone=auto'
}

entry_from_forecast() {
    local forecast_json="$1" display_location="$2" requested_units="$3" resolved_units="$4"
    local fetched_at="$5" expires_at="$6"
    local temperature unit code description summary

    temperature="$(jq -er '.current.temperature_2m | select(type == "number")' <<<"$forecast_json")"
    unit="$(jq -er '.current_units.temperature_2m | select(type == "string" and length > 0)' <<<"$forecast_json")"
    code="$(jq -er '.current.weather_code | select(type == "number") | floor' <<<"$forecast_json")"
    description="$(weather_description "$code")"
    printf -v temperature '%.0f' "$temperature"
    summary="${temperature}${unit} · ${description}"

    jq -cn \
        --arg summary "$summary" \
        --arg location "$display_location" \
        --arg requested_units "$requested_units" \
        --arg units "$resolved_units" \
        --argjson fetched_at "$fetched_at" \
        --argjson expires_at "$expires_at" '
        {
            summary: $summary,
            location: $location,
            requested_units: $requested_units,
            units: $units,
            fetched_at: $fetched_at,
            expires_at: $expires_at,
            provider: "open-meteo"
        }
    '
}

refresh_set() {
    local location="$1" units_json="$2"
    local modes resolved latitude longitude display_location fetched_at expires_at
    local entries='{}' first_entry='' requested resolved_units forecast_json entry
    declare -A forecast_by_resolved=()

    need curl
    need jq
    modes="$(validate_requested_modes "$units_json")" || {
        printf 'invalid weather unit set\n' >&2
        exit 2
    }

    resolved="$(resolve_location "$location")"
    IFS=$'\t' read -r latitude longitude display_location <<<"$resolved"
    [[ -n "$latitude" && -n "$longitude" && -n "$display_location" ]] || {
        printf 'weather location could not be resolved\n' >&2
        exit 1
    }

    fetched_at="$(date +%s)"
    expires_at=$((fetched_at + 1800))

    while IFS= read -r requested; do
        [[ -n "$requested" ]] || continue
        resolved_units="$(resolve_units "$requested")"
        if [[ -z "${forecast_by_resolved[$resolved_units]+x}" ]]; then
            forecast_by_resolved[$resolved_units]="$(forecast_for_units "$latitude" "$longitude" "$resolved_units")"
        fi
        forecast_json="${forecast_by_resolved[$resolved_units]}"
        entry="$(entry_from_forecast "$forecast_json" "$display_location" "$requested" "$resolved_units" "$fetched_at" "$expires_at")"
        entries="$(jq -c --arg requested "$requested" --argjson entry "$entry" \
            '. + {($requested): $entry}' <<<"$entries")"
        [[ -n "$first_entry" ]] || first_entry="$entry"
    done < <(jq -r '.[]' <<<"$modes")

    [[ -n "$first_entry" ]] || {
        printf 'weather unit set resolved to no entries\n' >&2
        exit 2
    }

    mkdir -p "$CACHE_DIR"
    TMP_FILE="$(mktemp "${CACHE_FILE}.tmp.XXXXXX")"
    jq -cn \
        --argjson legacy "$first_entry" \
        --argjson entries "$entries" '
        $legacy + {version: 2, entries: $entries}
    ' >"$TMP_FILE"

    jq -e '
        .version == 2
        and .provider == "open-meteo"
        and (.entries | type) == "object"
        and (.entries | length) >= 1
        and all(.entries[];
            .provider == "open-meteo"
            and (.summary | type) == "string"
            and (.summary | length) >= 1
            and (.summary | length) <= 96
            and (.location | type) == "string"
            and (.requested_units == "auto" or .requested_units == "fahrenheit" or .requested_units == "celsius")
            and (.units == "fahrenheit" or .units == "celsius")
            and (.fetched_at | type) == "number"
            and (.expires_at | type) == "number"
            and .expires_at > .fetched_at)
    ' "$TMP_FILE" >/dev/null

    mv -f -- "$TMP_FILE" "$CACHE_FILE"
    TMP_FILE=""
}

case "${1:-}" in
    refresh)
        (( $# >= 2 && $# <= 3 )) || {
            printf 'usage: %s refresh [location] [auto|fahrenheit|celsius]\n' "${0##*/}" >&2
            exit 2
        }
        requested="${3:-auto}"
        refresh_set "$2" "$(jq -cn --arg mode "$requested" '[$mode]')"
        ;;
    refresh-set)
        (( $# == 3 )) || {
            printf 'usage: %s refresh-set [location] <units-json-array>\n' "${0##*/}" >&2
            exit 2
        }
        refresh_set "$2" "$3"
        ;;
    *)
        printf 'usage: %s refresh [location] [auto|fahrenheit|celsius]\n' "${0##*/}" >&2
        printf '       %s refresh-set [location] <units-json-array>\n' "${0##*/}" >&2
        exit 2
        ;;
esac
''', encoding="utf-8")

weather_qml.write_text(r'''pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string weatherHelper:
        configHome + "/hypr/scripts/quickshell_lockscreen_weather.sh"
    readonly property int minimumRefreshIntervalMs: 1200000
    readonly property string configuredLocation:
        String(BarState.lockscreenWeatherLocation() || "").trim()
    readonly property var configuredUnitModes: requiredUnitModes()
    readonly property bool refreshEnabled: configuredUnitModes.length > 0

    property string lastRequestIdentity: ""
    property double lastRequestMs: 0

    function normalizedUnitMode(value) {
        const mode = String(value || "auto");
        return ["auto", "fahrenheit", "celsius"].indexOf(mode) >= 0 ? mode : "auto";
    }

    function requiredUnitModes() {
        const modes = [];
        const seen = ({});
        function addProfile(profile) {
            if (!profile || typeof profile !== "object" || profile.lockscreen_show_weather !== true)
                return;
            const mode = root.normalizedUnitMode(profile.lockscreen_weather_units);
            if (seen[mode])
                return;
            seen[mode] = true;
            modes.push(mode);
        }

        addProfile(BarState.lockscreenSharedProfile());
        const overrides = BarState.lockscreenMonitorOverrides();
        for (const name of Object.keys(overrides || ({})))
            addProfile(overrides[name]);
        return modes;
    }

    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        const modes = root.requiredUnitModes();
        if (modes.length === 0 || refreshProcess.running)
            return;

        const sortedModes = modes.slice().sort();
        const now = Date.now();
        const requestIdentity = location + "|" + sortedModes.join(",");
        const requestChanged = requestIdentity !== root.lastRequestIdentity;
        if (!requestChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestIdentity = requestIdentity;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh-set", location, JSON.stringify(modes)]);
    }

    Process {
        id: refreshProcess
    }

    Timer {
        interval: 1200000
        repeat: true
        running: root.refreshEnabled
        onTriggered: root.requestRefresh()
    }

    Timer {
        id: stateRefresh
        interval: 180
        repeat: false
        onTriggered: root.requestRefresh()
    }

    Connections {
        target: BarState
        function onRevisionChanged() {
            if (root.refreshEnabled)
                stateRefresh.restart();
        }
    }

    Component.onCompleted: {
        if (root.refreshEnabled)
            stateRefresh.restart();
    }
}
''', encoding="utf-8")

cache_qml.write_text(r'''import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property bool enabled
    required property string units
    property string summary: ""

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")
    readonly property string cachePath: root.cacheHome
        + "/awtarchy/lockscreen-weather.json"

    function normalizedUnits(value) {
        const mode = String(value || "auto");
        return ["auto", "fahrenheit", "celsius"].indexOf(mode) >= 0 ? mode : "auto";
    }

    function selectedEntry(parsed) {
        if (parsed.entries && typeof parsed.entries === "object"
                && !Array.isArray(parsed.entries)) {
            const selected = parsed.entries[root.units];
            if (selected && typeof selected === "object" && !Array.isArray(selected))
                return selected;
            return null;
        }
        // Backward compatibility for a pre-monitor Shared-only cache.
        return typeof parsed.summary === "string" ? parsed : null;
    }

    function refreshCache() {
        if (!root.enabled) {
            root.summary = "";
            return;
        }

        const text = cacheFile.text();
        if (!text || text.length === 0) {
            root.summary = "";
            return;
        }

        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                root.summary = "";
                return;
            }

            const mode = root.normalizedUnits(root.units);
            const entry = parsed.entries && typeof parsed.entries === "object"
                ? parsed.entries[mode] : root.selectedEntry(parsed);
            if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
                root.summary = "";
                return;
            }

            const value = typeof entry.summary === "string"
                ? entry.summary.trim() : "";
            const expiresAt = Number(entry.expires_at);
            const provider = typeof entry.provider === "string"
                ? entry.provider : "";
            const now = Math.floor(Date.now() / 1000);

            if (value.length === 0 || Array.from(value).length > 96
                    || !Number.isFinite(expiresAt) || expiresAt <= now
                    || provider !== "open-meteo") {
                root.summary = "";
                return;
            }

            root.summary = value;
        } catch (error) {
            root.summary = "";
        }
    }

    onEnabledChanged: {
        if (root.enabled)
            cacheFile.reload();
        else
            root.summary = "";
    }
    onUnitsChanged: {
        if (root.enabled)
            root.refreshCache();
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: root.refreshCache()
        onFileChanged: root.refreshCache()
    }
}
''', encoding="utf-8")

# ---------------------------------------------------------------------------
# Passive editor previews: give each display a timezone result map and process.
# ---------------------------------------------------------------------------
editor = editor_qml.read_text(encoding="utf-8")
if 'property var monitorTimezoneValues: ({})' not in editor:
    old = '            id: secondaryPreviewWindow; required property var modelData; readonly property var monitorProfile: root.effectiveProfileForMonitor(modelData.name); screen: modelData; visible: root.open && !root.pickerSuspended && editorWindow.visible && editorWindow.screen && modelData.name !== editorWindow.screen.name\n'
    if old not in editor:
        raise SystemExit("Task 6 passive preview anchor missing")
    new = old + r'''            property var monitorTimezoneValues: ({})
            function refreshMonitorTimezoneValues() {
                const clocks = secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks || [];
                if (!Array.isArray(clocks) || clocks.length === 0) {
                    secondaryPreviewWindow.monitorTimezoneValues = ({});
                    return;
                }
                if (secondaryTimezoneProcess.running)
                    return;
                const args = [root.timezoneBackend, "--batch"];
                for (const clock of clocks)
                    args.push(String(clock.id), String(clock.timezone), String(clock.format || "24h"));
                secondaryTimezoneProcess.exec(args);
            }
            Process {
                id: secondaryTimezoneProcess
                stdout: SplitParser {
                    onRead: data => {
                        try {
                            const parsed = JSON.parse(String(data || "{}"));
                            secondaryPreviewWindow.monitorTimezoneValues = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
                        } catch (error) {
                            secondaryPreviewWindow.monitorTimezoneValues = ({});
                        }
                    }
                }
            }
            Timer {
                interval: 15000
                repeat: true
                running: secondaryPreviewWindow.visible
                    && Array.isArray(secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks)
                    && secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks.length > 0
                triggeredOnStart: true
                onTriggered: secondaryPreviewWindow.refreshMonitorTimezoneValues()
            }
            onMonitorProfileChanged: {
                if (secondaryPreviewWindow.visible)
                    Qt.callLater(() => secondaryPreviewWindow.refreshMonitorTimezoneValues());
            }
            onVisibleChanged: {
                if (secondaryPreviewWindow.visible)
                    Qt.callLater(() => secondaryPreviewWindow.refreshMonitorTimezoneValues());
            }
'''
    editor = editor.replace(old, new, 1)

old_timezone = 'timezoneClocks: secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks; timezoneValues: ({}); customTexts:'
new_timezone = 'timezoneClocks: secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks; timezoneValues: secondaryPreviewWindow.monitorTimezoneValues; customTexts:'
if old_timezone in editor:
    editor = editor.replace(old_timezone, new_timezone, 1)
elif new_timezone not in editor:
    raise SystemExit("Task 6 passive timezone binding anchor missing")
editor_qml.write_text(editor, encoding="utf-8")

# ---------------------------------------------------------------------------
# Secure surface: own timezone formatting locally. Keep the old required
# timezoneValues input temporarily for shell compatibility; Task 7 removes the
# global presentation facade when profiles are resolved directly per surface.
# ---------------------------------------------------------------------------
surface = surface_qml.read_text(encoding="utf-8")
if 'import Quickshell.Io' not in surface:
    surface = surface.replace('import QtQuick.Effects\n', 'import QtQuick.Effects\nimport Quickshell\nimport Quickshell.Io\n', 1)

if 'property var localTimezoneValues: ({})' not in surface:
    anchor = '    property int passwordFailureMaskCount: 0\n'
    if anchor not in surface:
        raise SystemExit("Task 6 secure timezone property anchor missing")
    surface = surface.replace(anchor, anchor + r'''
    property var localTimezoneValues: ({})
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string timezoneBackend: configHome
        + "/hypr/scripts/quickshell_lockscreen_timezones.sh"

    function refreshTimezoneValues() {
        const clocks = root.timezoneClocks || [];
        if (!Array.isArray(clocks) || clocks.length === 0) {
            root.localTimezoneValues = ({});
            return;
        }
        if (timezoneProcess.running)
            return;
        const args = [root.timezoneBackend, "--batch"];
        for (const clock of clocks)
            args.push(String(clock.id), String(clock.timezone), String(clock.format || "24h"));
        timezoneProcess.exec(args);
    }
''', 1)

if 'id: timezoneProcess' not in surface:
    anchor = '    PinchHandler {\n'
    if anchor not in surface:
        raise SystemExit("Task 6 secure timezone process anchor missing")
    block = r'''    Process {
        id: timezoneProcess
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(String(data || "{}"));
                    root.localTimezoneValues = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
                } catch (error) {
                    root.localTimezoneValues = ({});
                }
            }
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: Array.isArray(root.timezoneClocks) && root.timezoneClocks.length > 0
        triggeredOnStart: true
        onTriggered: root.refreshTimezoneValues()
    }

    onTimezoneClocksChanged: Qt.callLater(() => root.refreshTimezoneValues())

'''
    surface = surface.replace(anchor, block + anchor, 1)

surface = surface.replace('            timezoneValues: root.timezoneValues\n', '            timezoneValues: root.localTimezoneValues\n', 1)
surface_qml.write_text(surface, encoding="utf-8")

# ---------------------------------------------------------------------------
# Secure shell compatibility until Task 7 replaces scalar state with per-surface
# profiles. Read Shared weather units so the now-required cache selector compiles
# and retains current single-profile behavior during this intermediate commit.
# ---------------------------------------------------------------------------
shell = shell_qml.read_text(encoding="utf-8")
if 'property string lockWeatherUnits: "auto"' not in shell:
    shell = shell.replace('    property string lockWeatherLocation: ""\n', '    property string lockWeatherLocation: ""\n    property string lockWeatherUnits: "auto"\n', 1)

if 'function normalizedWeatherUnits(value)' not in shell:
    anchor = '    function normalizedBackground(value) {\n'
    if anchor not in shell:
        raise SystemExit("Task 6 weather unit normalizer anchor missing")
    block = '''    function normalizedWeatherUnits(value) {\n        const key = String(value || "auto");\n        return ["auto", "fahrenheit", "celsius"].indexOf(key) >= 0 ? key : "auto";\n    }\n\n'''
    shell = shell.replace(anchor, block + anchor, 1)

shell = shell.replace('        lockWeatherLocation = "";\n', '        lockWeatherLocation = "";\n        lockWeatherUnits = "auto";\n', 1)
shell = shell.replace('            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);\n', '            lockWeatherLocation = normalizedWeatherLocation(parsed.lockscreen_weather_location);\n            lockWeatherUnits = normalizedWeatherUnits(parsed.lockscreen_weather_units);\n', 1)
old_cache = '''    LockWeatherCache {\n        id: lockWeatherCache\n        enabled: root.lockShowWeather\n    }'''
new_cache = '''    LockWeatherCache {\n        id: lockWeatherCache\n        enabled: root.lockShowWeather\n        units: root.lockWeatherUnits\n    }'''
if old_cache in shell:
    shell = shell.replace(old_cache, new_cache, 1)
elif new_cache not in shell:
    raise SystemExit("Task 6 LockWeatherCache instance anchor missing")
shell_qml.write_text(shell, encoding="utf-8")
