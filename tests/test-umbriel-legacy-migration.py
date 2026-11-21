#!/usr/bin/env python3
"""Exercise one-time migration of a managed Umbriel trial without losing custom files."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("umbriel_sync_legacy", ROOT / "compositors/umbriel/sync.py")
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)

with tempfile.TemporaryDirectory(prefix="umbriel-release-migration-") as temp:
    home = Path(temp) / "home"
    home.mkdir()
    with patch.object(sync.os, "geteuid", return_value=1000) if os.geteuid() == 0 else patch.object(sync.os, "geteuid", wraps=os.geteuid):
        # Establish the actual managed structure and its hashes first.
        sync.reconcile(ROOT, home, "apply")
        new_dir = home / ".config/umbriel/awtarchy"
        old_dir = home / ".config/umbriel/awtarchy-trial"
        new_state = home / ".local/state/awtarchy/umbriel-managed-baseline.json"
        old_state = home / ".local/state/awtarchy/umbriel-trial-baseline.json"
        native = home / ".config/umbriel/config.toml"
        original_hashes = json.loads(new_state.read_text())["hashes"]
        new_dir.rename(old_dir)
        native.write_bytes(native.read_bytes().replace(b"awtarchy/", b"awtarchy-trial/"))
        legacy_hashes = {}
        for key, value in original_hashes.items():
            legacy_hashes[key.replace(".config/umbriel/awtarchy/", ".config/umbriel/awtarchy-trial/")] = value
        legacy_hashes[".config/umbriel/config.toml"] = hashlib.sha256(native.read_bytes()).hexdigest()
        for file in old_dir.iterdir():
            if file.suffix != ".mp3" and file.is_file():
                data = file.read_bytes()
                changed = data.replace(b"umbriel/awtarchy", b"umbriel/awtarchy-trial")
                if changed != data:
                    file.write_bytes(changed)
                    rel = str(file.relative_to(home))
                    legacy_hashes[rel] = hashlib.sha256(changed).hexdigest()
        old_state.write_text(json.dumps({"version": 1, "hashes": legacy_hashes}))
        new_state.unlink()
        # Customized legacy script must be copied but not added to a managed baseline.
        edited = old_dir / "awtwall.sh"
        edited.write_bytes(edited.read_bytes() + b"\n# PERSONAL EDIT\n")
        sync.reconcile(ROOT, home, "preview")
        assert not new_dir.exists() and not new_state.exists()
        sync.reconcile(ROOT, home, "apply")
        assert native.read_bytes() == (ROOT / "compositors/umbriel/native-config.toml").read_bytes()
        assert (new_dir / "awtwall.sh").read_bytes().endswith(b"# PERSONAL EDIT\n")
        assert edited.read_bytes().endswith(b"# PERSONAL EDIT\n")
        assert old_dir.is_dir() and old_state.is_file()
        baseline = json.loads(new_state.read_text())["hashes"]
        assert ".config/umbriel/awtarchy/awtwall.sh" not in baseline
        tty = home / ".local/bin/umbriel"
        assert tty.read_bytes() == (ROOT / "compositors/umbriel/tty-launch.sh").read_bytes()
        assert tty.stat().st_mode & stat.S_IXUSR
        # Repeat after adoption; stale old personalization cannot override active files.
        sync.reconcile(ROOT, home, "apply")
        assert (new_dir / "awtwall.sh").read_bytes().endswith(b"# PERSONAL EDIT\n")

print("PASS: Umbriel release migration preserves legacy personal files, native config and TTY permissions")
