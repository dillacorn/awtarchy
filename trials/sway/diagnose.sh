#!/usr/bin/env bash
# Read-only diagnostics for Awtarchy's experimental Sway Quickshell profile.
set -euo pipefail
if [[ "${XDG_CURRENT_DESKTOP:-}" != sway || -z "${SWAYSOCK:-}" ]]; then
    printf 'Run inside the Sway trial, not Hyprland\n' >&2
    exit 1
fi
for bin in swaymsg jq python3; do
    command -v "$bin" >/dev/null 2>&1 || {
        printf 'Missing required tool: %s\n' "$bin" >&2
        exit 127
    }
done
printf '\n=== Sway version ===\n'
swaymsg -r -t get_version | jq '{human_readable, major, minor, patch}' || true
printf '\n=== Active and hidden workspace numbers ===\n'
swaymsg -r -t get_workspaces | jq '[.[] | {num, name, output, visible, focused}]' || true
printf '\n=== Shell and maccel window identity/geometry ===\n'
swaymsg -r -t get_tree | jq -c '
    .. | objects | select(.type? == "con")
    | select(
        ((.name // "") | startswith("Awtarchy"))
        or ((.app_id // "") | test("(?i)(quickshell|maccel|awtarchy-sway)"))
    )
    | {id, name, app_id, shell, focused, visible, rect}
' || true
printf '\n=== Workspace membership counts (no private window titles) ===\n'
helper="${XDG_CONFIG_HOME:-$HOME/.config}/sway/awtarchy-trial/workspace-state.py"
if [[ -f "$helper" && ! -L "$helper" ]]; then
    python3 "$helper" | jq '[.[] | {id, name, monitor, focused, active, count: (.clients | length)}]' || true
else
    printf 'Workspace helper missing\n'
fi
printf '\n=== Sway Quickshell control endpoint ===\n'
if command -v qs >/dev/null 2>&1; then
    qs -c awtarchy-sway ipc call control ping || true
fi
printf '\n=== maccel binary and supported subcommands ===\n'
if command -v maccel >/dev/null 2>&1; then
    command -v maccel
    maccel --help 2>&1 | head -n 20 || true
else
    printf 'maccel binary absent\n'
fi
printf '\n=== Screenshot lock holders ===\n'
if command -v lslocks >/dev/null 2>&1; then
    lslocks --noheadings -o PID,COMMAND,PATH 2>/dev/null |
        grep -F '/awtarchy-locks/sway-screenshot.lock' || true
fi
printf '\n=== Recent Quickshell warning/error lines ===\n'
log="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/quickshell-sway.log"
if [[ -f "$log" && ! -L "$log" ]]; then
    grep -iE 'error|warn|qml|failed|swaybridge|swaydragbridge|swaybardrag' "$log" | tail -n 45 || true
else
    printf 'Sway Quickshell log unavailable\n'
fi
