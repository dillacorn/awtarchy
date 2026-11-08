#!/usr/bin/env bash
# Mango window rules belong in config.conf, not Hyprland's runtime Lua registry.
set -euo pipefail
[[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]] || exit 1
# Integration is managed by config/mango/config.conf.
