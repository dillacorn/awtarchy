#!/usr/bin/env bash
# Toggle the single floating Default Applications selector.
set -euo pipefail

scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
printf -v selector_path '%q' "${scripts_dir}/default_applications.py"
exec "${scripts_dir}/launch_handler.sh" awtarchy-default-apps \
  "foot --app-id awtarchy-default-apps --title awtarchy-default-apps python3 ${selector_path} tui"
