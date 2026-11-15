#!/usr/bin/env python3
"""Isolated XDG directory MIME reconciliation regression tests.

No host MIME associations or real application defaults are changed.
"""
import importlib.util
import os
from pathlib import Path
from unittest.mock import patch
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "trials/sway/mime-parity.py"
spec = importlib.util.spec_from_file_location("mime_parity", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="sway-mime-parity-") as directory:
    home = Path(directory)
    config = home / "config"
    config.mkdir()
    data = home / "share"
    applications = data / "applications"
    applications.mkdir(parents=True)
    (applications / "pcmanfm-qt.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=PCManFM-Qt\n"
        "Exec=pcmanfm-qt %U\nMimeType=inode/directory;\n"
    )
    bins = home / "bin"
    bins.mkdir()
    executable = bins / "pcmanfm-qt"
    executable.write_text("#!/usr/bin/env sh\ntrue\n")
    executable.chmod(0o755)
    (config / "awtarchy").mkdir()
    (config / "awtarchy/default-applications.json").write_text(
        '{"file-manager":"pcmanfm-qt","terminal":"foot"}\n')
    mime = config / "mimeapps.list"
    before = (
        "# Keep this comment and every unrelated MIME association.\n"
        "[Default Applications]\n"
        "text/plain=org.example.Editor.desktop;\n"
        "inode/directory=org.example.Other.desktop;\n"
        "\n[Added Associations]\n"
        "application/pdf=org.example.Viewer.desktop;\n"
    )
    mime.write_text(before)
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_DATA_HOME": str(data),
        "XDG_DATA_DIRS": str(home / "empty-data"),
        "PATH": str(bins) + os.pathsep + env.get("PATH", ""),
    })

    with patch.dict(os.environ, env, clear=True), patch.object(
        module.os, "geteuid", return_value=1000
    ):
        with patch.object(sys, "argv", ["mime-parity.py", "review"]):
            module.main()
        assert mime.read_text() == before, "review must be read-only"
        with patch.object(sys, "argv", ["mime-parity.py", "apply"]):
            module.main()
        expected = before.replace(
            "inode/directory=org.example.Other.desktop;",
            "inode/directory=pcmanfm-qt.desktop;",
        )
        assert mime.read_text() == expected
        backups = list(config.glob("mimeapps.list.backup-*"))
        assert len(backups) == 1 and backups[0].read_text() == before
        with patch.object(sys, "argv", ["mime-parity.py", "apply"]):
            module.main()
        assert len(list(config.glob("mimeapps.list.backup-*"))) == 1, (
            "idempotent updates must not make redundant backups")

        # An explicit desktop-specific Sway preference outranks the generic
        # file. Never change unknown user overrides just to force matching.
        sway_override = config / "sway-mimeapps.list"
        sway_override.write_text(
            "[Default Applications]\ninode/directory=org.example.Custom.desktop;\n"
        )
        mime.write_text(before)
        try:
            with patch.object(sys, "argv", ["mime-parity.py", "apply"]):
                module.main()
        except ValueError as exc:
            assert "preserving" in str(exc)
        else:
            raise AssertionError("Sway-specific override was ignored")
        assert mime.read_text() == before
        sway_override.unlink()

        # Refuse unknown duplicated entries, rather than mutating an
        # ambiguous personalized MIME document.
        duplicate = (
            "[Default Applications]\ninode/directory=one.desktop;\n"
            "inode/directory=two.desktop;\n"
        )
        try:
            module.proposed_content(duplicate, "pcmanfm-qt.desktop")
        except ValueError:
            pass
        else:
            raise AssertionError("Duplicate MIME defaults were overwritten")

        # Symlink attacks must never modify the destination.
        protected = config / "original"
        protected.write_text("untouched")
        mime.unlink()
        mime.symlink_to(protected)
        try:
            with patch.object(sys, "argv", ["mime-parity.py", "apply"]):
                module.main()
        except ValueError:
            pass
        else:
            raise AssertionError("Symlinked MIME settings were overwritten")
        assert protected.read_text() == "untouched"

print("PASS: Sway directory MIME reconciliation preserves unrelated user settings")
