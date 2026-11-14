#!/usr/bin/env bash
set -euo pipefail
# Sway window placement rules are in config.toml; no Hyprland dispatcher.
# Dynamic privacy/capture rules cannot be treated as applied.
printf 'Sway runtime rule update unsupported; do not assume privacy rules applied\n' >&2
exit 1
