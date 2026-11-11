#!/usr/bin/env bash
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}"
bash "$config/sway/awtarchy-trial/ipc.sh" "powermenu" "begin"
