#!/usr/bin/env bash
# hypr-ddc-brightness.sh
# Debounced DDC/CI brightness for the focused Hyprland monitor.
#
# Each keypress queues a delta and returns immediately (with notify showing the running total).
# A per-connector worker applies ONE ddcutil update after:
#   - no keypress for DEBOUNCE_MS, OR
#   - MAX_WAIT_MS since the first press in the burst (prevents “never applies while spamming”).
#
# Usage:
#   hypr-ddc-brightness.sh up [step]
#   hypr-ddc-brightness.sh down [step]
#
# Optional: fastest manual map (recommended)
#   ~/.config/hypr/ddcutil-bus-map.conf
#     DP-3=5
#     HDMI-A-1 6
#
# Optional: pin bus (same style as your existing scripts)
#   export DDCUTIL_BUS="--bus=5"   # or "--bus 5"
#
# Tuning:
#   export HYPR_DDC_DEBOUNCE_MS=250
#   export HYPR_DDC_MAX_WAIT_MS=5000

set -euo pipefail

DEBOUNCE_MS="${HYPR_DDC_DEBOUNCE_MS:-350}"
MAX_WAIT_MS="${HYPR_DDC_MAX_WAIT_MS:-5000}"

now_ms() {
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
  else
    echo "$(( $(date +%s) * 1000 ))"
  fi
}

notify() {
  local icon="${1:-1}" ms="${2:-900}" color="${3:-0}" msg="${4:-}"
  hyprctl notify "$icon" "$ms" "$color" "$msg" >/dev/null 2>&1 || true
}

read_int_file() {
  local file="$1" def="${2:-0}" v=""
  if [[ -r "$file" ]]; then
    IFS= read -r v <"$file" || true
  fi
  [[ "$v" =~ ^-?[0-9]+$ ]] || v="$def"
  printf '%s\n' "$v"
}

read_uint_file() {
  local file="$1" def="${2:-0}" v=""
  if [[ -r "$file" ]]; then
    IFS= read -r v <"$file" || true
  fi
  [[ "$v" =~ ^[0-9]+$ ]] || v="$def"
  printf '%s\n' "$v"
}

lock_acquire() {
  local d="$1" i=0
  while ! mkdir "$d" 2>/dev/null; do
    i=$((i+1))
    [[ "$i" -gt 80 ]] && return 1
    sleep 0.02
  done
  return 0
}

lock_release() { rmdir "$1" 2>/dev/null || true; }

parse_vcp_cur_max() {
  local cur max
  cur="$(awk -F'current value = ' 'NF>1{print $2}' | awk -F',' '{print $1}' | tr -dc '0-9')"
  max="$(awk -F'max value = ' 'NF>1{print $2}' | awk -F',' '{print $1}' | tr -dc '0-9')"
  [[ -n "${max:-}" ]] || max="100"
  echo "${cur:-} ${max:-}"
}

get_focused_monitor_tsv() {
  hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused==true or .focused=="yes") |
    [(.name//""),(.make//""),(.model//""),(.serial//""),(.description//"")] | @tsv
  ' | head -n1
}

# ---------- args ----------
if [[ "${1:-}" == "--worker" ]]; then
  MODE="worker"
  WORKER_CONN="${2:-}"
  [[ -n "${WORKER_CONN:-}" ]] || exit 1
else
  MODE="client"
  dir="${1:-}"
  step="${2:-5}"
  [[ "$dir" == "up" || "$dir" == "down" ]] || { echo "usage: $0 up|down [step]" >&2; exit 2; }
  [[ "$step" =~ ^[0-9]+$ ]] || { echo "step must be integer" >&2; exit 2; }
fi

# ---------- paths ----------
uid="$(id -u)"
rundir="${XDG_RUNTIME_DIR:-/tmp}/hypr-ddc-brightness-${uid}"
cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-ddc-brightness"
config_map="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/ddcutil-bus-map.conf"
mkdir -p "$rundir" "$cachedir"

# ---------- mapping ----------
bus_from_config_map() {
  local conn="$1"
  [[ -f "$config_map" ]] || return 1
  awk -v c="$conn" '
    BEGIN{FS="[= \t]+"}
    $1==c && $2 ~ /^[0-9]+$/ { print $2; exit }
  ' "$config_map" 2>/dev/null | head -n1
}

bus_from_cache() {
  local conn="$1"
  local cache_tsv="$cachedir/busmap.tsv"
  [[ -f "$cache_tsv" ]] || return 1
  local now bus
  now="$(date +%s)"
  bus="$(
    awk -v c="$conn" -v now="$now" '
      $1==c && (now-$3) < 604800 { print $2; exit }
    ' "$cache_tsv" 2>/dev/null || true
  )"
  [[ -n "${bus:-}" ]] || return 1
  echo "$bus"
}

# Map by EDID-ish fields from ddcutil detect --verbose (no DRM connector dependency).
# Output: best bus number or nothing.
bus_from_detect_by_identity() {
  local conn="$1" hypr_make="$2" hypr_model="$3" hypr_serial="$4" hypr_desc="$5"
  local hypr_make_u hypr_model_u hypr_serial_u hypr_desc_u
  hypr_make_u="$(printf '%s' "$hypr_make" | tr '[:lower:]' '[:upper:]')"
  hypr_model_u="$(printf '%s' "$hypr_model" | tr '[:lower:]' '[:upper:]')"
  hypr_serial_u="$(printf '%s' "$hypr_serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
  hypr_desc_u="$(printf '%s' "$hypr_desc" | tr '[:lower:]' '[:upper:]')"

  local best_bus="" best_score=-1

  while IFS=$'\t' read -r bus mfg model serial; do
    [[ -n "${bus:-}" ]] || continue

    local mfg_u model_u serial_u score=0
    mfg_u="$(printf '%s' "$mfg" | tr '[:lower:]' '[:upper:]')"
    model_u="$(printf '%s' "$model" | tr '[:lower:]' '[:upper:]')"
    serial_u="$(printf '%s' "$serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"

    # serial exact (best)
    if [[ -n "$hypr_serial_u" && -n "$serial_u" && "$hypr_serial_u" == "$serial_u" ]]; then
      score=$((score + 1000))
    fi

    # model match / contains
    if [[ -n "$hypr_model_u" && -n "$model_u" ]]; then
      if [[ "$model_u" == "$hypr_model_u" || "$model_u" == *"$hypr_model_u"* || "$hypr_model_u" == *"$model_u"* ]]; then
        score=$((score + 250))
      fi
    fi

    # description contains model
    if [[ -n "$hypr_desc_u" && -n "$model_u" && "$hypr_desc_u" == *"$model_u"* ]]; then
      score=$((score + 150))
    fi

    # vendor match / contains
    if [[ -n "$hypr_make_u" && -n "$mfg_u" ]]; then
      if [[ "$hypr_make_u" == "$mfg_u" || "$hypr_make_u" == *"$mfg_u"* || "$mfg_u" == *"$hypr_make_u"* ]]; then
        score=$((score + 80))
      fi
    fi

    if (( score > best_score )); then
      best_score="$score"
      best_bus="$bus"
    fi
  done < <(
    timeout 3 ddcutil detect --verbose 2>/dev/null | awk '
      function flush() {
        if (bus != "") print bus "\t" mfg "\t" model "\t" serial
        bus=""; mfg=""; model=""; serial=""
      }
      /^Display[[:space:]]+[0-9]+/ { flush(); next }
      /I2C bus:/ { if (match($0, /\/dev\/i2c-([0-9]+)/, m)) bus=m[1]; next }
      /Mfg id:/ { s=$0; sub(/^.*Mfg id:[[:space:]]*/, "", s); mfg=s; next }
      /^ *Model:/ { s=$0; sub(/^.*Model:[[:space:]]*/, "", s); model=s; next }
      /Serial number:/ { s=$0; sub(/^.*Serial number:[[:space:]]*/, "", s); serial=s; next }
      END { flush() }
    '
  )

  [[ -n "${best_bus:-}" && "$best_score" -ge 180 ]] || return 1

  # cache (TTL 7d)
  local cache_tsv="$cachedir/busmap.tsv" epoch tmp
  epoch="$(date +%s)"
  tmp="${cache_tsv}.tmp.$$"
  { [[ -f "$cache_tsv" ]] && awk -v c="$conn" '$1!=c' "$cache_tsv" || true; } >"$tmp"
  printf '%s\t%s\t%s\n' "$conn" "$best_bus" "$epoch" >>"$tmp"
  mv -f "$tmp" "$cache_tsv"

  echo "$best_bus"
}

get_bus_for_focused() {
  local conn="$1" hypr_make="$2" hypr_model="$3" hypr_serial="$4" hypr_desc="$5"
  local bus=""

  bus="$(bus_from_config_map "$conn" || true)"
  [[ -n "${bus:-}" ]] && { echo "$bus"; return 0; }

  bus="$(bus_from_cache "$conn" || true)"
  [[ -n "${bus:-}" ]] && { echo "$bus"; return 0; }

  bus_from_detect_by_identity "$conn" "$hypr_make" "$hypr_model" "$hypr_serial" "$hypr_desc"
}

build_ddc_array() {
  local bus="$1"
  local -n _out="$2"
  local -a extra
  _out=(ddcutil)

  if [[ -n "${DDCUTIL_BUS:-}" ]]; then
    read -r -a extra <<<"$DDCUTIL_BUS"
    _out+=("${extra[@]}")
  else
    _out+=(--bus "$bus")
  fi
}

# ---------- client ----------
if [[ "$MODE" == "client" ]]; then
  focused="$(get_focused_monitor_tsv || true)"
  [[ -n "${focused:-}" ]] || { echo "hypr-ddc-brightness: no focused monitor" >&2; exit 1; }
  IFS=$'\t' read -r conn _make _model _serial _desc <<<"$focused"

  sign=1
  [[ "$dir" == "down" ]] && sign=-1
  delta=$((sign * step))

  pending_file="$rundir/pending_${conn}.txt"
  last_file="$rundir/last_${conn}.txt"
  first_file="$rundir/first_${conn}.txt"
  pid_file="$rundir/worker_${conn}.pid"
  lock_dir="$rundir/lock_${conn}.d"

  lock_acquire "$lock_dir" || { echo "hypr-ddc-brightness: lock timeout" >&2; exit 1; }

  old_pending="$(read_int_file "$pending_file" 0)"
  new_pending=$((old_pending + delta))

  printf '%s\n' "$new_pending" >"$pending_file"
  printf '%s\n' "$(now_ms)" >"$last_file"
  if [[ "$old_pending" == "0" ]]; then
    printf '%s\n' "$(now_ms)" >"$first_file"
  fi

  lock_release "$lock_dir"

  # immediate feedback per press
  if (( new_pending >= 0 )); then
    notify 1 650 0 "Brightness ${conn}: ${delta} (total +${new_pending})"
  else
    notify 1 650 0 "Brightness ${conn}: ${delta} (total ${new_pending})"
  fi

  if [[ -f "$pid_file" ]]; then
    wp="$(read_uint_file "$pid_file" 0)"
    if [[ "$wp" -gt 1 ]] && kill -0 "$wp" 2>/dev/null; then
      exit 0
    fi
  fi

  script_self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  nohup "$script_self" --worker "$conn" >/dev/null 2>&1 &
  exit 0
fi

# ---------- worker ----------
conn="$WORKER_CONN"
pending_file="$rundir/pending_${conn}.txt"
last_file="$rundir/last_${conn}.txt"
first_file="$rundir/first_${conn}.txt"
pid_file="$rundir/worker_${conn}.pid"
lock_dir="$rundir/lock_${conn}.d"

printf '%s\n' "$$" >"$pid_file"

idle_loops=0

while :; do
  while :; do
    sleep 0.08
    now="$(now_ms)"
    last="$(read_uint_file "$last_file" 0)"
    first="$(read_uint_file "$first_file" 0)"

    idle_age=$((now - last))
    elapsed=$(( first > 0 ? now - first : 0 ))

    if (( idle_age >= DEBOUNCE_MS )); then break; fi
    if (( first > 0 && elapsed >= MAX_WAIT_MS )); then break; fi
  done

  lock_acquire "$lock_dir" || exit 0
  pending="$(read_int_file "$pending_file" 0)"
  printf '0\n' >"$pending_file"
  printf '0\n' >"$first_file"
  lock_release "$lock_dir"

  if [[ "$pending" == "0" ]]; then
    idle_loops=$((idle_loops + 1))
    (( idle_loops >= 6 )) && exit 0
    sleep 0.05
    continue
  fi
  idle_loops=0

  # capture identity for mapping
  focused="$(get_focused_monitor_tsv || true)"
  hypr_make="" hypr_model="" hypr_serial="" hypr_desc=""
  if [[ -n "${focused:-}" ]]; then
    IFS=$'\t' read -r _conn hypr_make hypr_model hypr_serial hypr_desc <<<"$focused"
  fi

  bus="$(get_bus_for_focused "$conn" "$hypr_make" "$hypr_model" "$hypr_serial" "$hypr_desc" || true)"
  if [[ -z "${bus:-}" ]]; then
    notify 3 1600 0 "Brightness ${conn}: no DDC bus (map ${conn}=N in ${config_map})"
    continue
  fi

  declare -a ddc
  build_ddc_array "$bus" ddc

  vcp="$(timeout 2 "${ddc[@]}" getvcp 0x10 2>/dev/null || true)"
  read -r cur max < <(printf '%s\n' "$vcp" | parse_vcp_cur_max)
  if [[ -z "${cur:-}" ]]; then
    notify 3 1600 0 "Brightness ${conn}: getvcp failed (bus ${bus})"
    continue
  fi

  # Adaptive gain to compensate “requested 5, effective 3” monitors.
  desired_abs="${pending#-}"
  desired_abs="${desired_abs:-0}"

  gain_file="$cachedir/gain_bus${bus}.milli"
  gain_milli="$(read_uint_file "$gain_file" 1000)"
  [[ "$gain_milli" -ge 200 && "$gain_milli" -le 5000 ]] || gain_milli=1000

  send_abs=$(( (desired_abs * gain_milli + 500) / 1000 ))
  (( send_abs < 1 )) && send_abs=1

  sign=1
  (( pending < 0 )) && sign=-1

  target=$((cur + sign * send_abs))
  (( target < 0 )) && target=0
  (( target > max )) && target="$max"

  if ! timeout 3 "${ddc[@]}" setvcp 0x10 "$target" >/dev/null 2>&1; then
    sleep 0.25
    timeout 3 "${ddc[@]}" setvcp 0x10 "$target" >/dev/null 2>&1 || true
  fi

  vcp2="$(timeout 2 "${ddc[@]}" getvcp 0x10 2>/dev/null || true)"
  read -r cur2 _max2 < <(printf '%s\n' "$vcp2" | parse_vcp_cur_max)
  [[ -n "${cur2:-}" ]] || cur2="$target"

  eff_abs=$(( cur2 > cur ? cur2 - cur : cur - cur2 ))

  if (( desired_abs > 0 && eff_abs > 0 )); then
    computed=$(( gain_milli * desired_abs / eff_abs ))
    (( computed < 200 )) && computed=200
    (( computed > 5000 )) && computed=5000
    gain_milli=$(( (gain_milli + computed) / 2 ))
    printf '%s\n' "$gain_milli" >"$gain_file"
  fi

  sent_disp=$((sign * send_abs))
  notify 1 1400 0 "Brightness ${conn}: req ${pending}, sent ${sent_disp}, eff ${eff_abs}, now ${cur2} (bus ${bus}, gain ${gain_milli}‰)"
done
