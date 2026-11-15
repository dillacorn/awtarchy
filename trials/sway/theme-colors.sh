#!/usr/bin/env bash
# Apply Hyprland theme border colors to Sway without modifying Hyprland config.
# Invoked at Sway login/reload and after a Sway theme selection.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == "sway" && -n "${SWAYSOCK:-}" ]] || {
    printf 'Sway theme colors require an active Sway session\n' >&2
    exit 1
}
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
theme_name="${1:-}"
if [[ -z "$theme_name" ]]; then
    for state_file in "$state_home/active-theme-sway" "$state_home/active-theme"; do
        if [[ -f "$state_file" && ! -L "$state_file" ]]; then
            IFS= read -r theme_name <"$state_file" || true
            [[ -z "$theme_name" ]] || break
        fi
    done
fi

# The defaults remain usable for a new account without a selected theme.
active="a0a0a0ff"
inactive="4b4b4bff"
background="#353535"
foreground="#d0d0d0"
urgent="#ff5555"

theme_value() {
    local key="$1" file="$2"
    awk -F= -v key="$key" '
        $1 == key {
            value = $0
            sub(/^[^=]*=/, "", value)
            gsub(/^[[:space:]]*["\047]|["\047][[:space:]]*$/, "", value)
            print value
            exit
        }' "$file"
}
if [[ -n "$theme_name" ]]; then
    [[ "$theme_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
        printf 'Unsafe Sway theme name\n' >&2
        exit 2
    }
    theme_file="$config_home/hypr/themes/$theme_name"
    [[ -f "$theme_file" && ! -L "$theme_file" ]] || {
        printf 'Missing Sway theme source: %s\n' "$theme_file" >&2
        exit 1
    }
    for pair in NEW_ACTIVE_BORDER:active NEW_INACTIVE_BORDER:inactive \
                QS_BACKGROUND:background QS_FOREGROUND:foreground QS_URGENT:urgent; do
        key="${pair%%:*}"
        field="${pair#*:}"
        value="$(theme_value "$key" "$theme_file")"
        [[ -n "$value" ]] || continue
        case "$field" in
            active) active="$value" ;;
            inactive) inactive="$value" ;;
            background) background="$value" ;;
            foreground) foreground="$value" ;;
            urgent) urgent="$value" ;;
        esac
    done
fi

[[ "$active" =~ ^[[:xdigit:]]{8}$ &&
   "$inactive" =~ ^[[:xdigit:]]{8}$ &&
   "$background" =~ ^#[[:xdigit:]]{6}$ &&
   "$foreground" =~ ^#[[:xdigit:]]{6}$ &&
   "$urgent" =~ ^#[[:xdigit:]]{6}$ ]] || {
    printf 'Invalid border palette in selected theme\n' >&2
    exit 1
}

# All border, insertion indicator and child-border fields receive the same
# accent. Otherwise Sway can paint a default-blue segment on a themed window.
commands=(
    "client.focused #$active $background $foreground #$active #$active"
    "client.focused_inactive #$inactive $background $foreground #$inactive #$inactive"
    "client.unfocused #$inactive $background $foreground #$inactive #$inactive"
    "client.urgent $urgent $urgent $foreground $urgent $urgent"
)
for sway_command in "${commands[@]}"; do
    response="$(swaymsg -r -t command "$sway_command")" || {
        printf 'Sway rejected theme border command: %s\n' "$sway_command" >&2
        exit 1
    }
    jq -e 'type == "array" and length > 0 and all(.[]; .success == true)' \
        >/dev/null <<<"$response" || {
        printf 'Sway reported failed theme border command: %s\n' "$sway_command" >&2
        exit 1
    }
done
