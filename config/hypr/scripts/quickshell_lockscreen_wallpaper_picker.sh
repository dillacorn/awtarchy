#!/usr/bin/env bash
set -euo pipefail

AWTWALL_CMD="${AWTWALL_CMD:-awtwall}"
TERMINAL_CMD="${LOCKSCREEN_WALLPAPER_TERMINAL:-alacritty}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
RESULT_DIR="${CACHE_HOME}/awtarchy"
RESULT_FILE=""
PICKER_CLASS="awtarchy-lock-wallpaper"
PICKER_TITLE="Awtarchy-Lockscreen-Wallpaper"
MAP_ATTEMPTS=100
FULLSCREEN_ATTEMPTS=40
POLL_INTERVAL=0.05

cleanup() {
    [[ -z "$RESULT_FILE" ]] || rm -f -- "$RESULT_FILE"
}
trap cleanup EXIT

have() {
    command -v "$1" >/dev/null 2>&1
}

mapped_picker_address() {
    hyprctl clients -j 2>/dev/null | jq -r \
        --arg class "$PICKER_CLASS" --arg title "$PICKER_TITLE" '
            first(.[] | select(.class == $class and .title == $title) | .address) // empty
        ' 2>/dev/null || true
}

picker_fullscreen_state() {
    local address="$1"
    hyprctl clients -j 2>/dev/null | jq -r --arg address "$address" '
        first(.[] | select(.address == $address) | .fullscreen) // empty
    ' 2>/dev/null || true
}

request_picker_fullscreen() {
    local address="$1"
    local selector="address:${address}"

    # Hyprland 0.55+ dispatchers accept an exact window selector directly.
    # Use an explicit set action so retries cannot toggle the picker back out.
    hyprctl dispatch "hl.dsp.focus({ window = \"${selector}\" })" >/dev/null 2>&1 || true
    hyprctl dispatch "hl.dsp.window.fullscreen({ window = \"${selector}\", mode = \"fullscreen\", action = \"set\" })" \
        >/dev/null 2>&1 || true
}

ensure_picker_fullscreen() {
    local window_address=""
    local fullscreen_state=""

    for ((_attempt = 0; _attempt < MAP_ATTEMPTS; _attempt++)); do
        window_address="$(mapped_picker_address)"
        if [[ "$window_address" =~ ^0x[[:xdigit:]]+$ ]]; then
            break
        fi
        window_address=""
        sleep "$POLL_INTERVAL"
    done

    [[ -n "$window_address" ]] || return 0

    for ((_attempt = 0; _attempt < FULLSCREEN_ATTEMPTS; _attempt++)); do
        fullscreen_state="$(picker_fullscreen_state "$window_address")"
        [[ "$fullscreen_state" == "2" ]] && return 0
        request_picker_fullscreen "$window_address"
        sleep "$POLL_INTERVAL"
    done

    # One final read verifies the last bounded request without turning a picker
    # failure into a wallpaper-selection failure.
    picker_fullscreen_state "$window_address" >/dev/null
}

awtwall_path="$(command -v "$AWTWALL_CMD" 2>/dev/null || true)"
if [[ -z "$awtwall_path" ]]; then
    printf 'Awtwall is not installed\n' >&2
    exit 1
fi

if ! bash "$awtwall_path" --help 2>/dev/null | grep -Fq -- '--select-only'; then
    printf 'Awtwall does not support lockscreen selection-only mode yet\n' >&2
    printf 'Install an Awtwall build with --select-only support\n' >&2
    exit 2
fi

if ! have "$TERMINAL_CMD"; then
    printf 'Lockscreen wallpaper picker requires %s\n' "$TERMINAL_CMD" >&2
    exit 1
fi

mkdir -p -- "$RESULT_DIR"
RESULT_FILE="$(mktemp "${RESULT_DIR}/lockscreen-wallpaper-selection.XXXXXX")"
rm -f -- "$RESULT_FILE"

set +e
terminal_name="$(basename -- "$TERMINAL_CMD")"
if [[ "$terminal_name" == "alacritty" ]]; then
    "$TERMINAL_CMD" --option window.startup_mode=Fullscreen \
        --class awtarchy-lock-wallpaper --title Awtarchy-Lockscreen-Wallpaper \
        -e "$awtwall_path" --select-only --type images --resume \
        --select-result "$RESULT_FILE" &
    terminal_pid=$!
else
    "$TERMINAL_CMD" --class awtarchy-lock-wallpaper \
        --title Awtarchy-Lockscreen-Wallpaper -e "$awtwall_path" \
        --select-only --type images --resume --select-result "$RESULT_FILE" &
    terminal_pid=$!
fi

if have hyprctl && have jq; then
    ensure_picker_fullscreen
fi
wait "$terminal_pid"
terminal_rc=$?
set -e

# Closing/cancelling the picker is a clean no-change result.
if [[ ! -s "$RESULT_FILE" ]]; then
    if (( terminal_rc != 0 )); then
        printf 'Awtwall lockscreen picker closed without a selection\n' >&2
    fi
    exit 0
fi

IFS= read -r selected <"$RESULT_FILE" || selected=""
if [[ -z "$selected" || "$selected" != /* || ! -f "$selected" || ! -r "$selected" ]]; then
    printf 'Awtwall returned an invalid lockscreen wallpaper path\n' >&2
    exit 3
fi
if [[ "$selected" == *$'\n'* || "$selected" == *$'\r'* ]]; then
    printf 'Awtwall returned an invalid lockscreen wallpaper path\n' >&2
    exit 3
fi

printf '%s\n' "$selected"
