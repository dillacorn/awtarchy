#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/waytrogen_launcher.sh
#
# Heals GSettings schema drift only when the binary CHANGES (by SHA), not when the version string changes.
# Copies the packaged schema XML into the user schema dir and compiles it, then launches preferring that dir.
# No sudo. No network.
#
# Preview/render hardening:
# - one-time cache purge per binary (uses waytrogen --delete-cache if supported)
# - safe GTK renderer/theme/scaling wrapper for waytrogen only
# - optional one-shot dconf reset flag for testing

set -euo pipefail
IFS=$'\n\t'

APP_LOGICAL="waytrogen"                 # logical name for your launch_handler toggle
APP_EXEC="waytrogen"                    # resolved at runtime to waytrogen or waytrogen-bin
LAUNCH_HANDLER="${HOME}/.config/hypr/scripts/launch_handler.sh"

SCHEMA_ID="org.Waytrogen.Waytrogen"
REQUIRED_KEY="hide-changer-options-box"

USR_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/glib-2.0/schemas"
SYS_DIRS=(
  "/usr/share/glib-2.0/schemas"
  "/usr/local/share/glib-2.0/schemas"
)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/waytrogen"
SENTINEL="${STATE_DIR}/last_seen_version"         # legacy name; stores SHA
CACHE_HEAL_SENTINEL="${STATE_DIR}/last_cache_heal_sha"

mkdir -p "$STATE_DIR" "$USR_DIR"

# Defaults (override per-launch if needed)
: "${WAYTROGEN_VERBOSE:=0}"
: "${WAYTROGEN_SAFE_UI:=1}"
: "${WAYTROGEN_SAFE_GTK_RENDERER:=1}"
: "${WAYTROGEN_GSK_RENDERER:=cairo}"
: "${WAYTROGEN_GTK_THEME:=Adwaita:dark}"
: "${WAYTROGEN_GDK_SCALE:=1}"
: "${WAYTROGEN_GDK_DPI_SCALE:=1}"
: "${WAYTROGEN_LAUNCH_STDIO:=0}"
: "${WAYTROGEN_RESET_SCHEMA_ONCE:=0}"
: "${WAYTROGEN_FORCE_CACHE_HEAL:=0}"

log(){ [[ "$WAYTROGEN_VERBOSE" = "1" ]] && printf 'waytrogen-launcher: %s\n' "$*" >&2 || true; }
warn(){ printf 'waytrogen-launcher: %s\n' "$*" >&2; }

notify_err(){
  local msg="$*"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 3 3500 "rgb(ff4444)" "$msg" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a Waytrogen "$msg" || true
  fi
  printf '%s\n' "$msg" >&2
}

resolve_exec(){
  local cand
  for cand in waytrogen waytrogen-bin; do
    if command -v "$cand" >/dev/null 2>&1; then
      APP_EXEC="$cand"
      return 0
    fi
  done
  return 1
}

bin_path(){ command -v "$APP_EXEC" 2>/dev/null || true; }

get_sha(){
  local bin
  bin="$(bin_path)"
  [[ -n "$bin" ]] || { echo ""; return; }
  sha256sum "$bin" 2>/dev/null | awk '{print $1}'
}

get_ver(){
  local bin ver
  bin="$(bin_path)"
  [[ -n "$bin" ]] || { echo "unknown"; return; }

  ver="$("$bin" --version 2>/dev/null || true)"
  if [[ -z "$ver" || "$ver" =~ ^unknown$ ]]; then
    if command -v pacman >/dev/null 2>&1; then
      ver="$(pacman -Qi "$APP_EXEC" 2>/dev/null | awk -F': *' '/^Version/{print $2}')"
    fi
  fi

  echo "${ver:-unknown}"
}

migrate_sentinel_to_sha(){
  # Accept old format "ver:...|sha:HEX" or raw HEX. Write back pure lowercase HEX.
  local old="$1" parsed
  if [[ -z "$old" ]]; then
    echo ""
    return
  fi

  if [[ "$old" =~ ^[0-9a-fA-F]{32,64}$ ]]; then
    printf '%s\n' "$old" | tr 'A-F' 'a-f'
    return
  fi

  parsed="$(sed -n 's/.*sha:\([0-9a-fA-F]\{32,64\}\).*/\1/p' <<<"$old" | head -n1 | tr 'A-F' 'a-f')"
  echo "$parsed"
}

duplicate_installs_detected(){
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Qq waytrogen >/dev/null 2>&1 && pacman -Qq waytrogen-bin >/dev/null 2>&1
}

find_installed_schema(){
  local d p
  for d in "${SYS_DIRS[@]}"; do
    p="${d}/${SCHEMA_ID}.gschema.xml"
    [[ -r "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

schema_dirs_joined(){
  local joined d
  joined="${USR_DIR}"
  for d in "${SYS_DIRS[@]}"; do
    joined="${joined}:$d"
  done
  printf '%s\n' "$joined"
}

have_key(){
  local joined
  joined="$(schema_dirs_joined)"
  GSETTINGS_SCHEMA_DIR="$joined" gsettings list-keys "$SCHEMA_ID" 2>/dev/null | grep -qx "$1"
}

compile_user_if_needed(){
  if compgen -G "${USR_DIR}/*.xml" >/dev/null; then
    glib-compile-schemas "$USR_DIR"
  fi
}

install_user_schema_from_system(){
  local src dst
  src="$(find_installed_schema || true)"
  [[ -n "$src" ]] || return 1

  dst="${USR_DIR}/${SCHEMA_ID}.gschema.xml"
  install -Dm0644 "$src" "$dst"
  compile_user_if_needed
  return 0
}

heal_for_new_binary(){
  log "healing: syncing packaged schema into user dir"
  rm -f "${USR_DIR}/${SCHEMA_ID}.gschema.xml" || true
  if ! install_user_schema_from_system; then
    warn "no system schema XML found to copy; launching with system schema caches only"
  fi
}

app_supports_delete_cache(){
  "$APP_EXEC" --help 2>&1 | grep -q -- '--delete-cache'
}

delete_waytrogen_cache_once_per_sha(){
  local cur_sha="$1" prev_sha
  [[ -n "$cur_sha" ]] || return 0

  prev_sha="$(cat "$CACHE_HEAL_SENTINEL" 2>/dev/null || true)"

  if [[ "$cur_sha" == "$prev_sha" && "$WAYTROGEN_FORCE_CACHE_HEAL" != "1" ]]; then
    return 0
  fi

  if app_supports_delete_cache; then
    log "running cache heal (--delete-cache) for sha=$cur_sha"
    "$APP_EXEC" --delete-cache >/dev/null 2>&1 || true
  else
    log "binary does not support --delete-cache; skipping cache heal"
  fi

  printf '%s\n' "$cur_sha" > "$CACHE_HEAL_SENTINEL"
}

reset_dconf_schema_once_if_requested(){
  [[ "$WAYTROGEN_RESET_SCHEMA_ONCE" = "1" ]] || return 0
  command -v dconf >/dev/null 2>&1 || return 0

  log "resetting dconf schema path /org/Waytrogen/Waytrogen/ (one-shot request)"
  dconf reset -f /org/Waytrogen/Waytrogen/ >/dev/null 2>&1 || true
}

launch(){
  local joined d
  joined="$(schema_dirs_joined)"

  local -a env_cmd
  env_cmd=(env "GSETTINGS_SCHEMA_DIR=$joined")

  # Renderer fallback (GTK4/GPU stack issues)
  if [[ "$WAYTROGEN_SAFE_GTK_RENDERER" = "1" && -z "${GSK_RENDERER:-}" ]]; then
    env_cmd+=("GSK_RENDERER=$WAYTROGEN_GSK_RENDERER")
  fi

  # Safe UI wrapper for this app only (theme/scaling)
  if [[ "$WAYTROGEN_SAFE_UI" = "1" ]]; then
    if [[ -z "${GTK_THEME:-}" ]]; then
      env_cmd+=("GTK_THEME=$WAYTROGEN_GTK_THEME")
    fi
    if [[ -z "${GDK_SCALE:-}" ]]; then
      env_cmd+=("GDK_SCALE=$WAYTROGEN_GDK_SCALE")
    fi
    if [[ -z "${GDK_DPI_SCALE:-}" ]]; then
      env_cmd+=("GDK_DPI_SCALE=$WAYTROGEN_GDK_DPI_SCALE")
    fi
  fi

  if [[ -x "$LAUNCH_HANDLER" ]]; then
    "${env_cmd[@]}" "$LAUNCH_HANDLER" "$APP_LOGICAL" "$APP_EXEC"
  else
    if [[ "$WAYTROGEN_LAUNCH_STDIO" = "1" ]]; then
      "${env_cmd[@]}" "$APP_EXEC" &
    else
      "${env_cmd[@]}" "$APP_EXEC" >/dev/null 2>&1 &
    fi
  fi
}

# Toggle logic specific to Waytrogen windows:
# - If ANY tiled instance exists:
#     * Close all floating Waytrogen windows.
#     * Focus the most recently focused tiled instance.
#     * Never kill tiled Waytrogen.
# - If ONLY floating instances exist:
#     * If the current workspace has a floating Waytrogen:
#         - Close all floating Waytrogen windows.
#         - Do NOT launch a new one (pure toggle off on this workspace).
#     * If the current workspace does NOT have a floating Waytrogen:
#         - Close all floating Waytrogen windows (on other workspaces).
#         - Signal caller to launch a new one on the current workspace.
handle_existing_waytrogen(){
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  local clients filtered has_any active_ws_id
  local has_tiled_any has_float_any has_float_on_cur
  local target_addr

  clients="$(hyprctl -j clients 2>/dev/null || true)"
  [[ -n "${clients:-}" ]] || return 1

  filtered="$(jq -rc '
    [ .[]
      | select(
          ((.class        // "" | ascii_downcase) | contains("waytrogen")) or
          ((.initialClass // "" | ascii_downcase) | contains("waytrogen"))
        )
    ]
  ' <<<"$clients" 2>/dev/null || echo "[]")"

  has_any="$(jq 'length > 0' <<<"$filtered" 2>/dev/null || echo "false")"
  [[ "$has_any" == "true" ]] || return 1

  active_ws_id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // -1' 2>/dev/null || echo "-1")"

  has_tiled_any="$(jq '
    map(select(
      ((.floating // false) | tostring) as $f
      | ($f == "false" or $f == "0")
    )) | length > 0
  ' <<<"$filtered" 2>/dev/null || echo "false")"

  has_float_any="$(jq '
    map(select(
      ((.floating // false) | tostring) as $f
      | ($f == "true" or $f == "1")
    )) | length > 0
  ' <<<"$filtered" 2>/dev/null || echo "false")"

  if [[ "$has_tiled_any" == "true" ]]; then
    if [[ "$has_float_any" == "true" ]]; then
      jq -r '
        map(select(
          ((.floating // false) | tostring) as $f
          | ($f == "true" or $f == "1")
        ))[] | .address
      ' <<<"$filtered" 2>/dev/null \
        | while IFS= read -r addr; do
            [[ -n "$addr" && "$addr" != "null" ]] && \
              hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 || true
          done
    fi

    target_addr="$(jq -r '
      map(select(
        ((.floating // false) | tostring) as $f
        | ($f == "false" or $f == "0")
      ))
      | sort_by(.focusHistoryID // 0)
      | last
      | .address
    ' <<<"$filtered" 2>/dev/null || echo "")"

    if [[ -n "$target_addr" && "$target_addr" != "null" ]]; then
      hyprctl dispatch focuswindow "address:$target_addr" >/dev/null 2>&1 || true
    fi

    return 0
  fi

  if [[ "$has_float_any" != "true" ]]; then
    return 1
  fi

  has_float_on_cur="$(jq --argjson ACTIVE "$active_ws_id" '
    map(select(
      ((.floating // false) | tostring) as $f
      | ($f == "true" or $f == "1")
      and ((.workspace.id // .workspaceID // -1) == $ACTIVE)
    )) | length > 0
  ' <<<"$filtered" 2>/dev/null || echo "false")"

  if [[ "$has_float_on_cur" == "true" ]]; then
    jq -r '
      map(select(
        ((.floating // false) | tostring) as $f
        | ($f == "true" or $f == "1")
      ))[] | .address
    ' <<<"$filtered" 2>/dev/null \
      | while IFS= read -r addr; do
          [[ -n "$addr" && "$addr" != "null" ]] && \
            hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 || true
        done
    return 0
  fi

  jq -r '
    map(select(
      ((.floating // false) | tostring) as $f
      | ($f == "true" or $f == "1")
    ))[] | .address
  ' <<<"$filtered" 2>/dev/null \
    | while IFS= read -r addr; do
        [[ -n "$addr" && "$addr" != "null" ]] && \
          hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 || true
      done

  return 1
}

# ---------- main ----------

if ! resolve_exec; then
  notify_err "waytrogen not installed"
  exit 1
fi

if duplicate_installs_detected; then
  warn "both 'waytrogen' and 'waytrogen-bin' installed; binary/schema skew is likely. Continuing."
fi

# Toggle semantics first:
# - Tiled instance anywhere: close floats, focus tiled, stop.
# - Only floating and on current workspace: close floats, stop.
# - Only floating on other workspaces: close floats, then launch new on current workspace.
if handle_existing_waytrogen; then
  exit 0
fi

cur_sha="$(get_sha)"
[[ -n "$cur_sha" ]] || { notify_err "could not hash waytrogen binary"; exit 1; }

cur_ver="$(get_ver)"
log "binary sha=$cur_sha ver=${cur_ver}"

prev_raw="$(cat "$SENTINEL" 2>/dev/null || true)"
prev_sha="$(migrate_sentinel_to_sha "$prev_raw")"

if [[ -n "$prev_raw" && "$prev_sha" != "$prev_raw" ]]; then
  printf '%s\n' "$prev_sha" > "$SENTINEL"
fi

# Heal schema only when SHA changed.
if [[ "$cur_sha" != "$prev_sha" ]]; then
  log "detected binary change: ${prev_sha:-<none>} -> $cur_sha"
  heal_for_new_binary
  printf '%s\n' "$cur_sha" > "$SENTINEL"
else
  # Cheap sanity: if required key vanished (user cache got poisoned), heal anyway.
  if ! have_key "$REQUIRED_KEY"; then
    log "required key not visible; healing without SHA change"
    heal_for_new_binary
  fi
fi

# Preview/render hardening
delete_waytrogen_cache_once_per_sha "$cur_sha"
reset_dconf_schema_once_if_requested

launch
