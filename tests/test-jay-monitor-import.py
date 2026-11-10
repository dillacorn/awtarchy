#!/usr/bin/env python3
"""Monitor importer fixture without starting Hyprland or editing home config."""
import importlib.util
from pathlib import Path
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/jay"
spec = importlib.util.spec_from_file_location("jay_import", TRIAL / "import-hypr-monitors.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = [
    dict(name="DP-1", width=1920, height=1080, refreshRate=240.0, x=0, y=0, scale=1.0),
    dict(name="DP-3", width=1920, height=1080, refreshRate=239.963, x=-1920, y=0, scale=1.0),
]
rows = module.normalize(source)
assert rows == [("DP-1", "1920x1080@240.000", "1920x0", "1.000"),
                ("DP-3", "1920x1080@239.963", "0x0", "1.000")]
with tempfile.TemporaryDirectory() as temp:
    config = Path(temp) / "config.toml"
    config.write_bytes((TRIAL / "config.toml").read_bytes())
    backup = module.apply(rows, config)
    assert backup.read_bytes() == (TRIAL / "config.toml").read_bytes()
    data = tomllib.loads(config.read_text())
    assert data["tearing"]["mode"] == "variant2"
    assert [x["match"]["connector"] for x in data["outputs"]] == ["DP-1", "DP-3"]
    assert [x["x"] for x in data["outputs"]] == [1920, 0]
    try:
        module.apply(rows, config)
    except ValueError:
        pass
    else:
        raise AssertionError("Importer overwrote the existing Jay profile")
for bad in (
    source + [dict(source[0])],
    [dict(source[0], x=0.5)],
    [dict(source[0], scale=0)],
    [dict(source[0], refreshRate=float("nan"))],
    [dict(source[0], disabled=True)],
):
    try:
        module.normalize(bad)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid Hyprland monitor data was accepted")
print("PASS: Jay one-time monitor import, geometry normalization and preservation")
