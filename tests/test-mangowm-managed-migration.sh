#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

bash -n local/share/awtarchy/awtarchy-runtime.sh
bash -n local/share/awtarchy/awtarchy-package-reconcile.sh
bash -n local/bin/awtarchy
test -s config/xdg-desktop-portal/mango-portals.conf
grep -Fqx 'org.freedesktop.impl.portal.ScreenCast=wlr' config/xdg-desktop-portal/mango-portals.conf
grep -Fqx 'org.freedesktop.impl.portal.Screenshot=wlr' config/xdg-desktop-portal/mango-portals.conf
grep -Fq 'shield_when_capture:1,app_id:' config/mango/config.conf
grep -Fq 'app_id:^awtarchy-default-appsgrep -Fq 'dev\.vencord\.Vesktop' config/mango/config.conf
[[ $(grep -Fc 'env=XCURSOR_THEME,' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_theme=' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_size=' config/mango/config.conf) == 1 ]]
for script in config/mango/scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile trials/mangowm/render-quickshell.py config/mango/scripts/snapshot.py config/mango/scripts/cursor-variant.py

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
grep -Fq '/mango/scripts/lock.sh' "$tmp/awtarchy-mango/PowerMenu.qml"
grep -Fq '/mango/scripts/quicksettings.sh' "$tmp/awtarchy-mango/QuickSettings.qml"
if grep -qF 'wait-secure' "$tmp/awtarchy-mango/PowerMenu.qml"; then
    printf 'ERROR: Mango Power Menu still relies on the Hyprland lock readiness helper\n' >&2
    false
fi
grep -Fq 'awtarchy-mango' "$tmp/awtarchy-mango/shell.qml"
if grep -RnE 'import Quickshell.Hyprland|HyprlandFocusGrab|\bhyprctl\b|hl\.dispatch\(' "$tmp/awtarchy-mango" --include='*.qml'; then
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
 config/mango/config.conf
grep -Fq 'app_id:^awtarchy-qalcgrep -Fq 'dev\.vencord\.Vesktop' config/mango/config.conf
[[ $(grep -Fc 'env=XCURSOR_THEME,' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_theme=' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_size=' config/mango/config.conf) == 1 ]]
for script in config/mango/scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile trials/mangowm/render-quickshell.py config/mango/scripts/snapshot.py config/mango/scripts/cursor-variant.py

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
grep -Fq '/mango/scripts/lock.sh' "$tmp/awtarchy-mango/PowerMenu.qml"
grep -Fq '/mango/scripts/quicksettings.sh' "$tmp/awtarchy-mango/QuickSettings.qml"
if grep -qF 'wait-secure' "$tmp/awtarchy-mango/PowerMenu.qml"; then
    printf 'ERROR: Mango Power Menu still relies on the Hyprland lock readiness helper\n' >&2
    false
fi
grep -Fq 'awtarchy-mango' "$tmp/awtarchy-mango/shell.qml"
if grep -RnE 'import Quickshell.Hyprland|HyprlandFocusGrab|\bhyprctl\b|hl\.dispatch\(' "$tmp/awtarchy-mango" --include='*.qml'; then
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
 config/mango/config.conf
grep -Fq 'MANGO_INSTANCE_SIGNATURE' config/hypr/scripts/launch_handler.sh
grep -Fq 'dev\.vencord\.Vesktop' config/mango/config.conf
[[ $(grep -Fc 'env=XCURSOR_THEME,' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_theme=' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_size=' config/mango/config.conf) == 1 ]]
for script in config/mango/scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile trials/mangowm/render-quickshell.py config/mango/scripts/snapshot.py config/mango/scripts/cursor-variant.py

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
grep -Fq '/mango/scripts/lock.sh' "$tmp/awtarchy-mango/PowerMenu.qml"
grep -Fq '/mango/scripts/quicksettings.sh' "$tmp/awtarchy-mango/QuickSettings.qml"
if grep -qF 'wait-secure' "$tmp/awtarchy-mango/PowerMenu.qml"; then
    printf 'ERROR: Mango Power Menu still relies on the Hyprland lock readiness helper\n' >&2
    false
fi
grep -Fq 'awtarchy-mango' "$tmp/awtarchy-mango/shell.qml"
if grep -RnE 'import Quickshell.Hyprland|HyprlandFocusGrab|\bhyprctl\b|hl\.dispatch\(' "$tmp/awtarchy-mango" --include='*.qml'; then
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
