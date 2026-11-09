#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

bash -n local/share/awtarchy/awtarchy-runtime.sh
bash -n local/share/awtarchy/awtarchy-package-reconcile.sh
bash -n local/bin/awtarchy
# Both stages of the updater's plan validation must accept the Mango
# managed namespace. A shell-only allowlist is insufficient.
python3 - <<'PY'
from pathlib import Path
runtime = Path("local/share/awtarchy/awtarchy-runtime.sh").read_text()
shell_validator = runtime.split("validate_managed_relative_path() {", 1)[1].split("\n}", 1)[0]
python_plan = runtime.split("build_plan() {", 1)[1].split("\ndef valid_rel(raw):", 1)[0]
assert ".config/mango/*" in shell_validator
assert '"mango"' in python_plan.split("CONFIG_ROOTS = {", 1)[1].split("}", 1)[0]
assert 'render_mango_quickshell_target "$repo_dir" "$target_home"' in runtime
print("PASS: Mango managed namespace admitted by plan and apply validators")
PY

test -s config/xdg-desktop-portal/mango-portals.conf
grep -Fqx 'org.freedesktop.impl.portal.ScreenCast=wlr' config/xdg-desktop-portal/mango-portals.conf
grep -Fqx 'org.freedesktop.impl.portal.Screenshot=wlr' config/xdg-desktop-portal/mango-portals.conf
grep -Fq 'shield_when_capture:1,app_id:' config/mango/config.conf
grep -Fq 'app_id:^awtarchy-default-apps$' config/mango/config.conf
grep -Fq 'app_id:^awtarchy-qalc$' config/mango/config.conf
grep -Fq 'MANGO_INSTANCE_SIGNATURE' config/hypr/scripts/launch_handler.sh
grep -Fq 'dev\.vencord\.Vesktop' config/mango/config.conf
[[ $(grep -Fc 'env=XCURSOR_THEME,' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_theme=' config/mango/config.conf) == 1 ]]
[[ $(grep -Fc 'cursor_size=' config/mango/config.conf) == 1 ]]

for script in config/mango/scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile trials/mangowm/render-quickshell.py \
    config/mango/scripts/snapshot.py config/mango/scripts/cursor-variant.py \
    config/mango/scripts/launch-handler.py config/mango/scripts/idle-ipc-compat.py

# Separate generated Quickshell profile must be completely read-only with
# respect to the Hyprland source tree and remain within a temporary root.
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
grep -Fq 'awtarchy-mango' "$tmp/awtarchy-mango/shell.qml"
grep -Fq 'static capture shielding' "$tmp/awtarchy-mango/ScreenShareGuardCard.qml"
if grep -Eq 'screenshare_guard.sh|onClicked:|actionRunner|statusReader' \
    "$tmp/awtarchy-mango/ScreenShareGuardCard.qml"; then
    printf 'ERROR: Mango Screen Share Guard still exposes an unsafe Hyprland-only action\n' >&2
    false
fi

if grep -qF 'wait-secure' "$tmp/awtarchy-mango/PowerMenu.qml"; then
    printf 'ERROR: Mango Power Menu still relies on the Hyprland lock readiness helper\n' >&2
    false
fi
if grep -RnE --include='*.qml' \
    'import Quickshell.Hyprland|HyprlandFocusGrab|\bhyprctl\b|hl\.dispatch\(' \
    "$tmp/awtarchy-mango"; then
    printf 'ERROR: unported Hyprland QML references in Mango profile\n' >&2
    false
fi

# An attempt at a second profile must never overwrite the earlier output.
if python3 trials/mangowm/render-quickshell.py \
    --source config/quickshell/awtarchy \
    --dest "$tmp/awtarchy-mango" \
    --bridge-dir trials/mangowm; then
    printf 'ERROR: profile renderer overwrote an existing profile\n' >&2
    false
fi
printf 'PASS: Mango managed staging syntax and profile isolation\n'
