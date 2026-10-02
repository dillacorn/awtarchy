#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER_SOURCE="${ROOT}/config/hypr/scripts/hypr-ddc-brightness.sh"
BAR_MODULE_SOURCE="${ROOT}/config/hypr/scripts/ddc_brightness.sh"
QUICKSETTINGS_CORE="${ROOT}/config/hypr/scripts/hypr_quicksettings_core.sh"
QUICKSETTINGS_BACKEND="${ROOT}/config/hypr/scripts/hypr_quicksettings.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
AUDIO_LIMIT_STATE="${ROOT}/config/quickshell/awtarchy/AudioLimitState.qml"
BAR_QML="${ROOT}/config/quickshell/awtarchy/Bar.qml"
HYPR_CONFIG="${ROOT}/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
CONTROLLER="${TMP}/hypr-ddc-brightness.sh"
BAR_MODULE="${TMP}/ddc_brightness.sh"

cleanup() {
  local pid_file pid
  pid_file="${TMP}/runtime/hypr-ddc-brightness-$(id -u)/worker_LVDS-1.pid"
  if [[ -r "$pid_file" ]]; then
    IFS= read -r pid <"$pid_file" || true
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
install -m 0755 "$CONTROLLER_SOURCE" "$CONTROLLER"
install -m 0755 "$BAR_MODULE_SOURCE" "$BAR_MODULE"

fakebin="${TMP}/fakebin"
config_home="${TMP}/config"
cache_home="${TMP}/cache"
runtime_dir="${TMP}/runtime"
backlight_root="${TMP}/sys/class/backlight"
backlight_target="${TMP}/sys/devices/pci0000:00/0000:00:02.0/drm/card2/card2-LVDS-1/intel_backlight"
monitor_json="${TMP}/monitors.json"
brightness_state="${TMP}/brightness.state"
brightness_log="${TMP}/brightness.log"
notify_log="${TMP}/notify.log"
ddc_state="${TMP}/ddc.state"
ddc_log="${TMP}/ddc.log"

mkdir -p \
  "$fakebin" \
  "$config_home/hypr" \
  "$cache_home" \
  "$runtime_dir" \
  "$backlight_root" \
  "$backlight_target"
ln -s "$backlight_target" "$backlight_root/intel_backlight"

printf '%s\n' '2458 4710' >"$brightness_state"
printf '%s\n' '40 100' >"$ddc_state"
: >"$brightness_log"
: >"$notify_log"
: >"$ddc_log"

cat >"${fakebin}/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $* == '-j monitors' ]]; then
  cat "${AWTARCHY_TEST_MONITOR_JSON:?}"
  exit 0
fi
exit 2
EOF

cat >"${fakebin}/brightnessctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_BRIGHTNESS_LOG:?}"

device=""
operation=""
value=""
while (( $# )); do
  case "$1" in
    -c|--class|-d|--device)
      [[ "$1" == -d || "$1" == --device ]] && device="${2:-}"
      shift 2
      ;;
    -q|--quiet|-m|--machine-readable)
      shift
      ;;
    info|get|max)
      operation="$1"
      shift
      ;;
    set)
      operation="$1"
      value="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ "$device" == intel_backlight ]] || exit 3
read -r current maximum <"${AWTARCHY_TEST_BRIGHTNESS_STATE:?}"
percent=$(( (current * 100 + maximum / 2) / maximum ))

case "$operation" in
  info)
    printf 'intel_backlight,backlight,%s,%s%%,%s\n' "$current" "$percent" "$maximum"
    ;;
  get)
    printf '%s\n' "$current"
    ;;
  max)
    printf '%s\n' "$maximum"
    ;;
  set)
    [[ "$value" =~ ^[0-9]+%$ ]] || exit 4
    percent="${value%%%}"
    (( percent >= 0 && percent <= 100 )) || exit 5
    current=$(( (maximum * percent + 50) / 100 ))
    printf '%s %s\n' "$current" "$maximum" >"${AWTARCHY_TEST_BRIGHTNESS_STATE:?}"
    ;;
  *)
    exit 6
    ;;
esac
EOF

cat >"${fakebin}/ddcutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_DDC_LOG:?}"
args=("$@")

for index in "${!args[@]}"; do
  case "${args[$index]}" in
    getvcp)
      read -r current maximum <"${AWTARCHY_TEST_DDC_STATE:?}"
      printf 'VCP code 0x10 (Brightness): current value = %s, max value = %s\n' \
        "$current" "$maximum"
      exit 0
      ;;
    setvcp)
      target="${args[$((index + 2))]:-}"
      [[ "$target" =~ ^[0-9]+$ ]] || exit 7
      read -r _current maximum <"${AWTARCHY_TEST_DDC_STATE:?}"
      printf '%s %s\n' "$target" "$maximum" >"${AWTARCHY_TEST_DDC_STATE:?}"
      exit 0
      ;;
  esac
done

exit 8
EOF

cat >"${fakebin}/notify-send" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AWTARCHY_TEST_NOTIFY_LOG:?}"
EOF

chmod 0755 "${fakebin}/"*

write_monitor() {
  local connector="$1" make="$2" model="$3" serial="$4"
  jq -cn \
    --arg connector "$connector" \
    --arg make "$make" \
    --arg model "$model" \
    --arg serial "$serial" \
    '[{
      name:$connector,
      make:$make,
      model:$model,
      serial:$serial,
      description:($make + " " + $model),
      focused:true
    }]' >"$monitor_json"
}

run_controller_mode() {
  local notify_mode="$1" debounce_ms="$2" max_wait_ms="$3"
  shift 3
  env \
    PATH="${fakebin}:$PATH" \
    HOME="$TMP" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$cache_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
    HYPR_DDC_NOTIFY="$notify_mode" \
    HYPR_DDC_DEBOUNCE_MS="$debounce_ms" \
    HYPR_DDC_MAX_WAIT_MS="$max_wait_ms" \
    AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
    AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
    AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
    AWTARCHY_TEST_NOTIFY_LOG="$notify_log" \
    AWTARCHY_TEST_DDC_STATE="$ddc_state" \
    AWTARCHY_TEST_DDC_LOG="$ddc_log" \
    "$CONTROLLER" "$@"
}

run_controller() {
  run_controller_mode 0 10 100 "$@"
}

write_monitor "LVDS-1" "AU Optronics" "0x203E" ""
internal_status="$(run_controller --monitor LVDS-1 status)"
grep -Fxq 'conn=LVDS-1' <<<"$internal_status" || fail "internal connector was not selected"
grep -Fxq 'cur=52' <<<"$internal_status" || fail "internal raw brightness was not normalized"
grep -Fxq 'max=100' <<<"$internal_status" || fail "internal brightness maximum was not normalized"
grep -Fxq 'backend=backlight' <<<"$internal_status" || fail "LVDS did not use the backlight backend"
grep -Fxq 'device=intel_backlight' <<<"$internal_status" || fail "LVDS did not map to intel_backlight"
[[ ! -s "$ddc_log" ]] || fail "internal brightness invoked ddcutil"

bar_json="$(
  env \
    PATH="${fakebin}:$PATH" \
    HOME="$TMP" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$cache_home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    HYPR_BRIGHTNESS_SCRIPT="$CONTROLLER" \
    HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
    HYPR_DDC_NOTIFY=0 \
    AWTARCHY_OUTPUT_NAME=LVDS-1 \
    AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
    AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
    AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
    AWTARCHY_TEST_DDC_STATE="$ddc_state" \
    AWTARCHY_TEST_DDC_LOG="$ddc_log" \
    "$BAR_MODULE" status
)"
[[ $(jq -r '.percentage' <<<"$bar_json") == 52 ]] \
  || fail "bar did not expose internal-panel percentage"
[[ $(jq -r '.tooltip' <<<"$bar_json") != *DDC* ]] \
  || fail "bar still described the internal panel as DDC"

run_controller --monitor LVDS-1 set 40
grep -Fq 'set 40%' "$brightness_log" || fail "internal set did not use a logical percentage"
internal_status="$(run_controller --monitor LVDS-1 status)"
grep -Fxq 'cur=40' <<<"$internal_status" || fail "internal set did not update brightness"

run_controller --monitor LVDS-1 up 5
for _ in {1..100}; do
  IFS=' ' read -r raw maximum <"$brightness_state"
  [[ $raw == 2120 && $maximum == 4710 ]] && break
  sleep 0.05
done
[[ $raw == 2120 && $maximum == 4710 ]] \
  || fail "debounced internal adjustment did not apply five percentage points"

# A bar request must be able to make an already-running, slower keybind worker
# write immediately. Worker timing is batch metadata, not inherited forever from
# whichever input source happened to spawn the worker.
run_controller_mode 1 500 1000 --monitor LVDS-1 up 5
sleep 0.05
run_controller_mode 0 0 500 --monitor LVDS-1 up 5
active_scroll_applied=false
for _ in {1..12}; do
  IFS=' ' read -r raw maximum <"$brightness_state"
  if [[ $raw == 2591 && $maximum == 4710 ]]; then
    active_scroll_applied=true
    break
  fi
  sleep 0.02
done
[[ "$active_scroll_applied" == true ]] \
  || fail "bar brightness request did not lower an existing worker batch to immediate write timing"

# A silent bar-style adjustment followed by a notifying keybind-style adjustment
# can share one worker. Notification intent must be accumulated per batch rather
# than inherited from whichever request happened to create the worker.
: >"$notify_log"
run_controller_mode 0 250 500 --monitor LVDS-1 up 5
sleep 0.05
run_controller_mode 1 250 500 --monitor LVDS-1 up 5
for _ in {1..100}; do
  if grep -Fq 'Brightness LVDS-1' "$notify_log"; then
    break
  fi
  sleep 0.05
done
grep -Fq 'Brightness LVDS-1' "$notify_log" \
  || fail "keybind-style brightness feedback was lost when a silent request started the worker"

: >"$notify_log"
run_controller_mode 0 80 200 --monitor LVDS-1 up 5
sleep 0.4
[[ ! -s "$notify_log" ]] \
  || fail "silent brightness adjustment emitted a routine notification"

# Bar preview should advance immediately per wheel event, independently of the
# hardware worker's delayed DDC/backlight write.
env \
  PATH="${fakebin}:$PATH" \
  HOME="$TMP" \
  XDG_CONFIG_HOME="$config_home" \
  XDG_CACHE_HOME="$cache_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  HYPR_BRIGHTNESS_SCRIPT="$CONTROLLER" \
  HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
  AWTARCHY_OUTPUT_NAME=LVDS-1 \
  AWTARCHY_DDC_SCROLL_DEBOUNCE_MS=1000 \
  AWTARCHY_DDC_SCROLL_MAX_WAIT_MS=2000 \
  AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
  AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
  AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
  AWTARCHY_TEST_NOTIFY_LOG="$notify_log" \
  AWTARCHY_TEST_DDC_STATE="$ddc_state" \
  AWTARCHY_TEST_DDC_LOG="$ddc_log" \
  "$BAR_MODULE" up
preview_file="$cache_home/hypr-ddc-brightness/preview_LVDS-1.tsv"
read -r preview_once preview_max _preview_ts <"$preview_file"
env \
  PATH="${fakebin}:$PATH" \
  HOME="$TMP" \
  XDG_CONFIG_HOME="$config_home" \
  XDG_CACHE_HOME="$cache_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  HYPR_BRIGHTNESS_SCRIPT="$CONTROLLER" \
  HYPR_BACKLIGHT_SYSFS_DIR="$backlight_root" \
  AWTARCHY_OUTPUT_NAME=LVDS-1 \
  AWTARCHY_DDC_SCROLL_DEBOUNCE_MS=1000 \
  AWTARCHY_DDC_SCROLL_MAX_WAIT_MS=2000 \
  AWTARCHY_TEST_MONITOR_JSON="$monitor_json" \
  AWTARCHY_TEST_BRIGHTNESS_STATE="$brightness_state" \
  AWTARCHY_TEST_BRIGHTNESS_LOG="$brightness_log" \
  AWTARCHY_TEST_NOTIFY_LOG="$notify_log" \
  AWTARCHY_TEST_DDC_STATE="$ddc_state" \
  AWTARCHY_TEST_DDC_LOG="$ddc_log" \
  "$BAR_MODULE" up
read -r preview_twice preview_max _preview_ts <"$preview_file"
(( preview_twice == preview_once + 5 )) \
  || fail "bar brightness preview did not advance immediately for consecutive wheel events"
[[ "$preview_max" == 100 ]] \
  || fail "bar brightness preview lost the logical maximum"

state_file="$cache_home/hypr-ddc-brightness/state_LVDS-1.tsv"
settled=false
for _ in {1..100}; do
  if [[ -r "$state_file" ]]; then
    read -r settled_cur _settled_max _settled_ts <"$state_file" || true
    if [[ "${settled_cur:-}" == "$preview_twice" ]]; then
      settled=true
      break
    fi
  fi
  sleep 0.05
done
[[ "$settled" == true ]] \
  || fail "hardware brightness state did not converge to the optimistic bar target"
[[ ! -s "$notify_log" ]] \
  || fail "bar brightness scrolling emitted a routine notification"

edp_target="${TMP}/sys/devices/pci0000:00/0000:00:02.0/drm/card2/card2-eDP-1/intel_backlight"
mkdir -p "$edp_target"
ln -sfn "$edp_target" "$backlight_root/intel_backlight"
write_monitor "eDP-1" "Internal" "Panel" ""
edp_status="$(run_controller --monitor eDP-1 status)"
grep -Fxq 'backend=backlight' <<<"$edp_status" || fail "eDP did not use the backlight backend"
grep -Fxq 'device=intel_backlight' <<<"$edp_status" || fail "eDP did not map to intel_backlight"

printf '%s\n' 'DP-1=7' >"$config_home/hypr/ddcutil-bus-map.conf"
write_monitor "DP-1" "Dell Inc." "U2720Q" "ABC123"
brightness_calls_before="$(wc -l <"$brightness_log")"
external_status="$(run_controller --monitor DP-1 status)"
grep -Fxq 'conn=DP-1' <<<"$external_status" || fail "external connector was not selected"
grep -Fxq 'cur=40' <<<"$external_status" || fail "external DDC brightness changed unexpectedly"
grep -Fxq 'max=100' <<<"$external_status" || fail "external DDC maximum changed unexpectedly"
grep -Fxq 'backend=ddc' <<<"$external_status" || fail "external monitor did not use DDC"
grep -Fxq 'bus=7' <<<"$external_status" || fail "external monitor lost its configured DDC bus"

run_controller --monitor DP-1 set 45
IFS=' ' read -r ddc_current ddc_maximum <"$ddc_state"
[[ $ddc_current == 45 && $ddc_maximum == 100 ]] || fail "external DDC write failed"
[[ $(wc -l <"$brightness_log") == "$brightness_calls_before" ]] \
  || fail "external DDC brightness invoked brightnessctl"
grep -Fq -- '--bus 7' "$ddc_log" || fail "external DDC command did not retain its bus selection"

# Scroll/keybind steps are percentage points, even when the monitor exposes a
# native DDC range other than 0-100.
printf '%s\n' '80 200' >"$ddc_state"
rm -f "$cache_home/hypr-ddc-brightness/state_DP-1.tsv"
external_scaled_status="$(run_controller --monitor DP-1 status)"
grep -Fxq 'cur=80' <<<"$external_scaled_status" || fail "scaled DDC test did not start at raw 80"
grep -Fxq 'max=200' <<<"$external_scaled_status" || fail "scaled DDC test did not expose native max 200"

run_controller --monitor DP-1 set-percent 45
IFS=' ' read -r ddc_current ddc_maximum <"$ddc_state"
[[ $ddc_current == 90 && $ddc_maximum == 200 ]] \
  || fail "cached percentage DDC write did not scale 45 percent to the native range"

run_controller --monitor DP-1 up 5
for _ in {1..100}; do
  IFS=' ' read -r ddc_current ddc_maximum <"$ddc_state"
  [[ $ddc_current == 100 && $ddc_maximum == 200 ]] && break
  sleep 0.05
done
[[ $ddc_current == 100 && $ddc_maximum == 200 ]] \
  || fail "five-point DDC brightness step did not scale against the monitor native range"

grep -Fq 'AWTARCHY_DDC_SCROLL_DEBOUNCE_MS:-0' "$BAR_MODULE_SOURCE" \
  || fail "bar brightness does not request immediate hardware writes while scrolling"
grep -Fq 'debounce_file="$rundir/debounce_${conn}.txt"' "$CONTROLLER_SOURCE" \
  || fail "brightness worker does not track debounce timing per input batch"
grep -Fq 'batch_debounce="$(read_uint_file "$debounce_file" "$DEBOUNCE_MS")"' "$CONTROLLER_SOURCE" \
  || fail "brightness worker does not honor source-aware batch timing"
grep -Fq 'AWTARCHY_DDC_SCROLL_MAX_WAIT_MS:-500' "$BAR_MODULE_SOURCE" \
  || fail "bar brightness still allows long continuous-scroll latency"
grep -Fq 'HYPR_DDC_NOTIFY=0' "$BAR_MODULE_SOURCE" \
  || fail "bar brightness adjustments do not suppress routine notifications"
grep -Fq 'HYPR_DDC_NOTIFY=0 run_quiet "$BRIGHTNESS_SCRIPT"' "$QUICKSETTINGS_CORE" \
  || fail "Quick Settings brightness adjustments do not suppress routine notifications"
grep -Fq 'brightness_quiet set-percent "$percent"' "$QUICKSETTINGS_BACKEND" \
  || fail "Quick Settings brightness drag does not use the cached percentage write path"
grep -Fq 'property int brightnessPreviewPercent: -1' "$QUICK_SETTINGS" \
  || fail "Quick Settings brightness lacks immediate optimistic feedback"
grep -Fq 'property int brightnessRequestedValue: -1' "$BAR_QML" \
  || fail "bar brightness lacks a local optimistic target"
grep -Fq 'brightnessDisplayValue + direction * brightnessStep' "$BAR_QML" \
  || fail "bar brightness does not update the visible value directly from the wheel event"
grep -Fq 'label: bar.brightnessDisplayText' "$BAR_QML" \
  || fail "horizontal bar brightness does not render the immediate optimistic value"
grep -Fq 'bar.brightnessDisplayValue + "%"' "$BAR_QML" \
  || fail "vertical bar brightness does not render the immediate optimistic value"
grep -Fq 'brightnessPreviewPercent = Math.max(0, Math.min(100, base + delta));' "$QUICK_SETTINGS" \
  || fail "Quick Settings +/- brightness does not update its visible target immediately"
grep -Fq 'brightnessPreviewPercent = next;' "$QUICK_SETTINGS" \
  || fail "Quick Settings brightness track does not update its visible target immediately"
grep -Fq 'if (pressed)' "$QUICK_SETTINGS" \
  || fail "Quick Settings tracks do not support held left-button dragging"
grep -Fq 'root.setBrightnessPercent(root.brightnessHoverPercent);' "$QUICK_SETTINGS" \
  || fail "Quick Settings brightness does not adjust continuously while dragging"
grep -Fq 'item.args[0] === "brightness-percent"' "$QUICK_SETTINGS" \
  || fail "Quick Settings brightness drag does not coalesce superseded hardware writes"
grep -Fq 'AudioLimitState.previewLimit(root.outputVolumeHoverPercent);' "$QUICK_SETTINGS" \
  || fail "Quick Settings maximum volume does not preview continuously while dragging"
grep -Fq 'AudioLimitState.setLimit(root.outputVolumeHoverPercent);' "$QUICK_SETTINGS" \
  || fail "Quick Settings maximum volume does not commit the dragged value on release"
grep -Fq 'function previewLimit(value)' "$AUDIO_LIMIT_STATE" \
  || fail "maximum volume state has no lightweight drag preview path"
grep -Fq '[[ "${HYPR_DDC_NOTIFY:-1}" == "0" ]] && return 0' "$CONTROLLER_SOURCE" \
  || fail "brightness controller no longer defaults notifications on for direct calls"
grep -Fq 'hl.bind("SUPER + ALT + equal", hl.dsp.exec_cmd(hypr_ddc_brightness .. " up 5"), {})' "$HYPR_CONFIG" \
  || fail "brightness increase keybind no longer calls the notifying controller directly"
grep -Fq 'hl.bind("SUPER + ALT + minus", hl.dsp.exec_cmd(hypr_ddc_brightness .. " down 5"), {})' "$HYPR_CONFIG" \
  || fail "brightness decrease keybind no longer calls the notifying controller directly"

printf '%s\n' "Hybrid brightness backend tests passed."
