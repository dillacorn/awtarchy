#!/usr/bin/env bash
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
