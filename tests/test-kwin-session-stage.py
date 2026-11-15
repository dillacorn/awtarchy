#!/usr/bin/env python3
"""Offline isolated KWin package staging: idempotence, no writes in plan, fail closed."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "trials/kwin/prepare-session.py"
PLUGIN = ROOT / "trials/kwin/package/metadata.json"
SOURCE = ROOT / "trials/kwin/shortcuts.js"
TILING = ROOT / "trials/kwin/tiling.js"

metadata = json.loads(PLUGIN.read_text(encoding="utf-8"))
assert metadata["KPlugin"]["Id"] == "awtarchy-kwin"
assert metadata["X-Plasma-API"] == "javascript"
assert metadata["KPackageStructure"] == "KWin/Script"
assert metadata["X-Plasma-MainScript"] == "code/main.js"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory(prefix="awtarchy-kwin-test-") as directory:
    base = Path(directory)
    root = base / "private"
    root.mkdir(mode=0o700)
    sibling = base / "untouched"
    sibling.write_text("preserve", encoding="utf-8")

    def run(*args, expected=0):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(root), *args],
            text=True, capture_output=True, timeout=15
        )
        assert (result.returncode == 0) == (expected == 0), (
            args, result.returncode, result.stdout, result.stderr
        )
        return result

    run("--check")
    assert list(root.iterdir()) == [], "Read-only plan wrote files"
    run("--stage")
    config = root / "config" / "kwinrc"
    installed = root / "data/kwin/scripts/awtarchy-kwin/contents/code/main.js"
    assert sha(installed) == sha(SOURCE)
    tiling = root / "data/kwin/scripts/awtarchy-kwin-tiling/contents/code/main.js"
    assert sha(tiling) == sha(TILING)
    assert "Number=10" in config.read_text()
    assert "awtarchy-kwinEnabled=true" in config.read_text()
    assert "awtarchy-kwin-tilingEnabled=true" in config.read_text()
    assert config.read_text().splitlines().count("awtarchy-kwinEnabled=true") == 1
    assert config.read_text().splitlines().count("awtarchy-kwin-tilingEnabled=true") == 1
    recorded = {config: sha(config), installed: sha(installed), tiling: sha(tiling)}
    run("--stage")
    assert recorded == {path: sha(path) for path in recorded}
    assert sibling.read_text(encoding="utf-8") == "preserve"

    config.write_text("custom user content\n")
    run("--check", expected=1)
    run("--stage", expected=1)
    assert config.read_text() == "custom user content\n"
    assert sha(installed) == sha(SOURCE)

    # A symlink in a fresh directory must never be followed or rewritten.
    symlink_root = base / "symlink-private"
    symlink_root.mkdir(mode=0o700)
    (symlink_root / "config").symlink_to(base)
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(symlink_root), "--stage"],
        capture_output=True, text=True
    )
    assert result.returncode != 0
    assert sibling.read_text(encoding="utf-8") == "preserve"

print("PASS: KWin session package, 10 desktops, read-only check, collision safety")
