#!/usr/bin/env bash
set -euo pipefail

# ~/.config/hypr/scripts/hypr_quicksettings.sh
# Launches the curses TUI in a terminal when invoked from Hyprland binds.

SCRIPT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
TUI_PY="${SCRIPT_DIR}/hypr_quicksettings_tui.py"

if [[ -t 1 ]]; then
  exec python3 "$TUI_PY"
fi

# Prefer your Wayland terminals first.
if command -v kitty >/dev/null 2>&1; then
  exec kitty --class hypr-quicksettings -e python3 "$TUI_PY"
fi

if command -v foot >/dev/null 2>&1; then
  exec foot --app-id=hypr-quicksettings -e python3 "$TUI_PY"
fi

if command -v alacritty >/dev/null 2>&1; then
  exec alacritty --class hypr-quicksettings -e python3 "$TUI_PY"
fi

if command -v wezterm >/dev/null 2>&1; then
  exec wezterm start --class hypr-quicksettings -- python3 "$TUI_PY"
fi

if command -v konsole >/dev/null 2>&1; then
  exec konsole --appname hypr-quicksettings -e python3 "$TUI_PY"
fi

if command -v gnome-terminal >/dev/null 2>&1; then
  exec gnome-terminal --title=hypr-quicksettings -- python3 "$TUI_PY"
fi

# Last resort (Xwayland).
exec xterm -T hypr-quicksettings -e python3 "$TUI_PY"
