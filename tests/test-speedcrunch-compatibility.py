#!/usr/bin/env python3
"""Validate Awtarchy SpeedCrunch theme loading and Hyprland window rules."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
THEMES = ROOT / "config/hypr/themes"
SCHEMES = ROOT / "local/share/SpeedCrunch/color-schemes"
APPLY = ROOT / "config/hypr/scripts/quickshell_theme_apply.sh"

SCHEMA = "https://json-schema.org/draft/2020-12/schema"
SCHEMA_ID = "https://speedcrunch.org/schemas/theme-v1.schema.json"
COLOR_ROLES = {
    "number", "parens", "list", "unit", "result", "comment",
    "function", "operator", "variable", "separator", "background",
}
METADATA = {"$schema", "$id", "name", "author", "homepage", "version", "primary"}

theme_schemes = {}
for theme_file in sorted(THEMES.iterdir()):
    if not theme_file.is_file() or theme_file.name.startswith("."):
        continue
    definition = theme_file.read_text(encoding="utf-8")
    match = re.search(r'^SPEEDCRUNCH_COLORSCHEME="([^"]+)"$', definition, re.M)
    assert match, f"missing SpeedCrunch scheme in {theme_file.name}"
    theme_schemes[theme_file.name] = match.group(1)

assert len(theme_schemes) == 9, f"expected 9 stock themes, got {len(theme_schemes)}"
assert set(theme_schemes.values()) == {p.stem for p in SCHEMES.glob("*.json")}, (
    "bundled SpeedCrunch themes do not match Awtarchy theme selections"
)

for scheme_name in theme_schemes.values():
    path = SCHEMES / f"{scheme_name}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data.get("$schema") == SCHEMA, f"missing schema draft in {path.name}"
    assert data.get("$id") == SCHEMA_ID, f"missing theme schema in {path.name}"
    assert COLOR_ROLES <= data.keys(), f"missing required roles in {path.name}"
    assert data.keys() <= COLOR_ROLES | METADATA, f"unsupported roles in {path.name}"
    for role in COLOR_ROLES | {"primary"}:
        if role in data:
            assert re.fullmatch(r"#[0-9a-fA-F]{6}", data[role]), (
                f"invalid color {role} in {path.name}"
            )

lua = (ROOT / "config/hypr/hyprland.lua").read_text(encoding="utf-8")
class_pattern = r"^org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)$"
for action in ("float", "size", "center"):
    match = f'class = "{class_pattern}"'
    assert any(
        match in line and f"}}, {action} =" in line
        for line in lua.splitlines()
        if "hl.window_rule(" in line
    ), f"missing SpeedCrunch {action} window rule"

assert f"org\\\\.speedcrunch\\\\.(speedcrunch|SpeedCrunch)" in lua, (
    "SpeedCrunch opacity rule does not cover the new window class"
)
window_class_regex = re.compile(class_pattern.replace("\\\\", "\\"))
assert window_class_regex.fullmatch("org.speedcrunch.speedcrunch")
assert window_class_regex.fullmatch("org.speedcrunch.SpeedCrunch")
assert not window_class_regex.fullmatch("org.speedcrunch.Other")

with tempfile.TemporaryDirectory(prefix="awtarchy-speedcrunch-") as temp:
    home = Path(temp)
    config = home / ".config"
    (config / "hypr/themes").mkdir(parents=True)
    (config / "SpeedCrunch").mkdir()
    (config / "hypr/hyprland.lua").write_text(
        'local borders = {\n'
        '    active_border = "rgba(a0a0a0ff)",\n'
        '    inactive_border = "rgba(4b4b4bff)",\n'
        '}\n',
        encoding="utf-8",
    )
    settings = config / "SpeedCrunch/SpeedCrunch.ini"
    shutil.copyfile(ROOT / "config/SpeedCrunch/SpeedCrunch.ini", settings)
    for theme_name in theme_schemes:
        shutil.copyfile(THEMES / theme_name, config / "hypr/themes" / theme_name)

    fakebin = home / "bin"
    fakebin.mkdir()
    for program, status in (("hyprctl", "true"), ("systemctl", "false")):
        stub = fakebin / program
        stub.write_text(f"#!/bin/sh\n{status}\n", encoding="utf-8")
        stub.chmod(0o755)

    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "PATH": f"{fakebin}:{os.environ.get('PATH', '')}",
    }
    for theme_name, scheme_name in sorted(theme_schemes.items()):
        subprocess.run(
            ["bash", str(APPLY), theme_name],
            env=env, check=True, capture_output=True, text=True,
        )
        updated = settings.read_text(encoding="utf-8")
        match = re.search(r"(?m)^Display\\ColorSchemeName=(.*)$", updated)
        assert match and match.group(1) == scheme_name, (
            f"switching {theme_name} selected {match.group(1) if match else 'nothing'} "
            f"instead of {scheme_name}"
        )
        active = (home / ".local/state/awtarchy/active-theme").read_text().strip()
        assert active == theme_name, f"incorrect theme state for {theme_name}"

print("SpeedCrunch compatibility tests passed (9 themes, window rules, switching).")
