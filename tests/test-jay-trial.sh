#!/usr/bin/env bash
# Validate source only: not a proof of a functioning hardware session.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
trial="$root/trials/jay"
for file in setup.sh session.sh capture.sh diagnose.sh application-state.sh cursor-theme.sh position.sh runtime-rules.sh quicksettings.sh lock.sh lock-capture.sh ipc.sh launcher.sh power.sh clipboard.sh notifications.sh quick-settings.sh; do bash -n "$trial/$file"; done
python3 - "$trial" <<'PY'
from pathlib import Path
import sys
import tomllib
base = Path(sys.argv[1])
config = (base / "config.toml").read_text(encoding='utf-8')
data = tomllib.loads(config)
assert data["tearing"]["mode"] == "variant2"
assert data["vrr"]["mode"] == "variant1"
assert data["device-config-filter"] == "all"
assert data["clients"][0]["match"]["tag"] == "awtarchy-jay-shell"
assert data["show-bar"] is False
assert data["on-idle"]["exec"]["privileged"] is True
for mod in ("alt", "logo"):
    for n in range(1, 11):
        key = str(n if n < 10 else 0)
        assert data["shortcuts"][f"{mod}-{key}"]["name"] == str(n)
        assert data["shortcuts"][f"{mod}-shift-{key}"]["name"] == str(n)
assert "# AWTARCHY-JAY-OUTPUTS-BEGIN" in config
assert "# AWTARCHY-JAY-OUTPUTS-END" in config
assert "aur-scan install jay --noconfirm" in (base / "setup.sh").read_text()
assert '*.sh) mode=0755' in (base / "setup.sh").read_text()
assert "hyprctl" not in (base / "session.sh").read_text()
for item in base.glob("*.py"):
    compile(item.read_bytes(), str(item), "exec")
print("PASS: Jay trial syntax and invariants")
PY
