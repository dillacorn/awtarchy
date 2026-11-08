#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

bash -n local/share/awtarchy/awtarchy-runtime.sh
bash -n local/share/awtarchy/awtarchy-package-reconcile.sh
bash -n local/bin/awtarchy
for script in config/mango/scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile trials/mangowm/render-quickshell.py config/mango/scripts/snapshot.py

# Separate generated Quickshell profile must be completely read-only with
# respect to the Hyprland source tree and remain within temp target root.
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
python3 trials/mangowm/render-quickshell.py \
  --source config/quickshell/awtarchy \
  --dest "$tmp/awtarchy-mango" \
  --bridge-dir trials/mangowm
test -f "$tmp/awtarchy-mango/shell.qml"
test -f "$tmp/awtarchy-mango/MangoBridge.qml"
test -f "$tmp/awtarchy-mango/MangoFocusGrab.qml"
grep -Fq 'awtarchy-mango' "$tmp/awtarchy-mango/shell.qml"
if grep -RFnE 'import Quickshell.Hyprland|HyprlandFocusGrab|\bhyprctl\b|hl\.dispatch\(' "$tmp/awtarchy-mango" --include='*.qml'; then
  printf 'ERROR: unported Hyprland QML references in Mango profile\n' >&2
  false
fi
# Fail if an attempt at a second profile silently destroys the previous.
if python3 trials/mangowm/render-quickshell.py \
  --source config/quickshell/awtarchy \
  --dest "$tmp/awtarchy-mango" \
  --bridge-dir trials/mangowm; then
  printf 'ERROR: profile renderer overwrote an existing profile\n' >&2
  false
fi
printf 'PASS: Mango managed staging syntax and profile isolation\n'
