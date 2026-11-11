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

# Pre-map QML has already determined monitor, placement and dimensions.
# These are advisory; explicit live resize arguments override saved size.
if [[ -f "$profile" && ! -L "$profile" && -O "$profile" ]]; then
    IFS=$'\t' read -r saved_monitor saved_place saved_w saved_h saved_bar saved_anchor < "$profile" || :
    if [[ "$saved_monitor" =~ ^[A-Za-z0-9._:-]+$ ]] &&
       [[ "$saved_place" =~ ^(center|top|bottom|left|right|top-center|bottom-center|left-center|right-center)$ ]] &&
       number "$saved_w" && number "$saved_h" && number "$saved_bar"; then
        if [[ "$action" == spawn ]]; then
            monitor="$saved_monitor"
            placement="$saved_place"
        fi
        [[ "$width" != 0 ]] || width="$saved_w"
        [[ "$height" != 0 ]] || height="$saved_h"
        bar="$saved_bar"
        if [[ "$saved_anchor" =~ ^-?[0-9]+$ ]]; then anchor="$saved_anchor"; fi
    fi
fi
[[ "$placement" != clamp ]] || placement=center
if ! number "$width" || (( width < 1 )); then width="$default_w"; fi
if ! number "$height" || (( height < 1 )); then height="$default_h"; fi

read -r x0 y0 screen_w screen_h < <(
    swaymsg -r -t get_outputs | jq -r --arg monitor "$monitor" '
        .[] | select(.name == $monitor and .active == true)
        | [.rect.x, .rect.y, .rect.width, .rect.height] | @tsv
    '
)
[[ "${screen_w:-}" =~ ^[0-9]+$ && "${screen_h:-}" =~ ^[0-9]+$ ]] ||
    { printf 'Sway flyout output missing: %s\n' "$monitor" >&2; exit 1; }
(( screen_w > 20 && screen_h > 20 )) || exit 1
(( width > screen_w - 20 )) && width=$(( screen_w - 20 ))
(( height > screen_h - 20 )) && height=$(( screen_h - 20 ))
center_x=$(( (screen_w-width)/2 ))
center_y=$(( (screen_h-height)/2 ))
x="$center_x"
y="$center_y"
case "$placement" in
    top) y="$bar" ;;
    bottom) y=$(( screen_h-height-bar )) ;;
    left) x="$bar" ;;
    right) x=$(( screen_w-width-bar )) ;;
    top-center) y="$bar" ;;
    bottom-center) y=$(( screen_h-height-bar )) ;;
    left-center) x="$bar" ;;
    right-center) x=$(( screen_w-width-bar )) ;;
esac
# Side-edge launchers have their bar on the vertical axis.
if [[ "$surface" == launcher ]]; then
    case "$placement" in
        top) x=0 ;; bottom) x=0 ;;
        left) y=0 ;; right) y=0 ;;
    esac
fi
(( x < 0 )) && x=0
(( y < 0 )) && y=0
(( x > screen_w - width )) && x=$(( screen_w-width ))
(( y > screen_h - height )) && y=$(( screen_h-height ))
x=$(( x0+x ))
y=$(( y0+y ))

# Wait briefly for the mapped FloatingWindow. The static for_window rule
# floats it immediately; this only corrects position after mapping.
id=""
for attempt in {1..35}; do
    id="$(swaymsg -r -t get_tree | jq -r --arg title "$title" '
        [ .. | objects
          | select(.type? == "con" and .name? == $title and .visible? == true)
          | .id ] | last // empty
    ')" || exit 1
    [[ "$id" =~ ^[0-9]+$ ]] && break
    sleep 0.035
done
[[ "$id" =~ ^[0-9]+$ ]] || {
    printf 'Sway flyout not mapped: %s\n' "$title" >&2; exit 1;
}
command="[con_id=$id] floating enable, resize set $width px $height px, move absolute position $x $y"
result="$(swaymsg -r "$command")" || exit 1
jq -e 'type == "array" and all(.[]; .success == true)' <<< "$result" >/dev/null ||
    { printf 'Sway rejected flyout placement for %s\n' "$title" >&2; exit 1; }
