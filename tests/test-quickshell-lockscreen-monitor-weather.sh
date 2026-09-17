#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT/config/hypr/scripts/quickshell_lockscreen_weather.sh"
WEATHER="$ROOT/config/quickshell/awtarchy/LockscreenWeather.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
CACHE="$ROOT/config/quickshell/awtarchy-lock/LockWeatherCache.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }

mkdir -p "$TMP/bin" "$TMP/cache/awtarchy" "$TMP/home"
cat >"$TMP/bin/date" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "+%s" ]]; then
    printf '%s\n' 2000000000
else
    /usr/bin/date "$@"
fi
STUB
cat >"$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_CURL_LOG"
case "$*" in
    *ipwho.is*)
        printf '%s\n' '{"success":true,"city":"Pittsburgh","region":"Pennsylvania","country_code":"US","latitude":40.4406,"longitude":-79.9959}'
        ;;
    *api.open-meteo.com*)
        if [[ "$*" == *temperature_unit=fahrenheit* ]]; then
            printf '%s\n' '{"current":{"temperature_2m":72.0,"weather_code":0},"current_units":{"temperature_2m":"°F"}}'
        elif [[ "$*" == *temperature_unit=celsius* ]]; then
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
chmod 0755 "$TMP/bin/date" "$TMP/bin/curl"
export TEST_CURL_LOG="$TMP/curl.log"

PATH="$TMP/bin:/usr/bin:/bin" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" LANG='en_US.UTF-8' \
    bash "$HELPER" refresh-set '' '["fahrenheit","celsius","fahrenheit"]' \
    || fail 'weather helper rejected a valid multi-profile refresh set'

weather_cache="$TMP/cache/awtarchy/lockscreen-weather.json"
[[ -s "$weather_cache" ]] || fail 'multi-profile weather refresh wrote no cache'
jq -e '
    .provider == "open-meteo"
    and .summary == "72°F · Clear"
    and .units == "fahrenheit"
    and .entries.fahrenheit.provider == "open-meteo"
    and .entries.fahrenheit.requested_units == "fahrenheit"
    and .entries.fahrenheit.units == "fahrenheit"
    and .entries.fahrenheit.summary == "72°F · Clear"
    and .entries.celsius.provider == "open-meteo"
    and .entries.celsius.requested_units == "celsius"
    and .entries.celsius.units == "celsius"
    and .entries.celsius.summary == "22°C · Clear"
    and (.entries | keys | sort) == ["celsius","fahrenheit"]
    and .entries.fahrenheit.fetched_at == 2000000000
    and .entries.celsius.fetched_at == 2000000000
    and .entries.fahrenheit.expires_at == 2000001800
    and .entries.celsius.expires_at == 2000001800
' "$weather_cache" >/dev/null || fail 'multi-profile weather cache did not preserve both requested unit modes'

[[ "$(grep -Fc -- 'ipwho.is' "$TEST_CURL_LOG")" -eq 1 ]] \
    || fail 'refresh-set resolved the shared weather location more than once'
[[ "$(grep -Fc -- 'api.open-meteo.com' "$TEST_CURL_LOG")" -eq 2 ]] \
    || fail 'refresh-set did not fetch exactly the two deduplicated required forecast units'

# The old one-profile command remains valid for callers outside the new monitor
# aggregation path and mirrors its selected entry at the legacy top level.
: >"$TEST_CURL_LOG"
PATH="$TMP/bin:/usr/bin:/bin" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" LANG='en_GB.UTF-8' \
    bash "$HELPER" refresh '' celsius \
    || fail 'legacy single-profile weather refresh stopped working'
jq -e '
    .provider == "open-meteo"
    and .summary == "22°C · Clear"
    and .units == "celsius"
    and .entries.celsius.summary == "22°C · Clear"
' "$weather_cache" >/dev/null || fail 'legacy weather refresh no longer mirrors the requested entry'

# Unlocked refresh aggregates only profiles that actually show weather.
require_text "$WEATHER" 'function requiredUnitModes()' \
    'unlocked weather service has no per-profile unit aggregation'
require_text "$WEATHER" 'BarState.lockscreenSharedProfile()' \
    'unlocked weather service does not inspect Shared lockscreen state'
require_text "$WEATHER" 'BarState.lockscreenMonitorOverrides()' \
    'unlocked weather service does not inspect monitor overrides'
require_text "$WEATHER" 'profile.lockscreen_show_weather === true' \
    'unlocked weather service refreshes units for profiles that hide weather'
require_text "$WEATHER" '"refresh-set"' \
    'unlocked weather service does not use the multi-profile refresh command'
require_text "$WEATHER" 'JSON.stringify(modes)' \
    'unlocked weather service does not pass the deduplicated requested modes atomically'

# Secure cache lookup is exact by requested profile mode. A Fahrenheit profile
# must never consume the Celsius entry merely because it was refreshed later.
require_text "$CACHE" 'required property string units' \
    'secure weather cache has no requested-unit profile input'
require_text "$CACHE" 'parsed.entries[root.units]' \
    'secure weather cache does not select the exact requested unit entry'
require_text "$CACHE" 'const selected = parsed.entries' \
    'secure weather cache has no entries-map selection path'
require_text "$CACHE" 'parsed.summary' \
    'secure weather cache lost legacy single-summary fallback'

# Every passive editor display owns timezone output for its own effective profile.
require_text "$EDITOR" 'property var monitorTimezoneValues: ({})' \
    'passive monitor preview has no local timezone-value map'
require_text "$EDITOR" 'function refreshMonitorTimezoneValues()' \
    'passive monitor preview cannot refresh its own timezone clocks'
require_text "$EDITOR" 'secondaryTimezoneProcess' \
    'passive monitor preview has no independent timezone helper process'
require_text "$EDITOR" 'timezoneValues: secondaryPreviewWindow.monitorTimezoneValues' \
    'passive monitor preview still consumes active-editor timezone values'
require_text "$EDITOR" 'secondaryPreviewWindow.monitorProfile.lockscreen_timezone_clocks' \
    'passive monitor timezone refresh is not scoped to its effective profile'

# LockSurface owns the formatter process so identical timezone element IDs on
# different secure outputs cannot share one global value map. Task 7 will feed
# this surface the independently resolved monitor profile.
require_text "$SURFACE" 'property var localTimezoneValues: ({})' \
    'secure lock surface has no local timezone-value map'
require_text "$SURFACE" 'function refreshTimezoneValues()' \
    'secure lock surface cannot refresh its own timezone clocks'
require_text "$SURFACE" 'id: timezoneProcess' \
    'secure lock surface has no independent timezone helper process'
require_text "$SURFACE" 'timezoneValues: root.localTimezoneValues' \
    'secure scene still consumes a shared timezone-value map'

printf '%s\n' 'PASS: lockscreen per-monitor weather and timezone contracts'
