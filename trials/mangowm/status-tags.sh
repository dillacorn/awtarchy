#!/usr/bin/env bash
# Stock Waybar-compatible Mango tag summary. No unreleased Waybar modules.
set -euo pipefail

fallback='{"text":"Tags ?","tooltip":"Mango IPC unavailable","class":"unavailable"}'
if ! command -v mmsg >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$fallback"
    exit 0
fi
tags="$(mmsg get all-tags 2>/dev/null)" || { printf '%s\n' "$fallback"; exit 0; }
monitor="$(mmsg get cursorpos 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null || true)"
printf '%s\n' "$tags" | jq -c --arg monitor "$monitor" '
    (.all_tags // []) as $monitors
    | (($monitors | map(select(.monitor == $monitor)) | .[0].tags)
      // ($monitors[0].tags // [])) as $tags
    | {text: ($tags | map(
        if .is_active then "[" + (.index | tostring) + "]"
        elif .client_count > 0 then (.index | tostring)
        else "·" end
      ) | join(" ")),
      tooltip: ("Mango tags / monitor: " + (if $monitor == "" then "unknown" else $monitor end)),
      class: "mango-tags"}
' || printf '%s\n' "$fallback"
