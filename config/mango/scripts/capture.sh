#!/usr/bin/env bash
# Mango screenshot bridge: area, output, specific client, or all outputs.
# Never sends screenshots through Hyprland IPC.
set -euo pipefail
mode="${1:-}"
case "$mode" in
    area|screen|output|window) ;;
    *)
        printf 'Usage: capture.sh {area|screen|output|window}\n' >&2
        exit 2
        ;;
esac

directory="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p -- "$directory"
options=()
region=""
case "$mode" in
    area)
        region="$(slurp)" || exit 1
        [[ -n "$region" ]] || exit 1
        options=(-g "$region")
        ;;
    output)
        region="$(slurp -o -r)" || exit 1
        [[ -n "$region" ]] || exit 1
        options=(-g "$region")
        ;;
    window)
        [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" &&
           "${XDG_CURRENT_DESKTOP:-}" == mango ]] || {
            printf 'Mango window capture requires an active Mango session\n' >&2
            exit 1
        }
        # Mango's foreign_toplevel_id maps to grim -T. Do not substitute an
        # interactive rectangle while claiming to capture a particular window.
        command -v jq >/dev/null 2>&1 || exit 1
        client_id="$(mmsg get focusing-client |
            jq -er '.foreign_toplevel_id | select(type == "string" and length > 0 and length <= 128)')" || {
            printf 'No Mango foreign toplevel is available for capture\n' >&2
            exit 1
        }
        [[ "$client_id" =~ ^[A-Za-z0-9_.:-]+$ ]] || {
            printf 'Unexpected foreign toplevel identifier\n' >&2
            exit 1
        }
        options=(-T "$client_id")
        ;;
esac

target="$(mktemp "$directory/mango-$(date +%Y%m%d-%H%M%S)-XXXXXX.png")" || exit 1
if ! grim "${options[@]}" "$target"; then
    rm -f -- "$target"
    exit 1
fi
# Match Awtarchy's screenshot save-and-copy behavior.
if command -v wl-copy >/dev/null 2>&1; then
    wl-copy --type image/png <"$target" || {
        printf 'Screenshot saved but clipboard copy failed: %s\n' "$target" >&2
        exit 1
    }
fi
printf 'Screenshot saved: %s\n' "$target"
