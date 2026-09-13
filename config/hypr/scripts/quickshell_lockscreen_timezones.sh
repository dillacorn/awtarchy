#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ZONEINFO_ROOT="/usr/share/zoneinfo"
zone="${1:-}"
format="${2:-+%H:%M}"

if [[ -z "$zone" || "$zone" == /* || "$zone" == *".."* || "$zone" == *$'\n'* || "$zone" == *$'\r'* ]]; then
    printf 'invalid timezone: %s\n' "$zone" >&2
    exit 2
fi

zone_path="${ZONEINFO_ROOT}/${zone}"
if [[ ! -f "$zone_path" ]]; then
    printf 'unknown timezone: %s\n' "$zone" >&2
    exit 3
fi

TZ="$zone" date "$format"
