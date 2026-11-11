#!/usr/bin/env bash
# Sway-native Quickshell flyout staging and exact-window placement.
# Never fall back to hyprctl; restrict criteria to known Awtarchy titles.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == sway && -n "${SWAYSOCK:-}" ]] || {
    printf 'Sway window position requires active Sway\n' >&2; exit 1;
}
command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 ||
    { printf 'Sway placement requires swaymsg and jq\n' >&2; exit 127; }

surface=""
monitor=""
placement="center"
action="spawn"
width=0
height=0
bar=28
anchor=-1
case "${1:-}" in
    launcher|clipboard|notifications|quick-settings|network|bluetooth|battery)
        surface="$1"
        [[ $# -eq 9 || $# -ge 4 ]] || exit 2
        monitor="$2"
        placement="$3"
        if [[ $# -eq 9 ]]; then
            action=prepare
            width="$4"
            height="$5"
            bar="$6"
            anchor="$7"
            screen_w="$8"
            screen_h="$9"
        else
            action="$4"
            if [[ $# -ge 6 ]]; then
                width="$5"
                height="$6"
            fi
        fi ;;
    *)
        # Launcher post-map API: position.sh MONITOR PLACEMENT [clamp].
        [[ $# -ge 2 && $# -le 3 ]] || exit 2
        surface=launcher
        monitor="$1"
        placement="$2"
        action="${3:-spawn}" ;;
esac

[[ "$monitor" =~ ^[A-Za-z0-9._:-]+$ ]] || exit 2
case "$placement" in
    center|top|bottom|left|right|top-center|bottom-center|left-center|right-center|clamp) ;;
    *) printf 'Invalid Sway flyout placement: %s\n' "$placement" >&2; exit 2 ;;
esac
case "$action" in
    prepare|spawn|resize|resize-compact|clamp) ;;
    *) printf 'Invalid Sway flyout action: %s\n' "$action" >&2; exit 2 ;;
esac
case "$surface" in
    launcher) title="Awtarchy Application Search"; default_w=420; default_h=582 ;;
    clipboard) title="Awtarchy Clipboard History"; default_w=880; default_h=760 ;;
    notifications) title="Awtarchy Notification Center"; default_w=520; default_h=760 ;;
    quick-settings) title="Awtarchy Quick Settings"; default_w=860; default_h=850 ;;
    network) title="Awtarchy Network"; default_w=520; default_h=600 ;;
    bluetooth) title="Awtarchy Bluetooth"; default_w=500; default_h=600 ;;
    battery) title="Awtarchy Battery"; default_w=560; default_h=560 ;;
esac

state="${XDG_RUNTIME_DIR:-}/awtarchy-sway/flyout-targets"
[[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR:-}" &&
   ! -L "${XDG_RUNTIME_DIR:-}" ]] || exit 1
mkdir -p -m 0700 -- "$state"
[[ ! -L "$state" && ! -L "${state%/*}" ]] || exit 1
profile="$state/$surface"

number() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 <= 10000 )); }
if [[ "$action" == prepare ]]; then
    for value in "$width" "$height" "$bar" "$screen_w" "$screen_h"; do
        number "$value" || exit 2
    done
    [[ "$anchor" =~ ^-?[0-9]+$ ]] || exit 2
    (( width >= 1 && height >= 1 && screen_w >= 1 && screen_h >= 1 )) || exit 2
    [[ ! -L "$profile" ]] || exit 1
    tmp="$(mktemp "$state/.$surface-XXXXXXXX")"
    chmod 0600 -- "$tmp"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$monitor" "$placement" "$width" "$height" "$bar" "$anchor" > "$tmp"
    mv -f -- "$tmp" "$profile"
    exit 0
fi

# The generated Sway flyouts are now native layer-shell panels, not
# application toplevels. Their QML anchors and margins are calculated before
# mapping; Sway does not enumerate them in get_tree, so post-map floating or
# resize commands would be both ineffective and visibly unstable.
#
# This helper retains the exact existing prepare operation (and its per-output
# sizing cache) to preserve the source QML's prewarm and readiness contract.
# spawn/resize/clamp are intentionally successful no-ops. The layer-shell
# component owns those updates reactively on the Qt side.
exit 0
