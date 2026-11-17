#!/usr/bin/env python3
"""Install/update/remove only Awtarchy's user-local experimental KWin trial.

No pacman, root, Ly or existing compositor configuration writes. Uninstall
removes only exact files recorded during installation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import sys

FILES = (
    "preflight.sh", "package-plan.sh", "monitor-info.py",
    "prepare-session.py", "tty-smoke.sh", "probe-session.sh",
    "bridge-client.py", "state-bridge.py", "shortcuts.js", "tiling.js",
    "state-publisher.js", "shell.qml",
    "package/metadata.json", "package/tiling-metadata.json",
    "package/state-metadata.json",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe(path: Path) -> None:
    if not path.is_absolute():
        raise ValueError(f"Relative destination refused: {path}")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f"Symlink path refused: {part}")
        if part.exists() and not (part.is_file() or part.is_dir()):
            raise ValueError(f"Special path refused: {part}")


def inventory():
    if os.geteuid() == 0:
        raise ValueError("Run as ordinary user, not with sudo")
    home = Path(os.environ["HOME"])
    data = Path(os.environ.get("XDG_DATA_HOME", str(home / ".local/share")))
    state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state")))
    target = data / "awtarchy-kwin-trial"
    wrapper = home / ".local/bin/kwin"
    manifest = state / "awtarchy" / "kwin-trial-install.json"
    for path in (home, target, wrapper, manifest):
        safe(path)
    source = Path(__file__).resolve().parent
    entries = []
    for name in FILES:
        origin = source / name
        if origin.is_symlink() or not origin.is_file():
            raise ValueError(f"Missing or unsafe source {origin}")
        entries.append((target / name, origin.read_bytes(),
                        0o755 if name == "probe-session.sh" else 0o644))
    origin = source / "tty-command.sh"
    if origin.is_symlink() or not origin.is_file():
        raise ValueError("Missing KWin trial TTY entry")
    entries.append((wrapper, origin.read_bytes(), 0o755))
    return entries, manifest


def read_record(manifest: Path, allowed: set[str]):
    safe(manifest)
    if not manifest.exists():
        return None
    if not manifest.is_file() or manifest.stat().st_uid != os.geteuid():
        raise ValueError("Unsafe trial manifest")
    record = json.loads(manifest.read_text())
    files = record.get("files")
    if record.get("version") != 1 or not isinstance(files, dict) or not set(files) <= allowed:
        raise ValueError("Unrecognized trial manifest")
    if not all(isinstance(value, str) and len(value) == 64
               and all(ch in "0123456789abcdef" for ch in value)
               for value in files.values()):
        raise ValueError("Malformed manifest hash")
    return files


def install(apply: bool):
    entries, manifest = inventory()
    expected = {str(path): digest(data) for path, data, mode in entries}
    previous = read_record(manifest, set(expected))
    if previous is not None and previous != expected:
        raise ValueError("Installed trial differs; refuse unverified upgrade")
    for path, data, mode in entries:
        safe(path)
        if path.exists():
            if previous is None or digest(path.read_bytes()) != expected[str(path)]:
                raise ValueError(f"User-owned or changed target preserved: {path}")
        elif previous is not None:
            raise ValueError(f"Previously installed target missing: {path}")
        else:
            print(f"{'Installing' if apply else 'Would create'}: {path}")
    if not apply:
        print("PLAN ONLY: No files or packages changed")
        return
    if previous is not None:
        print("Exact trial already installed")
        return
    for path, data, mode in entries:
        safe(path)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(path, flags, mode)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(path, mode)
    safe(manifest)
    manifest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(manifest, flags, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write((json.dumps({"version": 1, "files": expected},
                                 sort_keys=True, indent=2) + "\n").encode())
    print("Installed experimental user-local command: kwin")
    print("No official packages, Ly sessions, or other compositors modified")


def update():
    """Refresh an exact, tracked trial in place, preserving recoverable backups.

    If the original package install failed before stage, do a normal install.
    Any local customization or missing managed file blocks the entire update.
    """
    entries, manifest = inventory()
    expected = {str(path): digest(data) for path, data, _ in entries}
    recorded = read_record(manifest, set(expected))
    if recorded is None:
        install(True)
        return
    if set(recorded) != set(expected):
        raise ValueError("Unexpected old trial inventory; refusing upgrade")
    changes = []
    for path, data, mode in entries:
        safe(path)
        if (not path.is_file() or path.stat().st_uid != os.geteuid()
                or not stat.S_ISREG(path.stat().st_mode)):
            raise ValueError(f"Missing/unsafe managed file: {path}")
        old = path.read_bytes()
        if digest(old) != recorded[str(path)]:
            raise ValueError(f"Locally modified trial file preserved: {path}")
        if old != data:
            changes.append((path, old, data, mode))
    if not changes:
        print("Existing KWin trial is already current")
        return

    safe(manifest.parent)
    backup_dir = Path(tempfile.mkdtemp(
        prefix="kwin-trial-upgrade-", dir=manifest.parent))
    os.chmod(backup_dir, 0o700)
    # Back up the exact original bytes and permissions before replacing any
    # trial file. Backups are kept for manual recovery after a power failure.
    for index, (path, old, new, mode) in enumerate(changes):
        archive = backup_dir / f"{index:03d}.original"
        archive.write_bytes(old)
        os.chmod(archive, 0o600)
    old_manifest = manifest.read_bytes()
    archive_manifest = backup_dir / "manifest.original"
    archive_manifest.write_bytes(old_manifest)
    os.chmod(archive_manifest, 0o600)

    def replace_bytes(path: Path, value: bytes, mode: int) -> None:
        safe(path)
        fd, staged_name = tempfile.mkstemp(
            prefix=".kwin-update-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as staged:
                staged.write(value)
            os.chmod(staged_name, mode)
            os.replace(staged_name, path)
        finally:
            if os.path.exists(staged_name):
                os.unlink(staged_name)

    applied = []
    try:
        for path, old, new, mode in changes:
            if path.read_bytes() != old:
                raise ValueError(f"Trial file changed during upgrade: {path}")
            replace_bytes(path, new, mode)
            applied.append((path, old, mode))
        new_manifest = (json.dumps({"version": 1, "files": expected},
                                   sort_keys=True, indent=2) + "\n").encode()
        if manifest.read_bytes() != old_manifest:
            raise ValueError("Trial manifest changed during upgrade")
        replace_bytes(manifest, new_manifest, 0o600)
    except Exception:
        for path, old, mode in reversed(applied):
            try:
                replace_bytes(path, old, mode)
            except OSError:
                print(f"RECOVERY REQUIRED: {path}, backup: {backup_dir}",
                      file=sys.stderr)
        raise
    print(f"Updated {len(changes)} exact KWin trial file(s).")
    print(f"Original files and manifest backed up at: {backup_dir}")
    print("No changes to Ly, Sway, Hyprland or system packages.")


def remove():
    entries, manifest = inventory()
    recorded = read_record(manifest, {str(path) for path, _, _ in entries})
    if recorded is None:
        print("No recorded KWin trial installation")
        return
    remaining = []
    for name, expected in recorded.items():
        path = Path(name)
        safe(path)
        if not path.exists():
            continue
        if path.is_file() and digest(path.read_bytes()) == expected:
            path.unlink()
            print(f"Removed exact trial file: {path}")
        else:
            remaining.append(name)
            print(f"PRESERVE modified trial file: {path}")
    if remaining:
        print("Original manifest retained for reviewing preserved files")
    else:
        manifest.unlink()
        print("Trial removed; installed packages and all other desktops preserved")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--plan", action="store_true")
    actions.add_argument("--install", action="store_true")
    actions.add_argument("--update", action="store_true")
    actions.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    try:
        if args.remove:
            remove()
        elif args.update:
            update()
        else:
            install(args.install)
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"KWin trial: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
