#!/usr/bin/env python3
"""Guard the targeted Jay appearance migration and imported monitor state."""
import importlib.util
from pathlib import Path
import stat
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
TRIAL = ROOT / "trials/jay"
SOURCE = TRIAL / "config.toml"
spec = importlib.util.spec_from_file_location("appearance", TRIAL / "repair-first-login-appearance.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

fresh = SOURCE.read_text(encoding="utf-8")
assert fresh.count(module.UPDATED) == 1
assert fresh.count(module.NEW_THEME) == 1
assert fresh.count(module.OLD_THEME) == 0
assert tomllib.loads(fresh)["show-titles"] is False
assert tomllib.loads(fresh)["use-hardware-cursor"] is False
assert tomllib.loads(fresh)["cursor-size"] == 24

legacy = fresh.replace(module.UPDATED, module.ORIGINAL, 1).replace(module.NEW_THEME, module.OLD_THEME, 1)
assert module.migration(legacy.encode()) == fresh.encode()
assert module.migration(fresh.encode()) == fresh.encode()
# Existing imported modes must survive byte for byte, not just semantically.
imported = legacy + '\n[[outputs]]\nmatch.connector = "DP-1"\nmode = { width = 1920, height = 1080, refresh-rate = 400.002 }\nx = 0\ny = 1080\nscale = 1.0\n'
updated = module.migration(imported.encode())
assert updated.decode().endswith(imported[len(legacy):])
assert tomllib.loads(updated.decode())["outputs"][0]["mode"]["refresh-rate"] == 400.002
assert module.migration(updated) == updated

for invalid in (
    legacy.replace("# Awtarchy Jay session (experimental).", "# foreign config"),
    legacy.replace('workspace-display-order = "sorted"', 'workspace-display-order = "manual"'),
    legacy.replace('show-bar = false', 'show-bar = true'),
    legacy.replace('show-bar = false', 'show-bar = false\nuse-hardware-cursor = true'),
):
    try:
        module.migration(invalid.encode())
    except ValueError:
        pass
    else:
        raise AssertionError("Unexpected config accepted for auto migration")

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "config.toml"
    path.write_bytes(imported.encode())
    prior_mode = stat.S_IMODE(path.stat().st_mode)
    backup = module.apply(path, updated, imported.encode(), prior_mode)
    assert path.read_bytes() == updated
    assert backup.read_bytes() == imported.encode()
    assert stat.S_IMODE(path.stat().st_mode) == prior_mode
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600
print("PASS: Jay title/cursor migration, strict guards, monitor preservation and backup")
