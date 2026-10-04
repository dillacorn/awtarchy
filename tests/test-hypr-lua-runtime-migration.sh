#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VIBRANCE="$ROOT/config/hypr/scripts/vibrance_shader.sh"
WORKSPACE_MIX="$ROOT/config/hypr/scripts/workspace_mix.sh"
ZOOM="$ROOT/config/hypr/scripts/zoom.sh"
SUNSHINE="$ROOT/config/hypr/scripts/sunshine-moonlight-fix.sh"
RESIZE="$ROOT/config/hypr/scripts/toggle_resize_if_ok.sh"
STEAM_NOTES="$ROOT/extra_notes/Steam_Launch_Options_Wayland_Hyprland.md"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

reject_text() {
    local file="$1" needle="$2" message="$3"
    if grep -Fq -- "$needle" "$file"; then
        fail "$message"
    fi
}

for file in "$VIBRANCE" "$WORKSPACE_MIX" "$ZOOM" "$SUNSHINE" "$RESIZE" "$STEAM_NOTES"; do
    [[ -f "$file" ]] || fail "missing target: $file"
done

# #258: vibrance is Lua-only and live changes use hl.config() through eval.
reject_text "$VIBRANCE" 'hyprland.conf' '#258 vibrance helper still references legacy hyprland.conf'
reject_text "$VIBRANCE" 'hyprctl keyword' '#258 vibrance helper still uses hyprctl keyword'
require_text "$VIBRANCE" "hyprctl eval \"hl.config({ decoration = { screen_shader = \$(lua_quote \"\$SHADER\") } })\"" '#258 live vibrance enable is not Lua-native'
require_text "$VIBRANCE" "screen_shader = ''" '#258 live vibrance disable is not Lua-native'

# #259: temporary dwindle changes and restoration must use Lua runtime config.
reject_text "$WORKSPACE_MIX" 'hyprctl keyword' '#259 workspace mix still uses hyprctl keyword'
require_text "$WORKSPACE_MIX" "hyprctl eval \"hl.config({ dwindle = { \${key} = \${lua_value} } })\"" '#259 workspace mix does not use Lua runtime config'
require_text "$WORKSPACE_MIX" 'dwindle.use_active_for_splits) key="use_active_for_splits"' '#259 use_active_for_splits mapping is missing'
require_text "$WORKSPACE_MIX" 'dwindle.preserve_split) key="preserve_split"' '#259 preserve_split mapping is missing'
require_text "$WORKSPACE_MIX" 'action="enable"' '#259 workspace mix does not explicitly enable saved float/pseudo state'
require_text "$WORKSPACE_MIX" 'action="disable"' '#259 workspace mix does not explicitly disable saved float/pseudo state'
reject_text "$WORKSPACE_MIX" 'action="set"' '#259 workspace mix still uses non-idempotent set action for toggle-style dispatchers'
reject_text "$WORKSPACE_MIX" 'action="unset"' '#259 workspace mix still uses non-idempotent unset action for toggle-style dispatchers'

# #260: zoom setters must use hl.config() through eval, retaining key detection.
reject_text "$ZOOM" ' keyword ' '#260 zoom helper still uses a keyword setter'
require_text "$ZOOM" "expr=\"hl.config({ cursor = { zoom_factor = \${value} } })\"" '#260 cursor zoom factor Lua setter is missing'
require_text "$ZOOM" "expr=\"hl.config({ cursor = { zoom_rigid = \${value} } })\"" '#260 cursor zoom rigid Lua setter is missing'
require_text "$ZOOM" "\"\$HC\" -q eval \"\$expr\"" '#260 zoom helper does not execute Lua runtime config'

# #261: Sunshine must target the exact window and use Lua-native dispatchers.
reject_text "$SUNSHINE" 'dispatch focuswindow' '#261 Sunshine helper still uses focuswindow text dispatcher'
reject_text "$SUNSHINE" 'dispatch movetoworkspacesilent' '#261 Sunshine helper still uses movetoworkspacesilent text dispatcher'
reject_text "$SUNSHINE" 'dispatch workspace' '#261 Sunshine helper still uses workspace text dispatcher'
require_text "$SUNSHINE" "hl.dsp.window.move({ workspace = \$(lua_quote \"\$TARGET_WS\"), follow = false, window = \$(lua_quote \"\$waddr\") })" '#261 exact-window Lua move is missing'
require_text "$SUNSHINE" "hl.dsp.focus({ workspace = \$(lua_quote \"\$TARGET_WS\") })" '#261 Lua workspace focus is missing'

# #262: resize submap must use the same Lua-native submap path as current Awtarchy.
reject_text "$RESIZE" 'hyprctl dispatch submap ' '#262 resize helper still uses text submap dispatch'
require_text "$RESIZE" 'hl.dsp.submap("resize")' '#262 resize-entry Lua dispatcher is missing'
require_text "$RESIZE" 'hl.dsp.submap("reset")' '#262 resize-reset Lua dispatcher is missing'

# #263: docs must use the Lua monitor API.
reject_text "$STEAM_NOTES" 'hyprctl keyword monitor' '#263 Steam notes still document legacy monitor keyword syntax'
require_text "$STEAM_NOTES" "hyprctl eval 'hl.monitor({ output =" '#263 Steam notes do not document hl.monitor through eval'

# Exercise #260 command generation and readback with a fake compositor.
ZOOM_BIN="$TMP/zoom-bin"
ZOOM_LOG="$TMP/zoom.log"
ZOOM_RIGID="$TMP/zoom-rigid"
mkdir -p -- "$ZOOM_BIN" "$TMP/zoom-config/hypr" "$TMP/zoom-state"
printf '%s\n' false >"$ZOOM_RIGID"
cat >"$ZOOM_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
    printf 'argc=%d' "$#"
    for arg in "$@"; do printf '|%s' "$arg"; done
    printf '\n'
} >>"$TEST_LOG"

if [[ "${1:-}" == "getoption" ]]; then
    case "${2:-}" in
        cursor:zoom_factor) printf '%s\n' '{"float":1.0}' ;;
        cursor:zoom_rigid)
            if [[ "$(cat "$RIGID_STATE")" == "true" ]]; then
                printf '%s\n' '{"bool":true}'
            else
                printf '%s\n' '{"bool":false}'
            fi
            ;;
        *) exit 1 ;;
    esac
    exit 0
fi

if [[ "${1:-}" == "-q" && "${2:-}" == "eval" ]]; then
    case "${3:-}" in
        *'zoom_rigid = true'*) printf '%s\n' true >"$RIGID_STATE" ;;
        *'zoom_rigid = false'*) printf '%s\n' false >"$RIGID_STATE" ;;
    esac
    exit 0
fi

exit 0
EOF
cat >"$ZOOM_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$ZOOM_BIN/hyprctl" "$ZOOM_BIN/notify-send"

: >"$ZOOM_LOG"
PATH="$ZOOM_BIN:$PATH" TEST_LOG="$ZOOM_LOG" RIGID_STATE="$ZOOM_RIGID" \
    XDG_CONFIG_HOME="$TMP/zoom-config" XDG_STATE_HOME="$TMP/zoom-state" \
    LOG_ENABLE=false NOTIFY_ENABLED=false bash "$ZOOM" set:1.5 >/dev/null
grep -Fq '|-q|eval|hl.config({ cursor = { zoom_factor = 1.500 } })' "$ZOOM_LOG" \
    || fail '#260 set:X did not emit the Lua zoom-factor update'

PATH="$ZOOM_BIN:$PATH" TEST_LOG="$ZOOM_LOG" RIGID_STATE="$ZOOM_RIGID" \
    XDG_CONFIG_HOME="$TMP/zoom-config" XDG_STATE_HOME="$TMP/zoom-state" \
    LOG_ENABLE=false NOTIFY_ENABLED=false bash "$ZOOM" rigid:on >/dev/null
grep -Fq '|-q|eval|hl.config({ cursor = { zoom_rigid = true } })' "$ZOOM_LOG" \
    || fail '#260 rigid:on did not emit the Lua zoom-rigid update'
if grep -Fq '|keyword|' "$ZOOM_LOG"; then
    fail '#260 dynamic zoom test observed a legacy keyword call'
fi

# Exercise #259 temporary mutation and EXIT restoration with one saved dwindle window.
MIX_BIN="$TMP/mix-bin"
MIX_LOG="$TMP/mix.log"
MIX_CACHE="$TMP/mix-cache"
mkdir -p -- "$MIX_BIN" "$MIX_CACHE/hypr/workspace-mix"
cat >"$MIX_BIN/python" <<'EOF'
#!/usr/bin/env bash
python3 "$@"
EOF
cat >"$MIX_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
    printf 'argc=%d' "$#"
    for arg in "$@"; do printf '|%s' "$arg"; done
    printf '\n'
} >>"$TEST_LOG"

if [[ "${1:-}" == "-j" ]]; then
    case "${2:-}" in
        monitors)
            printf '%s\n' '[{"name":"DP-1","focused":true,"activeWorkspace":{"name":" "}}]'
            ;;
        workspaces)
            printf '%s\n' '[{"id":1,"name":"1","monitor":"DP-1","tiledLayout":"dwindle"},{"id":99,"name":" ","monitor":"DP-1","tiledLayout":"dwindle"}]'
            ;;
        clients)
            printf '%s\n' '[{"address":"0xabc","workspace":{"id":99,"name":" "},"mapped":true,"floating":false,"pseudo":false,"pinned":false,"focusHistoryID":0,"at":[0,0],"size":[800,600]}]'
            ;;
        activewindow)
            printf '%s\n' '{"address":"0xabc"}'
            ;;
        getoption)
            printf '%s\n' '{"bool":false}'
            ;;
        *) printf '%s\n' '[]' ;;
    esac
    exit 0
fi

case "${1:-}" in
    dispatch|eval) exit 0 ;;
esac
exit 0
EOF
chmod +x "$MIX_BIN/python" "$MIX_BIN/hyprctl"
cat >"$MIX_CACHE/hypr/workspace-mix/state.json" <<'EOF'
{
  "selection": ["1"],
  "windows": [
    {
      "address": "0xabc",
      "orig_ws": "1",
      "floating": false,
      "pseudo": false,
      "pinned": false,
      "focus_history": 0,
      "x": 0,
      "y": 0,
      "w": 800,
      "h": 600
    }
  ],
  "workspaces": {
    "1": {
      "monitor": "DP-1",
      "layout": "dwindle",
      "last_window": "0xabc"
    }
  },
  "mix_ws": " ",
  "monitor": "DP-1",
  "prev_ws": "2",
  "prev_window": "",
  "created": 1
}
EOF

: >"$MIX_LOG"
PATH="$MIX_BIN:$PATH" TEST_LOG="$MIX_LOG" XDG_CACHE_HOME="$MIX_CACHE" \
    bash "$WORKSPACE_MIX" restore >/dev/null
for expected in \
    'eval|hl.config({ dwindle = { use_active_for_splits = true } })' \
    'eval|hl.config({ dwindle = { preserve_split = true } })' \
    'eval|hl.config({ dwindle = { use_active_for_splits = false } })' \
    'eval|hl.config({ dwindle = { preserve_split = false } })'; do
    grep -Fq -- "$expected" "$MIX_LOG" || fail "#259 missing runtime/restore command: $expected"
done
if grep -Fq '|keyword|' "$MIX_LOG"; then
    fail '#259 dynamic workspace-mix test observed a legacy keyword call'
fi
if grep -Eq 'hl\.dsp\.window\.(float|pseudo)\(\{ action = '\''(set|unset)'\''' "$MIX_LOG"; then
    fail '#259 dynamic workspace-mix test observed non-idempotent set/unset state actions'
fi

# Exercise #261 against fake Steam/Hyprland so exact-window command generation is tested.
SUN_BIN="$TMP/sun-bin"
SUN_LOG="$TMP/sun.log"
mkdir -p -- "$SUN_BIN"
cat >"$SUN_BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "list" ]]; then
    printf '%s\n' 'Steam com.valvesoftware.Steam'
fi
exit 0
EOF
cat >"$SUN_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
    printf 'argc=%d' "$#"
    for arg in "$@"; do printf '|%s' "$arg"; done
    printf '\n'
} >>"$TEST_LOG"
if [[ "${1:-}" == "clients" ]]; then
    printf '%s\n' '[{"title":"Steam Big Picture","address":"0xabc"}]'
fi
exit 0
EOF
chmod +x "$SUN_BIN/flatpak" "$SUN_BIN/hyprctl"
: >"$SUN_LOG"
PATH="$SUN_BIN:$PATH" TEST_LOG="$SUN_LOG" bash "$SUNSHINE" >/dev/null
grep -Fq 'dispatch|hl.dsp.window.move({ workspace = '\''1'\'', follow = false, window = '\''address:0xabc'\'' })' "$SUN_LOG" \
    || fail '#261 fake Sunshine run did not move the exact Big Picture address'
grep -Fq 'dispatch|hl.dsp.focus({ workspace = '\''1'\'' })' "$SUN_LOG" \
    || fail '#261 fake Sunshine run did not focus workspace 1 through Lua'
if grep -Eq 'dispatch\|(focuswindow|movetoworkspacesilent|workspace)(\||$)' "$SUN_LOG"; then
    fail '#261 fake Sunshine run observed a legacy text dispatcher'
fi

# Exercise #262 enter/reset calls with a safe fake Hyprland session.
RESIZE_BIN="$TMP/resize-bin"
RESIZE_LOG="$TMP/resize.log"
RESIZE_RUNTIME="$TMP/runtime"
mkdir -p -- "$RESIZE_BIN" "$RESIZE_RUNTIME"
chmod 0700 "$RESIZE_RUNTIME"
cat >"$RESIZE_BIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
{
    printf 'argc=%d' "$#"
    for arg in "$@"; do printf '|%s' "$arg"; done
    printf '\n'
} >>"$TEST_LOG"
if [[ "${1:-}" == "-j" ]]; then
    case "${2:-}" in
        activewindow)
            printf '%s\n' '{"address":"0x1","fullscreen":false,"fullscreenstate":{"internal":0,"client":0}}'
            ;;
        activeworkspace)
            printf '%s\n' '{"id":1}'
            ;;
        clients)
            printf '%s\n' '[{"workspace":{"id":1}},{"workspace":{"id":1}}]'
            ;;
    esac
fi
exit 0
EOF
cat >"$RESIZE_BIN/pkill" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$RESIZE_BIN/hyprctl" "$RESIZE_BIN/pkill"
: >"$RESIZE_LOG"
PATH="$RESIZE_BIN:$PATH" TEST_LOG="$RESIZE_LOG" XDG_RUNTIME_DIR="$RESIZE_RUNTIME" \
    bash "$RESIZE" >/dev/null
PATH="$RESIZE_BIN:$PATH" TEST_LOG="$RESIZE_LOG" XDG_RUNTIME_DIR="$RESIZE_RUNTIME" \
    bash "$RESIZE" reset >/dev/null
grep -Fq 'dispatch|hl.dsp.submap("resize")' "$RESIZE_LOG" \
    || fail '#262 resize helper did not enter the Lua-native resize submap'
grep -Fq 'dispatch|hl.dsp.submap("reset")' "$RESIZE_LOG" \
    || fail '#262 resize helper did not reset through the Lua-native submap dispatcher'
if grep -Eq 'dispatch\|submap\|' "$RESIZE_LOG"; then
    fail '#262 fake resize run observed legacy text submap dispatch'
fi

printf '%s\n' 'PASS: #258-#263 Lua-runtime migration contracts and command generation are covered.'
