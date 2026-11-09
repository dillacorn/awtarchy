#!/usr/bin/env bash
# Validate Mango Quick Settings mapping without Hyprland or a running compositor.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p -- "$tmp/bin" "$tmp/config/hypr/scripts" "$tmp/config/mango/scripts"
cat >"$tmp/config/hypr/scripts/hypr_quicksettings.sh" <<'BACKEND'
#!/usr/bin/env bash
case "$1" in
    --status-json)
        printf '%s\n' '{"monitors":[],"brightness":{"current":50,"max":100},"sched_ext":{"running":"off","schedulers":[]},"night_light":{"enabled":true},"vibrance":{"enabled":true},"bar":{"enabled":false}}'
        ;;
    --action)
        printf '%s\n' "$*" >>"$AWTARCHY_QS_ORIGINAL_LOG"
        ;;
    --authorize-scheduler-stdin|--restore-scheduler)
        printf '%s\n' "$1" >>"$AWTARCHY_QS_ORIGINAL_LOG"
        ;;
    *) false ;;
esac
BACKEND
cat >"$tmp/config/mango/scripts/quickshell.sh" <<'MANAGER'
#!/usr/bin/env bash
case "$1" in
    getpos) printf '%s\n' right ;;
    getenabled) printf '%s\n' true ;;
    getautohide) printf '%s\n' false ;;
    setenabled|setautohide|setpos)
        printf '%s\n' "$*" >>"$AWTARCHY_QS_MANAGER_LOG"
        ;;
    *) false ;;
esac
MANAGER
cat >"$tmp/bin/mmsg" <<'MMSG'
#!/usr/bin/env bash
case "$*" in
    'get all-monitors')
        printf '%s\n' '{"monitors":[{"name":"DP-1","active":true,"width":1920,"height":1080}]}'
        ;;
    'get keymode')
        jq -cn --arg mode "$(cat "$AWTARCHY_QS_MODE_FILE")" '{keymode:$mode}'
        ;;
    'dispatch setkeymode,'*)
        printf '%s\n' "$*" >>"$AWTARCHY_QS_IPC_LOG"
        printf '%s\n' "${2#setkeymode,}" >"$AWTARCHY_QS_MODE_FILE"
        ;;
    *) false ;;
esac
MMSG
cp config/mango/scripts/keymode.sh "$tmp/config/mango/scripts/keymode.sh"
chmod +x "$tmp/bin/mmsg" "$tmp/config/"*/scripts/*.sh
mkdir -p "$tmp/state"
printf 'default\n' >"$tmp/mode"
export PATH="$tmp/bin:$PATH" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state"
export MANGO_INSTANCE_SIGNATURE=mock-session WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=mango
export AWTARCHY_QS_MODE_FILE="$tmp/mode"
export AWTARCHY_QS_ORIGINAL_LOG="$tmp/original.log"
export AWTARCHY_QS_MANAGER_LOG="$tmp/manager.log"
export AWTARCHY_QS_IPC_LOG="$tmp/ipc.log"

backend="config/mango/scripts/quicksettings.sh"
bash -n "$backend"
status="$(bash "$backend" --status-json DP-1 DP-1)"
jq -e '.monitors[0].name == "DP-1" and .monitors[0].focused == true
    and .bar.monitor == "DP-1" and .bar.position == "right"
    and .bar.enabled == true and .bar.auto_hide == false
    and .brightness.current == 50 and .sched_ext.running == "off"
    and .submap == "reset" and .night_light.enabled == false
    and .vibrance.enabled == false' <<<"$status" >/dev/null

bash "$backend" --action brightness-percent DP-1 75
bash "$backend" --action bar-enabled DP-1 false
bash "$backend" --action bar-position DP-1 left
bash "$backend" --action submap reset
bash "$backend" --action submap noalt
[[ "$(cat "$AWTARCHY_QS_MODE_FILE")" == noalt ]]
[[ "$(cat "$tmp/state/awtarchy/mango-keymode")" == noalt ]]
status="$(bash "$backend" --status-json DP-1 DP-1)"
jq -e '.submap == "noalt"' <<<"$status" >/dev/null
bash "$backend" --action submap reset
bash "$backend" --restore-scheduler
grep -Fxq -- '--action brightness-percent DP-1 75' "$AWTARCHY_QS_ORIGINAL_LOG"
grep -Fxq -- '--restore-scheduler' "$AWTARCHY_QS_ORIGINAL_LOG"
grep -Fxq -- 'setenabled DP-1 false' "$AWTARCHY_QS_MANAGER_LOG"
grep -Fxq -- 'setpos DP-1 left' "$AWTARCHY_QS_MANAGER_LOG"
grep -Fxq -- '{}' "$AWTARCHY_QS_IPC_LOG"

for unsupported in night-light vibrance; do
    if bash "$backend" --action "$unsupported" toggle >/dev/null 2>&1; then
        printf 'ERROR: unsupported Mango setting succeeded: %s\n' "$unsupported" >&2
        false
    fi
done
if bash "$backend" --action submap not-a-mode >/dev/null 2>&1; then
    printf 'ERROR: invalid Mango mode was accepted\n' >&2
    false
fi
[[ $(wc -l <"$AWTARCHY_QS_IPC_LOG") == 3 ]]
printf 'PASS: Mango Quick Settings status, native key modes, shared operations and guarded actions\n'
