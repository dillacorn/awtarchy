#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ZONEINFO_ROOT="/usr/share/zoneinfo"

valid_zone() {
    local zone="${1:-}"
    [[ -n "$zone" && "$zone" != /* && "$zone" != *'..'* && -f "$ZONEINFO_ROOT/$zone" ]]
}

format_zone() {
    local zone="$1"
    local format="${2:-24h}"
    valid_zone "$zone" || return 2
    case "$format" in
        12h) TZ="$zone" date '+%-I:%M %p' ;;
        24h) TZ="$zone" date '+%H:%M' ;;
        *) return 2 ;;
    esac
}

if [[ "${1:-}" == "--validate" ]]; then
    (( $# == 2 )) || { printf '%s\n' 'usage: quickshell_lockscreen_timezones.sh --validate <IANA-zone>' >&2; exit 2; }
    zone="$2"
    valid_zone "$zone" || { printf 'Timezone not found: %s\n' "$zone" >&2; exit 2; }
    printf '%s\n' "$zone"
elif [[ "${1:-}" == "--batch" ]]; then
    shift
    (( $# % 3 == 0 )) || { printf '%s\n' 'invalid timezone batch' >&2; false; }
    first=true
    printf '{'
    while (( $# >= 3 )); do
        id="$1"; zone="$2"; format="$3"; shift 3
        [[ "$id" =~ ^timezone-[A-Za-z0-9_-]{1,64}$ ]] || { printf '%s\n' 'invalid timezone id' >&2; false; }
        value="$(format_zone "$zone" "$format")" || { printf '%s\n' "invalid timezone: $zone" >&2; false; }
        if $first; then first=false; else printf ','; fi
        printf '"%s":"%s"' "$id" "$value"
    done
    printf '}\n'
else
    zone="${1:-UTC}"
    format="${2:-24h}"
    format_zone "$zone" "$format"
fi
