#!/usr/bin/env bash
# Read-only health report for an installed Awtarchy Mango session.
# Does not inspect window titles, authentication content or clipboard.
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}"
problems=0
record() {
    local name="$1" status="$2"
    printf '%-28s %s\n' "$name" "$status"
    if [[ "$status" != PASS ]]; then
        problems=$((problems + 1))
    fi
}
check_file() {
    local name="$1" file="$2"
    if [[ -f "$file" && ! -L "$file" ]]; then
        record "$name" PASS
    else
        record "$name" MISSING
    fi
}
check_binary() {
    local name="$1" binary="$2"
    if command -v "$binary" >/dev/null 2>&1; then
        record "$name" PASS
    else
        record "$name" MISSING
    fi
}
check_user_service() {
    local name="$1" unit="$2"
    if command -v systemctl >/dev/null 2>&1 &&
        systemctl --user is-active --quiet "$unit" 2>/dev/null; then
        record "$name" PASS
    else
        record "$name" INACTIVE
    fi
}
check_process() {
    local name="$1" binary="$2"
    if pgrep -u "$(id -u)" -x "$binary" >/dev/null 2>&1; then
        record "$name" PASS
    else
        record "$name" INACTIVE
    fi
}

printf '%s\n' '=== Awtarchy Mango migration diagnostics (read-only) ==='
if [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" &&
    -n "${WAYLAND_DISPLAY:-}" &&
    "${XDG_CURRENT_DESKTOP:-}" == mango ]]; then
    record 'Mango session environment' PASS
else
    record 'Mango session environment' NOT_ACTIVE
fi

for binary in mango mmsg qs jq swayidle swaylock foot python3; do
    check_binary "Binary: $binary" "$binary"
done
check_file 'Managed Mango config' "$config/mango/config.conf"
check_file 'Mango Quickshell profile' "$config/quickshell/awtarchy-mango/shell.qml"
check_file 'Original Hyprland config' "$config/hypr/hyprland.lua"
check_file 'Original Quickshell profile' "$config/quickshell/awtarchy/shell.qml"

# The first trial reported PASS despite missing basic bindings. Make the
# installed config itself part of runtime diagnostics, not just file presence.
if [[ -f "$config/mango/config.conf" && ! -L "$config/mango/config.conf" ]] &&
    grep -Fq 'bind=ALT+SHIFT,Return,spawn_shell,python3' "$config/mango/config.conf" &&
    grep -Fq 'bind=SUPER,W,spawn_shell,' "$config/mango/config.conf" &&
    grep -Fq 'bind=SUPER+ALT,A,spawn_shell,' "$config/mango/config.conf" &&
    grep -Fq 'bind=SUPER+ALT,N,spawn_shell,' "$config/mango/config.conf"; then
    record 'Core Mango shortcut parity' PASS
else
    record 'Core Mango shortcut parity' MISSING
fi
check_file 'Mango display manager' "$config/mango/scripts/monitor-info.sh"
check_binary 'Binary: AwtWall' awtwall
check_binary 'Binary: wdisplays' wdisplays


if command -v mmsg >/dev/null 2>&1 &&
    mmsg get version >/dev/null 2>&1; then
    record 'Mango IPC version' PASS
else
    record 'Mango IPC version' UNAVAILABLE
fi

if command -v mmsg >/dev/null 2>&1 &&
    command -v jq >/dev/null 2>&1 &&
    mmsg get all-monitors 2>/dev/null |
        jq -e '.monitors | type == "array" and length > 0' >/dev/null 2>&1; then
    record 'Mango monitor IPC' PASS
else
    record 'Mango monitor IPC' UNAVAILABLE
fi

if command -v qs >/dev/null 2>&1 &&
    qs -c awtarchy-mango ipc call control ping >/dev/null 2>&1; then
    record 'Mango Quickshell IPC' PASS
else
    record 'Mango Quickshell IPC' UNAVAILABLE
fi

check_process 'Swayidle process' swayidle
check_user_service 'Awtarchy PolicyKit' awtarchy-polkit-agent.service
check_user_service 'Desktop portal' xdg-desktop-portal.service

if [[ -f "$config/mango/config.conf" && ! -L "$config/mango/config.conf" ]] &&
    command -v mango >/dev/null 2>&1 &&
    mango -c "$config/mango/config.conf" -p >/dev/null 2>&1; then
    record 'Mango config parser' PASS
else
    record 'Mango config parser' FAILED
fi

if ((problems > 0)); then
    printf '\n%d item(s) need investigation. No settings were changed.\n' "$problems"
    false
else
    printf '\nAll reported startup checks passed. Game, capture and suspend runtime behavior remain untested.\n'
fi
