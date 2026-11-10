#!/usr/bin/env python3
"""Stage only missing Hyprland/Awtarchy desktop files without touching user edits.

Shared Awtarchy shell is sourced from the exact selected Jay trial checkout.
No sudo, package management, or compositor restart is performed here.
"""
import argparse
import os
from pathlib import Path
import stat
import sys
import tempfile

def source_plan(repo: Path, home: Path):
    pairs = (
        (repo / "config/hypr", home / ".config/hypr"),
        (repo / "config/quickshell/awtarchy", home / ".config/quickshell/awtarchy"),
    )
    result = []
    for src_root, dest_root in pairs:
        if not src_root.is_dir() or src_root.is_symlink():
            raise ValueError(f"Missing or linked source tree: {src_root}")
        for src in sorted(src_root.rglob("*")):
            if src.is_symlink() or not (src.is_dir() or src.is_file()):
                raise ValueError(f"Invalid source tree entry: {src}")
            dest = dest_root / src.relative_to(src_root)
            result.append((src, dest))
    # Validate every destination type and every ancestor before making writes.
    for _, dest_root in pairs:
        result.append((None, dest_root))
    for src, dest in result:
        path = dest
        while path != home.parent:
            if path.is_symlink():
                raise ValueError(f"Refusing symlinked destination: {path}")
            if path == home:
                break
            path = path.parent
        if dest.exists():
            want_dir = src is None or src.is_dir()
            if (want_dir and not dest.is_dir()) or (not want_dir and not dest.is_file()):
                raise ValueError(f"Conflicting existing path: {dest}")
    return result

def atomic_create_file(src: Path, dest: Path):
    # Build a complete file in the destination filesystem, then link it into
    # place only if absent. os.link does not replace an existing user file.
    fd, temporary = tempfile.mkstemp(prefix=".awtarchy-hypr-stage-", dir=dest.parent)
    try:
        with os.fdopen(fd, "wb") as output, src.open("rb") as input_file:
            while True:
                data = input_file.read(256 * 1024)
                if not data:
                    break
                output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.S_IMODE(src.stat().st_mode))
        os.link(temporary, dest)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def stage(repo: Path, home: Path, apply: bool):
    planned = source_plan(repo, home)
    created = 0
    kept = 0
    for src, dest in sorted(planned, key=lambda pair: (len(pair[1].parts), str(pair[1]))):
        is_dir = src is None or src.is_dir()
        if dest.exists():
            if not is_dir:
                kept += 1
            continue
        print(("CREATE " if apply else "WOULD CREATE ") + str(dest.relative_to(home)))
        if apply:
            if is_dir:
                dest.mkdir(mode=0o755)
            else:
                atomic_create_file(src, dest)
        created += 1
    print(f"Hyprland support files: {created} new paths, {kept} existing files retained")
    return created

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--preview", action="store_true")
    group.add_argument("--apply", action="store_true")
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run as your normal desktop user")
    home = Path.home().resolve()
    repo = args.repo.resolve()
    if not (repo / "trials/jay/setup.sh").is_file():
        raise ValueError("Missing exact Jay trial checkout")
    stage(repo, home, apply=args.apply)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print("Hyprland staging: " + str(error), file=sys.stderr)
        sys.exit(1)
