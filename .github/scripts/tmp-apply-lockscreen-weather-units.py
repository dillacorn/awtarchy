#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "config/hypr/scripts/quickshell_application_state.sh"
HELPER = ROOT / "config/hypr/scripts/quickshell_lockscreen_weather.sh"
BAR = ROOT / "config/quickshell/awtarchy/BarState.qml"
WEATHER = ROOT / "config/quickshell/awtarchy/LockscreenWeather.qml"
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# Persistent state and the editor command boundary.
text = STATE.read_text()
text = once(
    text,
    "LOCKSCREEN_OVERLAY_MODES_JSON='[\"none\",\"dark\",\"light\"]'\n",
    "LOCKSCREEN_OVERLAY_MODES_JSON='[\"none\",\"dark\",\"light\"]'\n"
    "LOCKSCREEN_WEATHER_UNITS_JSON='[\"auto\",\"fahrenheit\",\"celsius\"]'\n",
    "weather unit enum",
)
anchor = '''normalize_lockscreen_weather_location() {
'''
validator = '''validate_lockscreen_weather_units() {
    local value="$1"
    if ! jq -e -n \\
        --arg value "$value" \\
        --argjson allowed "$LOCKSCREEN_WEATHER_UNITS_JSON" \\
        '$allowed | index($value) != null' >/dev/null 2>&1; then
        printf 'invalid lockscreen weather units: %s\\n' "$value" >&2
        exit 2
    fi
}

'''
text = once(text, anchor, validator + anchor, "weather unit validator")
text = once(
    text,
    '    local wallpaper_blur="${11:-0}"\n',
    '    local wallpaper_blur="${11:-0}"\n    local weather_units="${12:-auto}"\n',
    "editor save weather argument",
)
text = once(
    text,
    '''    validate_lockscreen_overlay_mode "$overlay_mode"
    focal_x="$(normalize_unit_interval "$focal_x" 'lockscreen wallpaper focal x')"
''',
    '''    validate_lockscreen_overlay_mode "$overlay_mode"
    validate_lockscreen_weather_units "$weather_units"
    focal_x="$(normalize_unit_interval "$focal_x" 'lockscreen wallpaper focal x')"
''',
    "editor save weather validation",
)
text = once(
    text,
    '''        --argjson wallpaper_blur "$wallpaper_blur" '
''',
    '''        --argjson wallpaper_blur "$wallpaper_blur" \\
        --arg weather_units "$weather_units" '
''',
    "editor save weather jq arg",
)
text = once(
    text,
    '''        | .lockscreen_wallpaper_blur = $wallpaper_blur
''',
    '''        | .lockscreen_wallpaper_blur = $wallpaper_blur
        | .lockscreen_weather_units = $weather_units
''',
    "editor save weather persistence",
)
text = once(
    text,
    '''        | .lockscreen_wallpaper_blur = 0
        | .lockscreen_weather_location = ""
''',
    '''        | .lockscreen_wallpaper_blur = 0
        | .lockscreen_weather_units = "auto"
        | .lockscreen_weather_location = ""
''',
    "weather reset default",
)
text = once(
    text,
    '''    save-lockscreen-editor)
        [[ $# -eq 6 ]] || exit 2
        save_lockscreen_editor "$2" "$3" "$4" "$5" "$6"
        ;;
''',
    '''    save-lockscreen-editor)
        case "$#" in
            6|12|13) ;;
            *) exit 2 ;;
        esac
        save_lockscreen_editor "${@:2}"
        ;;
''',
    "expanded editor save dispatch",
)
STATE.write_text(text)

# Weather helper. Networking remains unlocked-only; this only selects the
# explicit Open-Meteo unit before the request and records that request identity.
text = HELPER.read_text()
anchor = '''weather_description() {
'''
resolver = '''resolve_units() {
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
            printf 'invalid weather units: %s\\n' "$requested" >&2
            exit 2
            ;;
    esac
}

'''
text = once(text, anchor, resolver + anchor, "weather unit resolver")
text = once(
    text,
    '''refresh_weather() {
    local location="$1"
    local resolved latitude longitude display_location forecast_json
    local temperature unit code description summary fetched_at expires_at
''',
    '''refresh_weather() {
    local location="$1" requested_units="$2" resolved_units
    local resolved latitude longitude display_location forecast_json
    local temperature unit code description summary fetched_at expires_at
''',
    "weather refresh arguments",
)
text = once(
    text,
    '''    need jq
    validate_location "$location"

    resolved="$(resolve_location "$location")"
''',
    '''    need jq
    validate_location "$location"
    resolved_units="$(resolve_units "$requested_units")"

    resolved="$(resolve_location "$location")"
''',
    "weather resolve units before network",
)
text = once(
    text,
    '''        --data 'current=temperature_2m,weather_code' \\
        --data 'temperature_unit=fahrenheit' \\
        --data 'timezone=auto')"
''',
    '''        --data 'current=temperature_2m,weather_code' \\
        --data-urlencode "temperature_unit=$resolved_units" \\
        --data 'timezone=auto')"
''',
    "Open-Meteo unit request",
)
text = once(
    text,
    '''        --arg summary "$summary" \\
        --arg location "$display_location" \\
        --argjson fetched_at "$fetched_at" \\
''',
    '''        --arg summary "$summary" \\
        --arg location "$display_location" \\
        --arg units "$resolved_units" \\
        --argjson fetched_at "$fetched_at" \\
''',
    "weather cache units arg",
)
text = once(
    text,
    '''            summary: $summary,
            location: $location,
            fetched_at: $fetched_at,
''',
    '''            summary: $summary,
            location: $location,
            units: $units,
            fetched_at: $fetched_at,
''',
    "weather cache units field",
)
text = once(
    text,
    '''        and (.location | type) == "string"
        and (.fetched_at | type) == "number"
''',
    '''        and (.location | type) == "string"
        and (.units == "fahrenheit" or .units == "celsius")
        and (.fetched_at | type) == "number"
''',
    "weather cache units validation",
)
text = once(
    text,
    '''    refresh)
        [[ $# -eq 2 ]] || {
            printf 'usage: %s refresh [location]\\n' "${0##*/}" >&2
            exit 2
        }
        refresh_weather "$2"
        ;;
    *)
        printf 'usage: %s refresh [location]\\n' "${0##*/}" >&2
''',
    '''    refresh)
        (( $# >= 2 && $# <= 3 )) || {
            printf 'usage: %s refresh [location] [auto|fahrenheit|celsius]\\n' "${0##*/}" >&2
            exit 2
        }
        refresh_weather "$2" "${3:-auto}"
        ;;
    *)
        printf 'usage: %s refresh [location] [auto|fahrenheit|celsius]\\n' "${0##*/}" >&2
''',
    "weather CLI units",
)
HELPER.write_text(text)

# BarState getter.
text = BAR.read_text()
anchor = '''    function lockscreenWeatherLocation() {
'''
getter = '''    function lockscreenWeatherUnits() {
        const value = String(data().lockscreen_weather_units || "auto");
        return ["auto", "fahrenheit", "celsius"].indexOf(value) >= 0 ? value : "auto";
    }

'''
text = once(text, anchor, getter + anchor, "BarState weather unit getter")
BAR.write_text(text)

# Unlocked weather refresh service: include units in the throttle identity.
text = WEATHER.read_text()
text = once(
    text,
    '''    readonly property bool refreshEnabled: BarState.lockscreenShowWeather()

    property string lastRequestedLocation: ""
''',
    '''    readonly property bool refreshEnabled: BarState.lockscreenShowWeather()
    readonly property string configuredUnits: BarState.lockscreenWeatherUnits()

    property string lastRequestIdentity: ""
''',
    "weather service unit state",
)
old_request = '''    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        if (!root.refreshEnabled || refreshProcess.running)
            return;

        const now = Date.now();
        const locationChanged = location !== root.lastRequestedLocation;
        if (!locationChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestedLocation = location;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh", location]);
    }
'''
new_request = '''    function requestRefresh() {
        const location = String(root.configuredLocation || "").trim();
        const units = String(root.configuredUnits || "auto");
        if (!root.refreshEnabled || refreshProcess.running)
            return;

        const now = Date.now();
        const requestIdentity = location + "|" + units;
        const requestChanged = requestIdentity !== root.lastRequestIdentity;
        if (!requestChanged && root.lastRequestMs > 0
                && now - root.lastRequestMs < root.minimumRefreshIntervalMs)
            return;

        root.lastRequestIdentity = requestIdentity;
        root.lastRequestMs = now;
        refreshProcess.exec([root.weatherHelper, "refresh", location, units]);
    }
'''
text = once(text, old_request, new_request, "weather refresh unit identity")
WEATHER.write_text(text)

# Editor draft/history/save controls.
text = EDITOR.read_text()
text = once(
    text,
    '''    property int draftWallpaperBlur: 0
    property var draftAutoAccents: defaultAutoAccents()
''',
    '''    property int draftWallpaperBlur: 0
    property string draftWeatherUnits: "auto"
    property var draftAutoAccents: defaultAutoAccents()
''',
    "editor weather draft property",
)
text = once(
    text,
    '''            overlayStrength: draftOverlayStrength,
            wallpaperBlur: draftWallpaperBlur
''',
    '''            overlayStrength: draftOverlayStrength,
            wallpaperBlur: draftWallpaperBlur,
            weatherUnits: draftWeatherUnits
''',
    "editor weather history snapshot",
)
text = once(
    text,
    '''        draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(100, Math.round(wallpaperBlur))) : 0;
        scheduleContrastRefresh();
''',
    '''        draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(100, Math.round(wallpaperBlur))) : 0;
        draftWeatherUnits = ["auto", "fahrenheit", "celsius"].indexOf(String(snapshot.weatherUnits)) >= 0
            ? String(snapshot.weatherUnits) : "auto";
        scheduleContrastRefresh();
''',
    "editor weather history restore",
)
anchor = '''    function acceptWallpaperSelection(line) {
'''
setter = '''    function setDraftWeatherUnits(value) {
        const units = String(value || "");
        if (["auto", "fahrenheit", "celsius"].indexOf(units) < 0)
            return;
        recordUndoBeforeChange();
        draftWeatherUnits = units;
    }

'''
text = once(text, anchor, setter + anchor, "editor weather unit setter")
text = once(
    text,
    '''        draftWallpaperBlur = 0;
        draftAutoAccents = defaultAutoAccents();
''',
    '''        draftWallpaperBlur = 0;
        draftWeatherUnits = "auto";
        draftAutoAccents = defaultAutoAccents();
''',
    "editor weather reset",
)
text = once(
    text,
    '''        draftWallpaperBlur = BarState.lockscreenWallpaperBlur();
        draftAutoAccents = defaultAutoAccents();
''',
    '''        draftWallpaperBlur = BarState.lockscreenWallpaperBlur();
        draftWeatherUnits = BarState.lockscreenWeatherUnits();
        draftAutoAccents = defaultAutoAccents();
''',
    "editor weather load",
)
text = once(
    text,
    '''            draftOverlayMode,
            String(draftOverlayStrength),
            String(draftWallpaperBlur)
''',
    '''            draftOverlayMode,
            String(draftOverlayStrength),
            String(draftWallpaperBlur),
            draftWeatherUnits
''',
    "editor weather save",
)
text = once(
    text,
    '''                weatherText: "72°F · Clear"
''',
    '''                weatherText: root.draftWeatherUnits === "celsius"
                    ? "22°C · Clear" : "72°F · Clear"
''',
    "editor weather preview units",
)
text = once(
    text,
    '''                height: 224 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)
''',
    '''                height: 252 + ((root.elementPaletteOpen || root.backgroundPaletteOpen) ? 150 : 0)
''',
    "editor panel weather row height",
)
anchor = '''                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 142 : 0
                        spacing: 12
                        visible: root.elementPaletteOpen || root.backgroundPaletteOpen
'''
weather_row = '''                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            text: "Weather units"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }
                        SettingsButton {
                            label: "Auto"
                            active: root.draftWeatherUnits === "auto"
                            textSize: 9
                            onClicked: root.setDraftWeatherUnits("auto")
                        }
                        SettingsButton {
                            label: "°F"
                            active: root.draftWeatherUnits === "fahrenheit"
                            textSize: 9
                            onClicked: root.setDraftWeatherUnits("fahrenheit")
                        }
                        SettingsButton {
                            label: "°C"
                            active: root.draftWeatherUnits === "celsius"
                            textSize: 9
                            onClicked: root.setDraftWeatherUnits("celsius")
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Auto follows the system measurement locale."
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

'''
text = once(text, anchor, weather_row + anchor, "editor weather unit controls")
EDITOR.write_text(text)
