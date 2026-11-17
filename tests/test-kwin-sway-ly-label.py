#!/usr/bin/env python3
"""Sway Ly label transform leaves everything besides Name= untouched."""
import importlib.util
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "trials/kwin/sway-ly-label.py"
spec = importlib.util.spec_from_file_location("sway_ly_label", p)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

base = ("[Desktop Entry]\n"
        "Name=Sway (Awtarchy Trial)\n"
        "Comment=Keep my Sway environment\n"
        "Exec=/usr/local/bin/awtarchy-sway-session\n"
        "Type=Application\n"
        "DesktopNames=sway\n")
after = mod.renamed(base)
assert after == base.replace("Name=Sway (Awtarchy Trial)", "Name=Sway")
assert mod.renamed(after) == after
for name in ("Sway (Awtarchy)", "Sway (Awtarchy trial)"):
    assert "Name=Sway\n" in mod.renamed(base.replace(
        "Sway (Awtarchy Trial)", name))
for invalid in (
    base.replace("Exec=/usr/local/bin/awtarchy-sway-session", "Exec=/bin/bash -c garbage"),
    base.replace("Name=Sway (Awtarchy Trial)", "Name=Plasma"),
    base + "Name=Another\n",
    base + "Name[en_US]=Someother\n",
    base.replace("DesktopNames=sway", "DesktopNames=Hyprland"),
):
    try:
        mod.renamed(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError("Unexpected Sway desktop accepted")
print("PASS: exact Sway Ly label change; other fields preserved")
