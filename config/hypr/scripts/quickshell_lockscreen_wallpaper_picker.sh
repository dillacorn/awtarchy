#!/usr/bin/env bash
set -euo pipefail

AWTWALL_CMD="${AWTWALL_CMD:-awtwall}"
TERMINAL_CMD="${LOCKSCREEN_WALLPAPER_TERMINAL:-alacritty}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
RESULT_DIR="${CACHE_HOME}/awtarchy"
RESULT_FILE=""

cleanup() {
    [[ -z "$RESULT_FILE" ]] || rm -f -- "$RESULT_FILE"
}
trap cleanup EXIT

have() {
    command -v "$1" >/dev/null 2>&1
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
    for _attempt in {1..20}; do
        if hyprctl clients -j 2>/dev/null | jq -e '
            any(.[]; .class == "awtarchy-lock-wallpaper"
                and .title == "Awtarchy-Lockscreen-Wallpaper")
        ' >/dev/null 2>&1; then
            hyprctl dispatch focuswindow 'class:^(awtarchy-lock-wallpaper)$' >/dev/null 2>&1 || true
            hyprctl dispatch fullscreen 1 >/dev/null 2>&1 || true
            break
        fi
        sleep 0.05
    done
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
