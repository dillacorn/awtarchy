#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/sunshine-moonlight-fix.sh
# 
# Moves Steam Big Picture to workspace 1 on Sunshine connect.
# Works with native Steam or Flatpak Steam. Hyprland + jq required.
# 
# Awtarchy automatically adds this helper to Sunshine's global preparation
# commands during install/update when Sunshine is detected.
# Sunshine service/autostart state is intentionally left unchanged.

set -euo pipefail

# ---- YOUR SESSION ENV ----
# Set these to match your Hyprland session.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Hyprland sets both DISPLAY (Xwayland) and WAYLAND_DISPLAY; pick what you actually use.
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

TARGET_WS="1"
TIMEOUT=30
POLL=0.2
LOGPFX="[Sunshine Connect]"

log(){ printf '%s %s %s\n' "$(date '+%F %T')" "$LOGPFX" "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { log "Missing command: $1"; exit 1; }; }

need hyprctl
need jq

# Launch/open Big Picture in the running Steam, falling back to starting it.
launch_bigpicture() {
  if command -v flatpak >/dev/null 2>&1 && flatpak list --app | grep -q 'com\.valvesoftware\.Steam'; then
    # Flatpak Steam
    log "Opening Big Picture via Flatpak Steam…"
    flatpak run --branch=stable --file-forwarding com.valvesoftware.Steam "steam://open/bigpicture" >/dev/null 2>&1 &
  elif command -v steam >/dev/null 2>&1; then
    # Native Steam
    log "Opening Big Picture via native Steam…"
    steam "steam://open/bigpicture" >/dev/null 2>&1 &
  else
    log "Steam not found (native or Flatpak)."
    exit 1
  fi
}

addr_wrap() {
  local a="${1:-}"
  case "$a" in
    address:0x*|address:0X*) printf '%s\n' "$a" ;;
    0x*|0X*)                  printf 'address:%s\n' "$a" ;;
    *)                        printf 'address:0x%s\n' "$a" ;;
  esac
}

lua_quote() {
  local s="${1:-}"
  s=${s//\\/\\\\}
  s=${s//\'/\\\'}
  printf "'%s'" "$s"
}

# Return ADDR for Big Picture, empty if not found
find_bp_addr() {
  hyprctl clients -j 2>/dev/null \
    | jq -r '.[] | select(.title | test("Steam Big Picture|Big Picture Mode|Big Picture"; "i")) | .address' \
    | head -n1
}

# 1) Ask Steam for Big Picture (this fixes “error -1” by not relying on Sunshine’s internal trigger)
launch_bigpicture

# 2) Poll for the Big Picture window and move it to the target workspace
log "Waiting for Big Picture window…"
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  addr="$(find_bp_addr || true)"
  if [[ -n "${addr:-}" ]]; then
    waddr="$(addr_wrap "$addr")"
    log "Found Big Picture ($waddr). Moving to workspace ${TARGET_WS}…"
    # Move the exact Big Picture window without following it, then focus the target workspace.
    hyprctl dispatch "hl.dsp.window.move({ workspace = $(lua_quote "$TARGET_WS"), follow = false, window = $(lua_quote "$waddr") })" >/dev/null
    sleep 0.1
    hyprctl dispatch "hl.dsp.focus({ workspace = $(lua_quote "$TARGET_WS") })" >/dev/null
    log "Done."
    exit 0
  fi
  if (( $(date +%s) >= deadline )); then
    log "Timed out waiting for Big Picture (${TIMEOUT}s)."
    exit 1
  fi
  sleep "$POLL"
done
