#!/usr/bin/env python3
"""Guard Jay btop Foot floating rule and the installed-config migration."""
import importlib.util
from pathlib import Path
import stat
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/jay"
spec = importlib.util.spec_from_file_location("btop_migrate", TRIAL / "repair-btop-floating.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

source = (TRIAL / "config.toml").read_bytes()
data = tomllib.loads(source.decode())
assert data["shortcuts"]["alt-shift-b"]["exec"]["exec"] == [
    "foot", "--app-id", "btop", "btop"
]
assert data["shortcuts"]["logo-shift-b"]["exec"]["exec"] == [
    "foot", "--app-id", "btop", "btop"
]
rules = [r for r in data["windows"] if r.get("match", {}).get("app-id") == "btop"]
assert len(rules) == 1
assert rules[0]["initial-tile-state"] == "floating"
assert rules[0]["initial-floating-size"] == {"width": 1536, "height": 918}

legacy = source.decode().split("# btop in Foot uses --app-id btop")[0]
# Preserve the subsequent window rules and all previously imported monitor settings.
suffix = source.decode().split("# Quickshell's individual floating utility surfaces")[1]
legacy += "# Quickshell's individual floating utility surfaces" + suffix
assert not any(r.get("match", {}).get("app-id") == "btop"
               for r in tomllib.loads(legacy)["windows"])
imported = legacy + (
    '\n[[outputs]]\nmatch.connector = "DP-1"\n'
    "mode = { width = 1920, height = 1080, refresh-rate = 400.002 }\n"
    "x = 0\ny = 1080\nscale = 1.0\n"
)
out = mod.updated_bytes(imported.encode())
parsed = tomllib.loads(out.decode())
assert parsed["outputs"] == tomllib.loads(imported)["outputs"]
assert out.startswith(imported.encode())
assert mod.updated_bytes(out) == out

for invalid in (
    imported.replace("# Awtarchy Jay session (experimental).", "# unrelated config"),
    imported + '\n[[windows]]\nmatch.app-id = "btop"\ninitial-tile-state = "tiled"\n',
):
    try:
        mod.updated_bytes(invalid.encode())
    except ValueError:
        pass
    else:
        raise AssertionError("Modified or unknown Jay settings were unexpectedly accepted")

# Exercise atomic migration helper on a disposable destination.
appearance_spec = importlib.util.spec_from_file_location(
    "appearance", TRIAL / "repair-first-login-appearance.py"
)
appearance = importlib.util.module_from_spec(appearance_spec)
appearance_spec.loader.exec_module(appearance)
with tempfile.TemporaryDirectory(prefix="jay-btop-test-") as tmp:
    path = Path(tmp) / "config.toml"
    path.write_bytes(imported.encode())
    original_mode = stat.S_IMODE(path.stat().st_mode)
    backup = appearance.apply(path, out, imported.encode(), original_mode)
    assert backup.read_bytes() == imported.encode()
    assert path.read_bytes() == out
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600
    assert stat.S_IMODE(path.stat().st_mode) == original_mode

print("PASS: Jay btop rule, preserved monitors, idempotence, customized rules and backups")
