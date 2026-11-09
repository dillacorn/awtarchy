#!/usr/bin/env bash
# Mango key modes: separate state from Hyprland's saved submap.
set -euo pipefail

usage() {
    printf 'usage: keymode.sh {set default|noalt|mouse|vm|toggle noalt|mouse|vm|restore|current}\n' >&2
    return 2
}
valid_mode() {
    case "${1:-}" in default|noalt|mouse|vm) return 0 ;; *) return 1 ;; esac
}
require_session() {
    [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" && -n "${WAYLAND_DISPLAY:-}" &&
       "${XDG_CURRENT_DESKTOP:-}" == mango ]] || {
        printf 'Mango key mode requires an active Mango session\n' >&2
        return 1
    }
    command -v mmsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}
current() {
    local response mode
    response="$(mmsg get keymode)" || return 1
    mode="$(jq -er '.keymode | select(type == "string")' <<<"$response")" || return 1
    valid_mode "$mode" || return 1
    printf '%s\n' "$mode"
}
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/awtarchy"
state_file="$state_dir/mango-keymode"
hypr_file="$state_dir/hypr-submap"

save_mode() {
    local mode="$1" temp=""
    [[ ! -L "$state_dir" && ! -L "$state_file" ]] || {
        printf 'Refusing linked Mango key-mode state\n' >&2; return 1;
    }
    mkdir -p -- "$state_dir" || return 1
    temp="$(mktemp --tmpdir="$state_dir" '.mango-keymode.XXXXXX')" || return 1
    if ! printf '%s\n' "$mode" >"$temp" || ! chmod 0600 "$temp" ||
       ! mv -Tf -- "$temp" "$state_file"; then
        rm -f -- "$temp"
        return 1
    fi
}
read_saved() {
    local file="$1" value=""
    [[ -f "$file" && ! -L "$file" && -O "$file" ]] || return 1
    [[ "$(stat -c %s -- "$file")" -le 32 ]] || return 1
    IFS= read -r value <"$file" || true
    [[ -n "$value" ]] || value=default
    valid_mode "$value" || return 1
    printf '%s\n' "$value"
}
set_mode() {
    local mode="$1" actual=""
    valid_mode "$mode" || return 2
    mmsg dispatch "setkeymode,$mode" >/dev/null || return 1
    actual="$(current)" || return 1
    [[ "$actual" == "$mode" ]] || {
        printf 'Mango did not apply key mode: %s\n' "$mode" >&2
        return 1
    }
    save_mode "$mode"
}

main() {
    require_session || return 1
    case "${1:-}" in
    current)
        [[ $# -eq 1 ]] || usage
        current
        ;;
    set)
        [[ $# -eq 2 ]] && valid_mode "$2" || { usage; return 2; }
        set_mode "$2"
        ;;
    toggle)
        [[ $# -eq 2 && "$2" != default ]] && valid_mode "$2" || { usage; return 2; }
        active="$(current)" || return 1
        if [[ "$active" == "$2" ]]; then set_mode default; else set_mode "$2"; fi
        ;;
    restore)
        [[ $# -eq 1 ]] || { usage; return 2; }
        mode="$(read_saved "$state_file" || read_saved "$hypr_file" || printf default)"
        [[ -n "$mode" ]] || mode=default
        set_mode "$mode"
        ;;
    *) usage ;;
    esac
}

main "$@"
