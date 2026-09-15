#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('tests/test-quickshell-lockscreen-migration.sh')
text = path.read_text()
old = '''require_text "$HYPRLAND" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' \\
    'cutover target lost the SUPER + P power-menu bind'
'''
new = '''require_text "$HYPRLAND" 'hl.bind("SUPER + P", function()' \\
    'cutover target lost the SUPER + P power-menu bind'
require_text "$HYPRLAND" 'hl.dispatch(hl.dsp.submap("power-menu-fast"))' \\
    'cutover target does not arm compositor-owned Power Menu input first'
require_order "$HYPRLAND" \\
    'hl.dispatch(hl.dsp.submap("power-menu-fast"))' \\
    'hl.dispatch(hl.dsp.exec_cmd(power_menu))' \\
    'cutover target launches Power Menu before compositor key ownership'
'''
assert text.count(old) == 1, text.count(old)
path.write_text(text.replace(old, new, 1))

path = Path('tests/test-flyout-runtime-centering.sh')
text = path.read_text()
old = '''assert_count "$HYPR" 'hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})' 2 \\
    'SUPER+P power-menu binding changed unexpectedly'
'''
new = '''assert_count "$HYPR" 'hl.bind("SUPER + P", function()' 2 \\
    'SUPER+P power-menu binding changed unexpectedly'
assert_count "$HYPR" 'hl.dispatch(hl.dsp.submap("power-menu-fast"))' 1 \\
    'default SUPER+P no longer arms compositor-owned input'
assert_count "$HYPR" 'hl.dispatch(hl.dsp.submap("power-menu-fast-noalt"))' 1 \\
    'noalt SUPER+P no longer arms compositor-owned input'
'''
assert text.count(old) == 1, text.count(old)
path.write_text(text.replace(old, new, 1))
PY
