#!/usr/bin/env python3
"""Safely migrate the first Jay trial's local title/cursor settings.

Jay's installed config contains an imported display profile and is intentionally
not overwritten by the managed file updater. This migration changes only the
original, known-bad appearance settings and preserves the display block.
"""
import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import stat
import sys
import tempfile
import tomllib

ORIGINAL = 'workspace-display-order = "sorted"\nshow-bar = false\nwindow-management-key = "Super_L"'
UPDATED = (
    'workspace-display-order = "sorted"\n'
    'show-bar = false\n'
    'show-titles = false   # Jay compositor titles, not application-side decorations.\n'
    'use-hardware-cursor = false  # Trial workaround for missing AMD hardware pointer.\n'
    'cursor-size = 24\n'
    'window-management-key = "Super_L"'
)
OLD_THEME = '[theme]\nbar-position = "top"\ncontainer-borders = "full-smart"\nborder-width = 1\nshow-titles = false'
NEW_THEME = '[theme]\nbar-position = "top"\ncontainer-borders = "full-smart"\nborder-width = 1'


def migration(data: bytes) -> bytes:
    body = data.decode("utf-8")
    current = tomllib.loads(body)
    # A second application must be a no-op, including preserving any later
    # custom changes to other settings.
    if current.get("show-titles") is False and current.get("use-hardware-cursor") is False and current.get("cursor-size") == 24 and "show-titles" not in current.get("theme", {}):
        return data
    if "# Awtarchy Jay session (experimental)." not in body:
        raise ValueError("Unrecognized Jay config; refusing to modify it")
    if body.count(ORIGINAL) != 1 or body.count(OLD_THEME) != 1:
        raise ValueError("Installed Jay settings differ from the original trial; merge manually")
    if any(k in current for k in ("show-titles", "cursor-size", "use-hardware-cursor")):
        raise ValueError("Existing custom title/cursor setting; refusing to overwrite")
    updated = body.replace(ORIGINAL, UPDATED, 1).replace(OLD_THEME, NEW_THEME, 1)
    parsed = tomllib.loads(updated)
    if parsed.get("show-titles") is not False or parsed.get("use-hardware-cursor") is not False or parsed.get("cursor-size") != 24:
        raise ValueError("Migration failed TOML validation")
    if parsed.get("outputs") != current.get("outputs"):
        raise ValueError("Monitor profile changed unexpectedly; refusing to write")
    return updated.encode("utf-8")


def apply(path: Path, changed: bytes, original: bytes, mode: int) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    backup = path.with_name(path.name + ".backup-" + stamp)
    with backup.open("xb") as handle:
        os.chmod(backup, 0o600)
        handle.write(original)
        handle.flush()
        os.fsync(handle.fileno())
    name = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".jay-appearance-", delete=False) as temp:
            name = temp.name
            temp.write(changed)
            temp.flush()
            os.fsync(temp.fileno())
        os.chmod(name, mode)
        # A local edit between preview and replacement must not be discarded.
        if path.read_bytes() != original:
            raise ValueError("Jay config changed during migration; backup retained")
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)
    return backup


def main():
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preview", action="store_true")
    action.add_argument("--apply", action="store_true")
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "jay/config.toml")
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run as normal user, not root")
    path = args.config
    if path.is_symlink() or path.parent.is_symlink() or not path.is_file():
        raise ValueError("Missing or unsafe Jay config: " + str(path))
    details = path.stat()
    if not stat.S_ISREG(details.st_mode) or details.st_uid != os.geteuid() or details.st_nlink != 1:
        raise ValueError("Jay config must be a singly linked regular file owned by current user")
    original = path.read_bytes()
    changed = migration(original)
    if changed == original:
        print("Jay appearance settings already migrated; no changes")
        return
    if args.preview:
        print("WOULD UPDATE: root-level show-titles=false, cursor-size=24, use-hardware-cursor=false")
        print("Preserve all monitor overrides, bindings, and other settings; --apply backs up config.toml")
        return
    backup = apply(path, changed, original, stat.S_IMODE(details.st_mode))
    if path.read_bytes() != changed:
        raise ValueError("Jay appearance migration did not verify; inspect backup " + str(backup))
    print("PASS: Jay appearance adjusted; saved backup: " + str(backup))
    print("Sign out and return to the Jay trial to test the cursor and title bars.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError, tomllib.TOMLDecodeError) as error:
        print("Jay appearance migration: " + str(error), file=sys.stderr)
        sys.exit(1)
