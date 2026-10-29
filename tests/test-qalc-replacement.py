#!/usr/bin/env python3
"""Qalc launcher, multi-instance behavior and preserved-config migration."""

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / "config/hypr/hyprland.lua"
RUNTIME = ROOT / "local/share/awtarchy/awtarchy-runtime.sh"
MIGRATOR = ROOT / "local/share/awtarchy/migrate-qalc-hyprland.py"
lua = LUA.read_text(encoding="utf-8")
runtime = RUNTIME.read_text(encoding="utf-8")
new_command = 'local calculator = "foot --app-id awtarchy-qalc --title Qalc qalc -s \'autocalc on\'"'

assert new_command in lua
assert lua.count('"ALT + SHIFT + C", calculator') == 2
assert lua.count('"SUPER + SHIFT + C", calculator') == 2
assert '"SUPER + ALT + C", hl.dsp.exec_cmd(calculator)' in lua
assert "launch_handler.sh awtarchy-qalc" not in lua
assert 'gvfs-afc libqalculate imagemagick' in runtime
assert 'ensure_qalc_for_target "$target_home"' in runtime
assert 'migrate_qalc_hyprland "$repo_dir" "$target_home"' in runtime
for action in ("float = true", "size = { 347, 510 }", "center = true"):
    assert any('class = "^awtarchy-qalc$"' in line and action in line
               for line in lua.splitlines())
assert "speedcrunch_scheme=" not in (ROOT / "config/hypr/scripts/quickshell_theme_apply.sh").read_text()
assert '"speedcrunch":' not in (ROOT / "config/hypr/scripts/quickshell_theme_catalog.sh").read_text()

old_class = r'class = "^org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)$"'
stock_rules = [
    f'hl.window_rule({{ match = {{ {old_class} }}, float = true }})',
    f'hl.window_rule({{ match = {{ {old_class} }}, size = {{ 347, 510 }} }})',
    f'hl.window_rule({{ match = {{ {old_class} }}, center = true }})',
]
with tempfile.TemporaryDirectory(prefix="qalc-test-") as tmp:
    root = Path(tmp)
    live, output = root / "live.lua", root / "output.lua"
    old = lua.replace(new_command, 'local calculator = "speedcrunch"')
    old = "\n".join(line for line in old.splitlines()
                    if 'class = "^awtarchy-qalc$"' not in line) + "\n"
    old += "\n".join(stock_rules) + "\n-- preserve custom comment\n"
    live.write_text(old, encoding="utf-8")
    subprocess.run(["python3", str(MIGRATOR), str(live), str(LUA), str(output)],
                   check=True, capture_output=True, text=True)
    result = output.read_text(encoding="utf-8")
    assert new_command in result
    assert "-- preserve custom comment" in result
    assert all(rule not in result for rule in stock_rules)
    assert result.count('class = "^awtarchy-qalc$"') == 3
    live.write_text(result, encoding="utf-8")
    output.unlink()
    subprocess.run(["python3", str(MIGRATOR), str(live), str(LUA), str(output)],
                   check=True, capture_output=True, text=True)
    assert not output.exists(), "migration must be idempotent"
    custom = old.replace('local calculator = "speedcrunch"',
                         'local calculator = "custom-calc"')
    live.write_text(custom, encoding="utf-8")
    subprocess.run(["python3", str(MIGRATOR), str(live), str(LUA), str(output)],
                   check=True, capture_output=True, text=True)
    assert 'local calculator = "custom-calc"' in output.read_text()

print("PASS: Qalc launch rules and preserved configuration migration")
