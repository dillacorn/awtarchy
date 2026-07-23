#!/usr/bin/env bash
# Per-output DDC brightness module for Waybar.

set -euo pipefail
export LC_ALL=C

BRIGHTNESS_SCRIPT="${HYPR_BRIGHTNESS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr-ddc-brightness.sh}"
QUICK_SETTINGS="${HYPR_QUICK_SETTINGS_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/hypr_quicksettings.sh}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-ddc-brightness"
CACHE_MAX_AGE_MS="${WAYBAR_DDC_CACHE_MAX_AGE_MS:-30000}"
STEP="${WAYBAR_DDC_STEP:-5}"
SIGNAL="${WAYBAR_DDC_SIGNAL:-15}"

now_ms() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    printf '%s\n' "$(( $(date +%s) * 1000 ))"
  fi
}

focused_monitor() {
  hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused == true or .focused == "yes") | .name
  ' | head -n 1
}

monitor_under_cursor() {
  local cursor x y

  cursor="$(hyprctl -j cursorpos 2>/dev/null)" || return 1
  x="$(jq -r '.x // empty' <<<"$cursor")"
  y="$(jq -r '.y // empty' <<<"$cursor")"

  [[ "$x" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  [[ "$y" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1

  hyprctl -j monitors 2>/dev/null | jq -r \
    --argjson x "$x" \
    --argjson y "$y" '
      def rotated:
        ((.transform // 0) % 2) == 1;

      def logical_width:
        if rotated then
          (.height / (.scale // 1))
        else
          (.width / (.scale // 1))
        end;

      def logical_height:
        if rotated then
          (.width / (.scale // 1))
        else
          (.height / (.scale // 1))
        end;

      .[]
      | select(
          $x >= .x
          and $x < (.x + logical_width)
          and $y >= .y
          and $y < (.y + logical_height)
        )
      | .name
    ' | head -n 1
}

resolve_monitor() {
  local monitor="${WAYBAR_OUTPUT_NAME:-}"

  if [[ -z "$monitor" ]]; then
    monitor="$(monitor_under_cursor || true)"
  fi

  if [[ -z "$monitor" ]]; then
    monitor="$(focused_monitor || true)"
  fi

  [[ -n "$monitor" ]] || return 1
  printf '%s\n' "$monitor"
}

state_file() {
  printf '%s/state_%s.tsv\n' "$CACHE_DIR" "$1"
}

read_cached_status() {
  local monitor="$1"
  local file cur max timestamp current age

  file="$(state_file "$monitor")"
  [[ -r "$file" ]] || return 1

  read -r cur max timestamp <"$file" || return 1

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$timestamp" =~ ^[0-9]+$ ]] || return 1

  current="$(now_ms)"
  age=$((current - timestamp))

  (( age >= 0 && age <= CACHE_MAX_AGE_MS )) || return 1
  printf '%s %s\n' "$cur" "$max"
}

query_status() {
  local monitor="$1"
  local output cur max

  output="$(
    HYPR_DDC_NOTIFY=0 \
      "$BRIGHTNESS_SCRIPT" --monitor "$monitor" status 2>/dev/null
  )" || return 1

  cur="$(awk -F= '$1 == "cur" {print $2; exit}' <<<"$output")"
  max="$(awk -F= '$1 == "max" {print $2; exit}' <<<"$output")"

  [[ "$cur" =~ ^[0-9]+$ ]] || return 1
  [[ "$max" =~ ^[1-9][0-9]*$ ]] || return 1

  printf '%s %s\n' "$cur" "$max"
}

print_status() {
  local monitor cur max percent tooltip

  monitor="$(resolve_monitor)" || {
    jq -cn \
      '{text:" ?",tooltip:"No Hyprland monitor found",class:["error"]}'
    return 0
  }

  if ! read -r cur max < <(read_cached_status "$monitor"); then
    if ! read -r cur max < <(query_status "$monitor"); then
      jq -cn \
        --arg monitor "$monitor" \
        '{
          text:" ?",
          tooltip:("Brightness " + $monitor + ": DDC unavailable"),
          class:["error"]
        }'
      return 0
    fi
  fi

  percent=$((cur * 100 / max))
  tooltip="Brightness ${monitor}: ${cur}/${max}
Scroll to adjust this display
Left/right click to toggle Hypr Quick Settings"

  jq -cn \
    --arg text " ${cur}" \
    --arg tooltip "$tooltip" \
    --argjson percentage "$percent" \
    '{
      text:$text,
      tooltip:$tooltip,
      class:["ddc-brightness"],
      percentage:$percentage
    }'
}

signal_waybar_later() {
  (
    sleep 0.4
    pkill -RTMIN+"$SIGNAL" -x waybar 2>/dev/null || true
  ) >/dev/null 2>&1 &
}

adjust() {
  local direction="$1"
  local monitor

  monitor="$(monitor_under_cursor || true)"
  [[ -n "$monitor" ]] || monitor="$(resolve_monitor)"

  "$BRIGHTNESS_SCRIPT" --monitor "$monitor" "$direction" "$STEP"
  signal_waybar_later
}

quick_settings_addresses() {
  hyprctl clients -j 2>/dev/null |
    jq -r '
      (. // [])[]
      | select(
          .mapped == true
          and .hidden == false
          and (
            .class == "hypr_quicksettings"
            or .initialClass == "hypr_quicksettings"
          )
        )
      | .address
    '
}

toggle_quick_settings() {
  local monitor runtime_dir lock_file lock_dir address
  local -a addresses=()

  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  lock_file="${runtime_dir}/waybar-ddc-quicksettings.lock"
  lock_dir="${lock_file}.d"

  mkdir -p "$runtime_dir"

  # Never wait behind another click. Extra clicks during launch/close are dropped.
  if command -v flock >/dev/null 2>&1; then
    exec 8>"$lock_file"
    flock -n 8 || return 0
  else
    mkdir "$lock_dir" 2>/dev/null || return 0
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  fi

  mapfile -t addresses < <(quick_settings_addresses)

  # Existing instance: close every match and do not relaunch.
  if (( ${#addresses[@]} > 0 )); then
    for address in "${addresses[@]}"; do
      [[ -n "$address" ]] || continue

      hyprctl dispatch "hl.dsp.window.close({ window = \"address:${address}\" })" >/dev/null 2>&1 || true
    done

    # Hold the nonblocking lock only until Hyprland removes the window.
    for _ in {1..20}; do
      [[ -z "$(quick_settings_addresses)" ]] && return 0
      sleep 0.05
    done

    return 0
  fi

  monitor="$(monitor_under_cursor || true)"
  [[ -n "$monitor" ]] || monitor="$(resolve_monitor)"

  # Launch Alacritty directly. --ui prevents hypr_quicksettings.sh from
  # attempting to launch a second terminal.
  HYPR_BRIGHTNESS_MONITOR="$monitor" \
    alacritty \
      --class hypr_quicksettings \
      -e "$QUICK_SETTINGS" --ui \
      >/dev/null 2>&1 8>&- &

  # Release the lock immediately once the actual window becomes visible.
  for _ in {1..40}; do
    [[ -n "$(quick_settings_addresses)" ]] && return 0
    sleep 0.05
  done

  return 0
}

case "${1:-status}" in
  status|"")
    print_status
    ;;
  up)
    adjust up
    ;;
  down)
    adjust down
    ;;
  menu)
    toggle_quick_settings
    ;;
  *)
    printf 'Usage: %s {status|up|down|menu}\n' "$0" >&2
    exit 2
    ;;
esac
