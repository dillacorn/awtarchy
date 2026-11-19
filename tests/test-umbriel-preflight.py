#!/usr/bin/env python3
"""Offline contract for Umbriel read-only discovery."""
from __future__ import annotations
import contextlib
import importlib.util
import io
from pathlib import Path
import os
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parents[1] / "trials/umbriel/preflight.py"
spec = importlib.util.spec_from_file_location("awtarchy_umbriel_preflight", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cards = root / "drm"
    cards.mkdir()
    for name, vendor in (("card0", "0x1002"), ("card1", "0x10de"),
                         ("card12", "0x8086"), ("renderD128", "0x10de")):
        node = cards / name / "device"
        node.mkdir(parents=True)
        (node / "vendor").write_text(vendor + "\n", encoding="ascii")
    (cards / "card3").mkdir()
    assert module.gpu_cards(cards) == [
        ("card0", "AMD"), ("card1", "NVIDIA"), ("card12", "Intel")
    ]
    sessions = root / "sessions"
    sessions.mkdir()
    (sessions / "awtarchy-sway.desktop").write_text(
        "[Desktop Entry]\nName=Sway\nExec=/path/to/preserved-session\n"
    )
    (sessions / "custom.desktop").symlink_to("awtarchy-sway.desktop")
    assert module.session_entries(sessions) == [
        ("awtarchy-sway.desktop", "Sway")
    ]

    # Test actual CLI output with a fake pacman: calls are read-only -Si/-Qq.
    stub = root / "pacman"
    audit = root / "audit"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        "printf '%s\\n' \"$*\" >> \"$UMB_AUDIT\"\n"
        "[[ \"$1\" == -Si && \"$3\" == umbriel ]]\n"
    )
    stub.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = str(root) + os.pathsep + env.get("PATH", "")
    env["UMB_AUDIT"] = str(audit)
    proc = subprocess.run(
        [sys.executable, str(source), "--sysfs-root", str(cards),
         "--session-dir", str(sessions)],
        capture_output=True, text=True, env=env, timeout=10
    )
    assert proc.returncode == 0, proc.stderr
    assert "card0: AMD" in proc.stdout
    assert "card1: NVIDIA" in proc.stdout
    assert "umbriel: repository=yes, installed=no" in proc.stdout
    assert "No installation, configuration, or Ly changes" in proc.stdout
    assert "awtarchy-sway.desktop: Sway" in proc.stdout
    for line in audit.read_text().splitlines():
        assert line.startswith("-Si -- ") or line.startswith("-Qq -- "), line

print("PASS: Umbriel preflight reads package metadata and GPU/session state only")
