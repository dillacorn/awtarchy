#!/usr/bin/env python3
"""Install/remove only Awtarchy's user-local experimental KWin trial.

No pacman, root, Ly or existing compositor configuration writes. Uninstall
removes only exact files recorded during installation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
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
    actions.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    try:
        if args.remove:
            remove()
        else:
            install(args.install)
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"KWin trial: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
