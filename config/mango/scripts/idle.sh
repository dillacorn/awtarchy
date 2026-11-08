#!/usr/bin/env bash
# Mango session idle actions using Awtarchy's existing protected-idle guard.
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}"
mango="$config/mango/scripts"
hypr="$config/hypr/scripts"
action="${1:-}"

[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || {
    printf 'Mango idle handler requires an active Mango session\n' >&2
    false
}
[[ -f "$mango/idle-ipc-compat.py" && ! -L "$mango/idle-ipc-compat.py" ]] || {
    printf 'Mango idle IPC bridge missing\n' >&2
    false
}
[[ -f "$hypr/hypridle_action.sh" && ! -L "$hypr/hypridle_action.sh" ]] || {
    printf 'Awtarchy protected-idle guard missing\n' >&2
    false
}
export HYPRCTL_BIN="$mango/idle-ipc-compat.py"
export LOCK_MANAGER="$mango/lock.sh"
export QUICKSHELL_CONFIG_NAME=awtarchy-mango
export SUSPEND_EXEC_OVERRIDE="$mango/suspend-guard.sh"
guard="$hypr/hypridle_action.sh"

case "$action" in
    bar-hide)
        bash "$guard" waybar-hide
        ;;
    bar-restore)
        bash "$hypr/quickshell_bar_restore.sh"
        ;;
    dim)
        bash "$guard" dim
        ;;
    brightness-restore)
        "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "enable" })'
        bash "$hypr/restore_brightness.sh"
        ;;
    lock)
        bash "$guard" lock
        ;;
    dpms-off)
        bash "$guard" dpms-off
        ;;
    dpms-on)
        "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "enable" })'
        ;;
    suspend)
        # Existing asynchronous suspend-watch preserves productive work,
        # Teams, game, video and OBS guards. Its final action locks securely.
        bash "$guard" suspend
        ;;
    cancel-suspend)
        bash "$guard" cancel-suspend-watch
        ;;
    protected)
        inhibitor="$hypr/idle_inhibitor_global.sh"
        if [[ -f "$inhibitor" ]] && bash "$inhibitor" is-always-awake; then
            : # Locked Always Awake explicitly blocks four-hour safety.
        else
            protected=0
            if [[ -f "$inhibitor" ]] && bash "$inhibitor" is-active; then
                protected=1
            fi
            for check in teams-inhibit-active obs-active game-active video-active; do
                if bash "$guard" "$check"; then protected=1; fi
            done
            if (( protected == 1 )); then
                bash "$mango/lock.sh" lock
                "$HYPRCTL_BIN" dispatch 'hl.dsp.dpms({ action = "disable" })'
            fi
        fi
        ;;
    *)
        printf 'usage: idle.sh {bar-hide|bar-restore|dim|brightness-restore|lock|dpms-off|dpms-on|suspend|cancel-suspend|protected}\n' >&2
        false
        ;;
esac
