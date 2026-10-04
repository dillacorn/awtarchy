#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_DIR="$CACHE_HOME/awtarchy"
LOG_FILE="$LOG_DIR/hypr-lua-issues-runtime-$(date +%Y%m%d-%H%M%S).log"

VIBRANCE="$CONFIG_HOME/hypr/scripts/vibrance_shader.sh"
WORKSPACE_MIX="$CONFIG_HOME/hypr/scripts/workspace_mix.sh"
ZOOM="$CONFIG_HOME/hypr/scripts/zoom.sh"
SUNSHINE="$CONFIG_HOME/hypr/scripts/sunshine-moonlight-fix.sh"
RESIZE="$CONFIG_HOME/hypr/scripts/toggle_resize_if_ok.sh"

failures=0

mkdir -p -- "$LOG_DIR"

say() {
    printf '%s\n' "$*"
}

pass() {
    say "RESULT $1 PASS: $2"
}

fail() {
    failures=$((failures + 1))
    say "RESULT $1 FAIL: $2"
}

need() {
    command -v "$1" >/dev/null 2>&1
}

lua_quote() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\'/\\\'}
    printf "'%s'" "$s"
}

file_has() {
    local file="$1" needle="$2"
    [[ -f "$file" ]] && grep -Fq -- "$needle" "$file"
}

file_lacks() {
    local file="$1" needle="$2"
    [[ -f "$file" ]] && ! grep -Fq -- "$needle" "$file"
}

bool_option() {
    local option="$1"
    hyprctl -j getoption "$option" 2>/dev/null | jq -r '
        if .bool? != null then (if .bool then "true" else "false" end)
        elif .int? != null then (if .int == 1 then "true" else "false" end)
        elif .value? != null then
            if (.value == true or .value == 1 or .value == "1" or .value == "true") then "true" else "false" end
        else empty
        end
    '
}

run_checks() {
    say "Awtarchy Hyprland Lua runtime validation"
    say "Timestamp: $(date --iso-8601=seconds)"
    say "Log: $LOG_FILE"
    say

    if ! need hyprctl || ! need jq; then
        fail "#258-#263" "hyprctl and jq are required in the active Hyprland session"
        return
    fi

    say "== Hyprland =="
    hyprctl version 2>&1 || true
    hyprctl status 2>&1 || true
    say

    if file_has "$VIBRANCE" 'hyprctl eval "hl.config({ decoration' \
        && file_lacks "$VIBRANCE" 'hyprctl keyword' \
        && file_lacks "$VIBRANCE" 'hyprland.conf' \
        && hyprctl eval 'hl.config({ decoration = { screen_shader = hl.get_config("decoration.screen_shader") } })' >/dev/null 2>&1; then
        pass "#258" "vibrance helper is Lua-only and the live hl.config eval path is accepted"
    else
        fail "#258" "vibrance Lua runtime path or installed helper contract failed"
    fi

    local use_active preserve
    use_active="$(bool_option 'dwindle.use_active_for_splits' || true)"
    preserve="$(bool_option 'dwindle.preserve_split' || true)"
    if file_has "$WORKSPACE_MIX" 'hyprctl eval "hl.config({ dwindle' \
        && file_lacks "$WORKSPACE_MIX" 'hyprctl keyword' \
        && [[ "$use_active" == "true" || "$use_active" == "false" ]] \
        && [[ "$preserve" == "true" || "$preserve" == "false" ]] \
        && hyprctl eval "hl.config({ dwindle = { use_active_for_splits = $use_active, preserve_split = $preserve } })" >/dev/null 2>&1 \
        && [[ "$(bool_option 'dwindle.use_active_for_splits' || true)" == "$use_active" ]] \
        && [[ "$(bool_option 'dwindle.preserve_split' || true)" == "$preserve" ]]; then
        pass "#259" "workspace-mix Lua option writes are accepted and idempotent readback matches"
    else
        fail "#259" "workspace-mix Lua option write/readback validation failed"
    fi

    local before factor rigid after_factor after_rigid rigid_action
    before="$("$ZOOM" status:json 2>/dev/null || true)"
    factor="$(jq -r '.zoom_factor // empty' <<<"$before" 2>/dev/null || true)"
    rigid="$(jq -r '.zoom_rigid // empty' <<<"$before" 2>/dev/null || true)"
    if [[ -n "$factor" && ( "$rigid" == "true" || "$rigid" == "false" ) ]]; then
        if [[ "$rigid" == "true" ]]; then rigid_action="rigid:on"; else rigid_action="rigid:off"; fi
        NOTIFY_ENABLED=false LOG_ENABLE=false "$ZOOM" "set:$factor" >/dev/null 2>&1 || true
        NOTIFY_ENABLED=false LOG_ENABLE=false "$ZOOM" "$rigid_action" >/dev/null 2>&1 || true
        after="$("$ZOOM" status:json 2>/dev/null || true)"
        after_factor="$(jq -r '.zoom_factor // empty' <<<"$after" 2>/dev/null || true)"
        after_rigid="$(jq -r '.zoom_rigid // empty' <<<"$after" 2>/dev/null || true)"
        if file_has "$ZOOM" '"$HC" -q eval "$expr"' \
            && file_lacks "$ZOOM" ' -q keyword ' \
            && awk -v a="$factor" -v b="$after_factor" 'BEGIN { d=a-b; if (d<0) d=-d; exit !(d < 0.0001) }' \
            && [[ "$after_rigid" == "$rigid" ]]; then
            pass "#260" "zoom factor/rigid Lua setters preserved the live values and read back correctly"
        else
            fail "#260" "zoom Lua setter/readback validation failed"
        fi
    else
        fail "#260" "could not read current zoom factor/rigid state"
    fi

    if file_has "$SUNSHINE" 'hl.dsp.window.move({ workspace = $(lua_quote "$TARGET_WS"), follow = false, window = $(lua_quote "$waddr") })' \
        && file_has "$SUNSHINE" 'hl.dsp.focus({ workspace = $(lua_quote "$TARGET_WS") })' \
        && file_lacks "$SUNSHINE" 'dispatch movetoworkspacesilent' \
        && file_lacks "$SUNSHINE" 'dispatch focuswindow' \
        && hyprctl eval 'local _ = hl.dsp.window.move({ workspace = "1", follow = false, window = "address:0x0" })' >/dev/null 2>&1 \
        && hyprctl eval 'local _ = hl.dsp.focus({ workspace = "1" })' >/dev/null 2>&1; then
        pass "#261" "Sunshine helper uses exact-window Lua dispatchers and Hyprland accepts their constructors"
    else
        fail "#261" "Sunshine Lua dispatcher contract/runtime constructor validation failed"
    fi
    say "MANUAL #261 YES: before closure, run one real Sunshine/Moonlight connection and confirm Steam Big Picture moves to workspace 1 without an unintended workspace flicker."
    say

    if file_has "$RESIZE" 'hyprctl dispatch '\''hl.dsp.submap("resize")'\''' \
        && file_has "$RESIZE" 'hyprctl dispatch '\''hl.dsp.submap("reset")'\''' \
        && file_lacks "$RESIZE" 'hyprctl dispatch submap ' \
        && hyprctl eval 'local _ = hl.dsp.submap("resize")' >/dev/null 2>&1 \
        && hyprctl eval 'local _ = hl.dsp.submap("reset")' >/dev/null 2>&1; then
        pass "#262" "resize helper uses Lua-native submap dispatchers and Hyprland accepts them"
    else
        fail "#262" "resize Lua submap contract/runtime constructor validation failed"
    fi

    local monitor_json monitor_name width height refresh x y scale mode position monitor_expr
    monitor_json="$(hyprctl -j monitors 2>/dev/null | jq -c '([.[] | select(.focused == true)][0] // .[0])' 2>/dev/null || true)"
    monitor_name="$(jq -r '.name // empty' <<<"$monitor_json" 2>/dev/null || true)"
    width="$(jq -r '.width // empty' <<<"$monitor_json" 2>/dev/null || true)"
    height="$(jq -r '.height // empty' <<<"$monitor_json" 2>/dev/null || true)"
    refresh="$(jq -r '.refreshRate // empty' <<<"$monitor_json" 2>/dev/null || true)"
    x="$(jq -r '.x // empty' <<<"$monitor_json" 2>/dev/null || true)"
    y="$(jq -r '.y // empty' <<<"$monitor_json" 2>/dev/null || true)"
    scale="$(jq -r '.scale // empty' <<<"$monitor_json" 2>/dev/null || true)"
    if [[ -n "$monitor_name" && -n "$width" && -n "$height" && -n "$refresh" && -n "$x" && -n "$y" && -n "$scale" ]]; then
        mode="${width}x${height}@${refresh}"
        position="${x}x${y}"
        monitor_expr="hl.monitor({ output = $(lua_quote "$monitor_name"), mode = $(lua_quote "$mode"), position = $(lua_quote "$position"), scale = $scale })"
        if hyprctl eval "$monitor_expr" >/dev/null 2>&1; then
            pass "#263" "hl.monitor runtime syntax was accepted while reapplying the focused monitor's current mode"
        else
            fail "#263" "current-mode hl.monitor runtime evaluation failed"
        fi
    else
        fail "#263" "could not read focused monitor geometry for a safe no-op hl.monitor check"
    fi
    say "MANUAL #263 YES: before closure, verify one documented temporary game resolution actually switches modes and restores the native mode when the game exits."
    say

    if (( failures == 0 )); then
        say "AUTOMATED SUMMARY: PASS (#258, #259, #260, #261 command path, #262, #263 command path)"
    else
        say "AUTOMATED SUMMARY: FAIL ($failures issue check(s) failed)"
    fi
    say "MANUAL SUMMARY: #261 and #263 still require the two real-world confirmations printed above."
}

run_checks 2>&1 | tee "$LOG_FILE"
status=${PIPESTATUS[0]}
say "Saved log: $LOG_FILE" | tee -a "$LOG_FILE"
if (( status != 0 || failures != 0 )); then
    exit 1
fi
