#!/usr/bin/env bash
# hypr-ddc-brightness.sh
# Adjust DDC/CI brightness on the currently focused Hyprland monitor.
#
# Usage:
#   ./hypr-ddc-brightness.sh up [step]
#   ./hypr-ddc-brightness.sh down [step]
#
# Optional override (pins a specific monitor):
#   export DDCUTIL_BUS="--bus=5"   # or "--bus=6", etc
#
# Notes:
# - This does NOT rely on ddcutil relative +/-. It reads current, applies step, clamps, sets absolute.
# - Auto-mapping prefers EDID serial match, then model+vendor, then connector name.

set -euo pipefail

usage() { echo "usage: $(basename "$0") up|down [step]" >&2; exit 2; }

dir="${1:-}"; step="${2:-5}"
[[ "$dir" == "up" || "$dir" == "down" ]] || usage
[[ "$step" =~ ^[0-9]+$ ]] || usage

# If user pins a bus, just use it (matches your existing scripts pattern)
if [[ -n "${DDCUTIL_BUS:-}" ]]; then
  bus_arg="$DDCUTIL_BUS"
else
  bus_arg=""
fi

# focused monitor info from Hyprland
read -r hypr_name hypr_make hypr_model hypr_serial hypr_desc < <(
  hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused==true or .focused=="yes") |
    [
      (.name // ""),
      (.make // ""),
      (.model // ""),
      (.serial // ""),
      (.description // "")
    ] | @tsv
  ' | head -n1 | tr '\t' ' '
)

[[ -n "${hypr_name:-}" && "$hypr_name" != "null" ]] || {
  echo "hypr-ddc-brightness: could not determine focused monitor (hyprctl)" >&2
  exit 1
}

norm() {
  # upper, collapse to alnum+spaces
  tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/ /g; s/^ +| +$//g; s/ +/ /g'
}

hypr_name_n="$(printf '%s' "$hypr_name" | norm)"
hypr_make_n="$(printf '%s' "$hypr_make" | norm)"
hypr_model_n="$(printf '%s' "$hypr_model" | norm)"
hypr_serial_n="$(printf '%s' "$hypr_serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
hypr_desc_n="$(printf '%s' "$hypr_desc" | norm)"

pick_bus_for_focused() {
  # Parse ddcutil detect --verbose into TSV records:
  # bus<TAB>drm_connector<TAB>mfg<TAB>model<TAB>serial
  ddcutil detect --verbose 2>/dev/null | awk '
    function flush() {
      if (bus != "") {
        print bus "\t" conn "\t" mfg "\t" model "\t" serial
      }
      bus=""; conn=""; mfg=""; model=""; serial=""
    }

    /^Display[[:space:]]+[0-9]+/ { flush(); next }

    /I2C bus:/ {
      if (match($0, /\/dev\/i2c-([0-9]+)/, m)) bus=m[1]
      next
    }

    /DRM connector:/ {
      s=$0
      sub(/^.*DRM connector:[[:space:]]*/, "", s)   # e.g. card0-DP-3 or card1-DP-3-1
      conn=s
      next
    }

    /Mfg id:/ {
      s=$0
      sub(/^.*Mfg id:[[:space:]]*/, "", s)
      mfg=s
      next
    }

    /^ *Model:/ {
      s=$0
      sub(/^.*Model:[[:space:]]*/, "", s)
      model=s
      next
    }

    /Serial number:/ {
      s=$0
      sub(/^.*Serial number:[[:space:]]*/, "", s)
      serial=s
      next
    }

    END { flush() }
  '
}

if [[ -z "${bus_arg:-}" ]]; then
  best_bus=""
  best_score="-1"

  while IFS=$'\t' read -r bus conn mfg model serial; do
    [[ -n "${bus:-}" ]] || continue

    conn_n="$(printf '%s' "$conn" | norm)"
    mfg_n="$(printf '%s' "$mfg" | norm)"
    model_n="$(printf '%s' "$model" | norm)"
    serial_n="$(printf '%s' "$serial" | tr -dc 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"

    score=0

    # serial match (strongest)
    if [[ -n "$hypr_serial_n" && -n "$serial_n" && "$hypr_serial_n" == "$serial_n" ]]; then
      score=$((score + 1000))
    fi

    # vendor/make match (often 3-letter EDID code or brand)
    if [[ -n "$hypr_make_n" && -n "$mfg_n" ]]; then
      if [[ "$mfg_n" == "$hypr_make_n" ]] || [[ "$hypr_make_n" == *"$mfg_n"* ]] || [[ "$mfg_n" == *"$hypr_make_n"* ]]; then
        score=$((score + 80))
      fi
    fi

    # model match
    if [[ -n "$hypr_model_n" && -n "$model_n" ]]; then
      if [[ "$model_n" == "$hypr_model_n" ]] || [[ "$model_n" == *"$hypr_model_n"* ]] || [[ "$hypr_model_n" == *"$model_n"* ]]; then
        score=$((score + 120))
      fi
    fi

    # description match fallback
    if [[ "$score" -lt 200 && -n "$hypr_desc_n" && -n "$model_n" ]]; then
      if [[ "$hypr_desc_n" == *"$model_n"* ]] || [[ "$model_n" == *"$hypr_desc_n"* ]]; then
        score=$((score + 60))
      fi
    fi

    # connector match (handles MST variants: DP-3, DP-3-1, etc)
    if [[ -n "$conn_n" && -n "$hypr_name_n" ]]; then
      if [[ "$conn_n" == *"$hypr_name_n"* ]]; then
        score=$((score + 50))
      fi
    fi

    if [[ "$score" -gt "$best_score" ]]; then
      best_score="$score"
      best_bus="$bus"
    fi
  done < <(pick_bus_for_focused)

  [[ -n "${best_bus:-}" && "$best_score" -ge 50 ]] || {
    echo "hypr-ddc-brightness: could not map focused '$hypr_name' to a ddcutil bus. Try pinning DDCUTIL_BUS=\"--bus=N\"." >&2
    exit 1
  }

  bus_arg="--bus=${best_bus}"
fi

# Read current + max brightness
vcp_out="$(timeout 2 ddcutil ${bus_arg:+$bus_arg} getvcp 0x10 2>/dev/null || true)"
cur="$(printf '%s\n' "$vcp_out" | awk -F'current value = ' 'NF>1{print $2}' | awk -F',' '{print $1}' | tr -dc '0-9')"
max="$(printf '%s\n' "$vcp_out" | awk -F'max value = ' 'NF>1{print $2}' | awk -F',' '{print $1}' | tr -dc '0-9')"

[[ -n "${cur:-}" ]] || { echo "hypr-ddc-brightness: failed to read current brightness (getvcp 0x10)" >&2; exit 1; }
[[ -n "${max:-}" ]] || max="100"

new="$cur"
if [[ "$dir" == "up" ]]; then
  new=$((cur + step))
else
  new=$((cur - step))
fi

# clamp
if (( new < 0 )); then new=0; fi
if (( new > max )); then new="$max"; fi

# set with one retry
if ! timeout 3 ddcutil ${bus_arg:+$bus_arg} setvcp 0x10 "$new" >/dev/null 2>&1; then
  sleep 0.35
  timeout 3 ddcutil ${bus_arg:+$bus_arg} setvcp 0x10 "$new" >/dev/null 2>&1 || true
fi
