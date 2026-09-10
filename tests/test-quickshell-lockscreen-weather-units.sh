#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${ROOT}/config/hypr/scripts/quickshell_application_state.sh"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_weather.sh"
BAR="${ROOT}/config/quickshell/awtarchy/BarState.qml"
WEATHER="${ROOT}/config/quickshell/awtarchy/LockscreenWeather.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

# Persistent preference and strict enum validation.
require_text "$STATE" 'LOCKSCREEN_WEATHER_UNITS_JSON=' 'weather-unit enum is missing'
require_text "$STATE" '.lockscreen_weather_units = "auto"' 'weather-unit reset default is not Auto'
require_text "$STATE" 'validate_lockscreen_weather_units()' 'weather-unit validator is missing'
require_text "$STATE" 'local weather_units="${12:-auto}"' 'atomic editor save does not accept weather units'
require_text "$STATE" '.lockscreen_weather_units = $weather_units' 'atomic editor save does not persist weather units'

# BarState remains the unlocked persistent state owner.
require_text "$BAR" 'function lockscreenWeatherUnits()' 'BarState has no weather-unit getter'
require_text "$BAR" '["auto", "fahrenheit", "celsius"]' 'BarState does not validate weather-unit values'

# The unlocked refresh service invalidates its throttle identity when units change.
require_text "$WEATHER" 'readonly property string configuredUnits:' 'weather service does not read configured units'
require_text "$WEATHER" 'property string lastRequestIdentity: ""' 'weather service has no request identity'
require_text "$WEATHER" 'const requestIdentity = location + "|" + units;' 'weather service identity omits units'
require_text "$WEATHER" 'refreshProcess.exec([root.weatherHelper, "refresh", location, units]);' 'weather service does not pass units to helper'

# Editor units are draft state, so Cancel cannot accidentally persist them.
require_text "$EDITOR" 'property string draftWeatherUnits: "auto"' 'editor has no weather-unit draft'
require_text "$EDITOR" 'weatherUnits: draftWeatherUnits' 'editor history omits weather units'
require_text "$EDITOR" 'draftWeatherUnits = BarState.lockscreenWeatherUnits();' 'editor does not load persisted weather units'
require_text "$EDITOR" 'draftWeatherUnits = "auto";' 'editor reset does not restore Auto weather units'
require_text "$EDITOR" 'function setDraftWeatherUnits(value)' 'editor has no weather-unit setter'
require_text "$EDITOR" 'label: "Auto"' 'Auto weather-unit control is missing'
require_text "$EDITOR" 'label: "°F"' 'Fahrenheit weather-unit control is missing'
require_text "$EDITOR" 'label: "°C"' 'Celsius weather-unit control is missing'
require_text "$EDITOR" 'draftWeatherUnits' 'editor save does not include weather units'

# Helper resolves Auto from locale and requests an explicit Open-Meteo unit.
require_text "$HELPER" 'resolve_units()' 'weather helper has no unit resolver'
require_text "$HELPER" 'LC_ALL' 'Auto units do not inspect LC_ALL'
require_text "$HELPER" 'LC_MEASUREMENT' 'Auto units do not inspect LC_MEASUREMENT'
require_text "$HELPER" 'LANG' 'Auto units do not inspect LANG'
require_text "$HELPER" '*_US*)' 'Auto units do not map US locales to Fahrenheit'
require_text "$HELPER" '--data-urlencode "temperature_unit=$resolved_units"' 'Open-Meteo request does not use resolved units'
require_text "$HELPER" '--arg units "$resolved_units"' 'weather cache does not record resolved request units'
require_text "$HELPER" 'units: $units' 'weather cache payload omits resolved units'

# Runtime mapping: use a curl stub that reports the requested unit back in the response.
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache" "$TMP/home"
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
    *ipwho.is*)
        printf '%s\n' '{"success":true,"city":"Pittsburgh","region":"Pennsylvania","country_code":"US","latitude":40.4406,"longitude":-79.9959}'
        ;;
    *api.open-meteo.com*)
        if [[ "$args" == *temperature_unit=fahrenheit* ]]; then
            printf '%s\n' '{"current":{"temperature_2m":72.0,"weather_code":0},"current_units":{"temperature_2m":"°F"}}'
        elif [[ "$args" == *temperature_unit=celsius* ]]; then
            printf '%s\n' '{"current":{"temperature_2m":22.0,"weather_code":0},"current_units":{"temperature_2m":"°C"}}'
        else
            exit 64
        fi
        ;;
    *)
        exit 22
        ;;
esac
STUB
chmod 0755 "$TMP/bin/curl"

run_case() {
    local locale="$1" units="$2" expected_units="$3" expected_summary="$4"
    rm -rf -- "$TMP/cache/awtarchy"
    env -i \
        PATH="$TMP/bin:/usr/bin:/bin" \
        HOME="$TMP/home" \
        XDG_CACHE_HOME="$TMP/cache" \
        LANG="$locale" \
        bash "$HELPER" refresh '' "$units"
    jq -e --arg units "$expected_units" --arg summary "$expected_summary" '
        .provider == "open-meteo"
        and .units == $units
        and .summary == $summary
    ' "$TMP/cache/awtarchy/lockscreen-weather.json" >/dev/null \
        || fail "weather helper mapped ${locale}/${units} incorrectly"
}

run_case 'en_US.UTF-8' auto fahrenheit '72°F · Clear'
run_case 'en_GB.UTF-8' auto celsius '22°C · Clear'
run_case 'en_US.UTF-8' celsius celsius '22°C · Clear'
run_case 'en_GB.UTF-8' fahrenheit fahrenheit '72°F · Clear'

if env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" LANG='en_US.UTF-8' \
    bash "$HELPER" refresh '' kelvin >/dev/null 2>&1; then
    fail 'weather helper accepted an unsupported unit mode'
fi

printf '%s\n' 'PASS: lockscreen weather Auto/Fahrenheit/Celsius contracts'
