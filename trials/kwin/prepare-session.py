#!/usr/bin/env python3
"""Stage an isolated KWin scripting package for a disposable TTY smoke session.

No global XDG paths, installed services, or existing user configurations are edited.
The caller supplies an already-created, owned, private session root.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import sys

PLUGIN_IDS = ("awtarchy-kwin", "awtarchy-kwin-tiling")
KWINRC = (
    "[Desktops]\n"
    "Number=10\n"
    "Rows=1\n"
    "\n"
    "[Plugins]\n"
    "".join(f"{plugin}Enabled=true\\n" for plugin in PLUGIN_IDS)
)


def fail(message: str) -> None:
    raise ValueError(message)


def safe_directory(path: Path, root: Path) -> None:
    relative = path.relative_to(root)
    for part in (root, *(root.joinpath(*relative.parts[:i])
                         for i in range(1, len(relative.parts) + 1))):
        if part.is_symlink():
            fail(f"Symlink directory refused: {part}")
        if part.exists() and not part.is_dir():
            fail(f"Non-directory in target: {part}")


def plan(root: Path, sources: Path) -> list[tuple[Path, bytes]]:
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        fail("Session root must be an existing, absolute, non-symlink directory")
    if root.stat().st_uid != os.geteuid():
        fail("Session root is not owned by the invoking user")
    if stat.S_IMODE(root.stat().st_mode) & 0o077:
        fail("Session root must be private (mode 0700)")
    contents = [(root / "config" / "kwinrc", KWINRC.encode("utf-8"))]
    scripts = (("awtarchy-kwin", "shortcuts.js", "metadata.json"),
               ("awtarchy-kwin-tiling", "tiling.js", "tiling-metadata.json"))
    for plugin_id, script, metadata in scripts:
        metadata_path = sources / "package" / metadata
        script_path = sources / script
        for file in (metadata_path, script_path):
            if file.is_symlink() or not file.is_file():
                fail(f"Missing or unsafe source: {file}")
        meta = metadata_path.read_bytes()
        info = json.loads(meta)
        if info.get("KPlugin", {}).get("Id") != plugin_id:
            fail("KWin script package ID mismatch")
        if info.get("KPackageStructure") != "KWin/Script" or (
            info.get("X-Plasma-MainScript") != "code/main.js"
        ):
            fail("KWin script package metadata mismatch")
        package = root / "data" / "kwin" / "scripts" / plugin_id
        contents.extend([
            (package / "metadata.json", meta),
            (package / "contents" / "code" / "main.js", script_path.read_bytes()),
        ])
    for target, expected in contents:
        safe_directory(target.parent, root)
        if target.is_symlink():
            fail(f"Symlink file refused: {target}")
        if target.exists():
            if not target.is_file():
                fail(f"Non-regular destination: {target}")
            if target.read_bytes() != expected:
                fail(f"Existing session content differs; preserving: {target}")
    return contents


def run() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path,
                        help="owned private temporary root; no global config writes")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--stage", action="store_true")
    args = parser.parse_args()
    root = args.root
    sources = Path(__file__).resolve().parent
    files = plan(root, sources)
    if args.check:
        for target, _ in files:
            print(f"Would stage (or preserve identical): {target}")
        print("PASS: read-only isolated KWin session plan")
        return 0
    for target, data in files:
        target.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        safe_directory(target.parent, root)
        if target.exists():
            if target.is_symlink() or target.read_bytes() != data:
                fail(f"Concurrent change; refusing: {target}")
            continue
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(target, flags, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        print(f"Staged: {target}")
    print("PASS: isolated KWin script and config staged")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(run())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"KWin session staging: {error}", file=sys.stderr)
        sys.exit(1)
