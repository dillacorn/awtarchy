#!/usr/bin/env python3
"""Exercise Jay managed config review, backups and modification preservation."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / "trials/jay/sync.py"
compile(source.read_bytes(), str(source), "exec")
sys.path.insert(0, str(source.parent))
import sync

with tempfile.TemporaryDirectory(prefix="awtarchy-jay-update.") as tmp:
    home = Path(tmp) / "home"
    home.mkdir()
    with tempfile.TemporaryDirectory() as stage:
        staged = sync.expected_files(root, home, Path(stage))
    assert len(staged) >= 55
    for path, body in staged.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)

    environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                       XDG_STATE_HOME=str(home / ".local/state"))
    def run(action):
        return subprocess.run(
            [sys.executable, str(source), action, "--repo", str(root)],
            env=environment, capture_output=True, text=True, timeout=40
        )

    initial = run("record")
    assert initial.returncode == 0, initial.stderr
    baseline_path = home / ".local/state/awtarchy/jay-managed-baseline.json"
    baseline = json.loads(baseline_path.read_text())
    assert len(baseline) >= 55

    custom = home / ".config/quickshell/awtarchy-jay/Bar.qml"
    custom.write_bytes(custom.read_bytes() + b"\n// user-custom-style\n")
    config = home / ".config/jay/config.toml"
    config.write_bytes(config.read_bytes() + b"\n# custom input preference\n")

    # Simulate an older tracked helper: manifest matches installed old bytes,
    # branch source has a new version.
    old = b"#!/bin/bash\n# previous managed release\n"
    target = home / ".config/jay/awtarchy-trial/runtime-rules.sh"
    target.write_bytes(old)
    key = str(target.relative_to(home))
    baseline[key] = hashlib.sha256(old).hexdigest()
    baseline_path.write_text(json.dumps(baseline) + "\n")
    previous_state = baseline_path.read_bytes()

    review = run("review")
    assert review.returncode == 0, review.stderr
    assert "WOULD UPDATE: " + key in review.stdout
    assert "PRESERVE modified file: .config/quickshell/awtarchy-jay/Bar.qml" in review.stdout
    assert target.read_bytes() == old
    assert baseline_path.read_bytes() == previous_state

    apply = run("apply")
    assert apply.returncode == 0, apply.stderr
    assert target.read_bytes() == staged[target]
    assert custom.read_bytes().endswith(b"// user-custom-style\n")
    assert config.read_bytes().endswith(b"# custom input preference\n")
    backups = list(target.parent.glob("runtime-rules.sh.backup-*"))
    assert len(backups) == 1 and backups[0].read_bytes() == old
    rereview = run("review")
    assert rereview.returncode == 0 and "WOULD UPDATE" not in rereview.stdout

print("PASS: Jay managed-source review is read-only and apply preserves custom work")
