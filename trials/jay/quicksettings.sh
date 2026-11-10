#!/usr/bin/env bash
# Intentionally do not run the Hyprland Quick Settings backend in Jay.
set -euo pipefail
printf 'Jay Quick Settings compositor controls are not ported. Shared UI state remains available.\n' >&2
exit 1
