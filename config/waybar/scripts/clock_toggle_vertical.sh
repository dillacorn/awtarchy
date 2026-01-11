#!/usr/bin/env bash
# ~/.config/waybar/scripts/clock_toggle_vertical.sh
# Splits clock_toggle.sh JSON text into icon|a|b for vertical instances.
#
# clock_toggle.sh .text expected:
#   " HH:MM" or " MM-DD" (icon + space + value)

set -euo pipefail

mode="${1:-}"
SRC="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/scripts/clock_toggle.sh"
json="$("$SRC" 2>/dev/null || true)"

command -v jq >/dev/null 2>&1 || { printf '%s\n' "$json"; exit 0; }

# Extract pieces from `.text`
# Returns empty strings if format unexpected.
jq -c --arg mode "$mode" '
  def split_text:
    (.text // "") as $t
    | if ($t | test("^\\S+\\s+.+$")) then
        ($t | capture("^(?<ico>\\S+)\\s+(?<rest>.+)$")) as $m
        | ($m.ico // "") as $ico
        | ($m.rest // "") as $rest
        | if ($rest | test(":")) then
            ($rest | split(":")) as $p
            | {ico:$ico, a:($p[0] // ""), b:($p[1] // "")}
          elif ($rest | test("-")) then
            ($rest | split("-")) as $p
            | {ico:$ico, a:($p[0] // ""), b:($p[1] // "")}
          else
            {ico:$ico, a:$rest, b:""}
          end
      else
        {ico:"", a:"", b:""}
      end;

  split_text as $s
  | if $mode == "icon" then .text = $s.ico
    elif $mode == "a" then .text = $s.a
    elif $mode == "b" then .text = $s.b
    else .
    end
' <<<"$json"
