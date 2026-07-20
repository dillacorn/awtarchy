#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/mako_dismiss.sh

# Purpose: dismiss mako without leaving the cursor "stuck" in some games
# Requires: makoctl, jq, hyprctl

set -euo pipefail

# Save the current cursor position.
read -r CX CY < <(hyprctl -j cursorpos | jq -r '"\(.x) \(.y)"')

restore_cursor() {
    hyprctl dispatch "hl.dsp.cursor.move({ x = ${CX}, y = ${CY} })" >/dev/null 2>&1 || true
}

# Always restore the cursor, including when makoctl fails.
trap restore_cursor EXIT

# Move the cursor to a corner to force a redraw in Hyprland.
# Failure here must not prevent the notification from being dismissed.
hyprctl dispatch 'hl.dsp.cursor.move_to_corner({ corner = 2 })' >/dev/null 2>&1 || true

# Dismiss the first visible notification.
makoctl dismiss
