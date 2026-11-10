#!/usr/bin/env python3
"""Preview/apply Jay code updates without replacing personalized TOML or QML."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

def sha(data):
    return hashlib.sha256(data).hexdigest()

def expected_files(repo, home, temporary):
    trial = repo / "trials/jay"
    script = (trial / "setup.sh").read_text(encoding="utf-8")
    m = re.search(r"^sources=\(([^)]*)\)$", script, flags=re.MULTILINE)
    if not m:
        raise ValueError("Jay setup source manifest is unavailable")
    sources = shlex.split(m.group(1))
    if "config.toml" not in sources or "jay-portals.conf" not in sources:
        raise ValueError("Jay managed source inventory changed")
    result = {}
    for name in sources:
        if "/" in name or not re.fullmatch(r"[a-zA-Z0-9._-]+", name):
            raise ValueError("Unsafe Jay source name")
        target = (
            home / ".config/jay/config.toml" if name == "config.toml" else
            home / ".config/xdg-desktop-portal/jay-portals.conf" if name == "jay-portals.conf" else
            home / ".config/jay/awtarchy-trial" / name
        )
        source = trial / name
        if source.is_symlink() or not source.is_file():
            raise ValueError("Unsafe Jay source file: " + str(source))
        result[target] = source.read_bytes()
    shell = temporary / "awtarchy-jay"
    subprocess.run(
        ["python3", str(trial / "render-quickshell.py"),
         "--source", str(repo / "config/quickshell/awtarchy"),
         "--dest", str(shell), "--bridge-dir", str(trial)],
        check=True, timeout=45
    )
    for source in shell.iterdir():
        if not source.is_file() or source.is_symlink():
            raise ValueError("Unexpected generated Jay Quickshell asset")
        result[home / ".config/quickshell/awtarchy-jay" / source.name] = source.read_bytes()
    generated = temporary / "quickshell.sh"
    subprocess.run(
        ["python3", str(trial / "render-manager.py"),
         "--source", str(repo / "config/hypr/scripts/quickshell.sh"),
         "--dest", str(generated)],
        check=True, timeout=30
    )
    result[home / ".config/jay/awtarchy-trial/quickshell.sh"] = generated.read_bytes()
    return result

def atomic_replace(target, body):
    if target.is_symlink() or target.parent.is_symlink():
        raise ValueError("Refusing symlinked Jay destination")
    if not target.parent.is_dir():
        raise ValueError("Jay destination parent missing: " + str(target.parent))
    if target.exists() and not target.is_file():
        raise ValueError("Jay destination is not a file")
    previous = target.read_bytes() if target.exists() else None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    if previous is not None:
        backup = target.with_name(target.name + ".backup-" + stamp)
        with backup.open("xb") as handle:
            handle.write(previous)
            handle.flush()
            os.fsync(handle.fileno())
        backup.chmod(0o600)
    fd, name = tempfile.mkstemp(prefix=".jay-managed-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        mode = target.stat().st_mode & 0o777 if target.exists() else 0o755 if target.suffix == ".sh" else 0o644
        os.chmod(name, mode)
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("record", "review", "apply"))
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run the Jay updater as the normal user")
    home = Path.home().resolve()
    repo = args.repo.resolve()
    if not (repo / "trials/jay/setup.sh").is_file():
        raise ValueError("Jay source checkout not found")
    state = home / ".local/state/awtarchy"
    manifest = state / "jay-managed-baseline.json"
    if manifest.is_symlink() or state.is_symlink():
        raise ValueError("Unsafe Jay baseline path")
    with tempfile.TemporaryDirectory(prefix="jay-sync-") as stage:
        desired = expected_files(repo, home, Path(stage))
    actual = {}
    for path, body in desired.items():
        if path.is_symlink() or path.parent.is_symlink():
            raise ValueError("Refusing linked installed Jay path: " + str(path))
        if path.is_file():
            actual[str(path.relative_to(home))] = sha(path.read_bytes())
    if args.mode == "record":
        for path, body in desired.items():
            key = str(path.relative_to(home))
            if key == ".config/jay/config.toml":
                # Includes the one-time imported monitor profile, not base defaults.
                if key not in actual:
                    raise ValueError("No installed Jay configuration")
            elif actual.get(key) != sha(body):
                raise ValueError("Installed Jay stage does not match source: " + key)
        state.mkdir(parents=True, exist_ok=True)
        if manifest.exists():
            raise ValueError("Existing Jay baseline cannot be silently adopted")
        atomic_replace(manifest, json.dumps(actual, indent=2, sort_keys=True).encode() + b"\n")
        print("PASS: recorded exact initial Jay source baseline")
        return
    if not manifest.is_file():
        raise ValueError("Missing Jay baseline; refusing to assume personalized files are unmodified")
    original = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(original, dict):
        raise ValueError("Invalid Jay baseline")
    updated = dict(original)
    counts = dict(unchanged=0, update=0, preserve=0, missing=0)
    for path, body in sorted(desired.items(), key=lambda item: str(item[0])):
        key = str(path.relative_to(home))
        current = actual.get(key)
        target = sha(body)
        if current == target:
            counts["unchanged"] += 1
            continue
        if key == ".config/jay/config.toml":
            counts["preserve"] += 1
            print("PRESERVE personal Jay config: " + key)
            continue
        if current is None:
            counts["missing"] += 1
            print("MISSING (manual re-stage required): " + key)
            continue
        if original.get(key) != current:
            counts["preserve"] += 1
            print("PRESERVE modified file: " + key)
            continue
        counts["update"] += 1
        print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ") + key)
        if args.mode == "apply":
            atomic_replace(path, body)
            updated[key] = target
    if args.mode == "apply":
        atomic_replace(manifest, json.dumps(updated, indent=2, sort_keys=True).encode() + b"\n")
    print("Summary: " + ", ".join(f"{key}={value}" for key, value in counts.items()))
    print("Personal config and user-modified files were never overwritten.")
    if args.mode == "apply":
        print("Re-login recommended to load the new Jay Quickshell helpers.")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired, KeyError, json.JSONDecodeError) as exc:
        print("Jay sync: " + str(exc), file=sys.stderr)
        sys.exit(1)
