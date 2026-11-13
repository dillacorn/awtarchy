#!/usr/bin/env python3
"""Preview/apply Sway code updates without replacing personalized TOML or QML."""
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
    trial = repo / "trials/sway"
    script = (trial / "setup.sh").read_text(encoding="utf-8")
    m = re.search(r"^sources=\(([^)]*)\)$", script, flags=re.MULTILINE)
    if not m:
        raise ValueError("Sway setup source manifest is unavailable")
    sources = shlex.split(m.group(1))
    if "config" not in sources or "sway-portals.conf" not in sources:
        raise ValueError("Sway managed source inventory changed")
    result = {}
    for name in sources:
        if "/" in name or not re.fullmatch(r"[a-zA-Z0-9._-]+", name):
            raise ValueError("Unsafe Sway source name")
        target = (
            home / ".config/sway/awtarchy-trial/config" if name == "config" else
            home / ".config/xdg-desktop-portal/sway-portals.conf" if name == "sway-portals.conf" else
            home / ".config/sway/awtarchy-trial" / name
        )
        source = trial / name
        if source.is_symlink() or not source.is_file():
            raise ValueError("Unsafe Sway source file: " + str(source))
        result[target] = source.read_bytes()
    # The Sway session uses private copies of DDC scripts. The active
    # ~/.config/hypr/scripts files may be user-modified or from a release that
    # predates this trial; never depend on changing them for Sway updates.
    for name in ("ddc_brightness.sh", "hypr-ddc-brightness.sh"):
        source = repo / "config/hypr/scripts" / name
        if source.is_symlink() or not source.is_file():
            raise ValueError("Unsafe shared brightness source: " + str(source))
        result[home / ".config/sway/awtarchy-trial" / name] = source.read_bytes()
    shell = temporary / "awtarchy-sway"
    subprocess.run(
        ["python3", str(trial / "render-quickshell.py"),
         "--source", str(repo / "config/quickshell/awtarchy"),
         "--dest", str(shell), "--bridge-dir", str(trial)],
        check=True, timeout=45
    )
    for source in shell.iterdir():
        if not source.is_file() or source.is_symlink():
            raise ValueError("Unexpected generated Sway Quickshell asset")
        result[home / ".config/quickshell/awtarchy-sway" / source.name] = source.read_bytes()
    generated = temporary / "quickshell.sh"
    subprocess.run(
        ["python3", str(trial / "render-manager.py"),
         "--source", str(repo / "config/hypr/scripts/quickshell.sh"),
         "--dest", str(generated)],
        check=True, timeout=30
    )
    result[home / ".config/sway/awtarchy-trial/quickshell.sh"] = generated.read_bytes()
    return result

def prepare_config_update(old: bytes, new: bytes) -> bytes:
    """Keep the original Sway output profile byte-for-byte across updates.

    Called only when the installed config hash still matches Awtarchy's
    recorded baseline. A user-edited config is preserved without guessing.
    """
    start = "# AWTARCHY-SWAY-OUTPUTS-BEGIN"
    end = "# AWTARCHY-SWAY-OUTPUTS-END"
    previous = old.decode("utf-8")
    proposed = new.decode("utf-8")
    for text in (previous, proposed):
        if text.count(start) != 1 or text.count(end) != 1:
            raise ValueError("Sway monitor delimiters changed; refusing config update")
    imported = previous.split(start, 1)[1].split(end, 1)[0]
    return (proposed.split(start, 1)[0] + start + imported + end
            + proposed.split(end, 1)[1]).encode("utf-8")


def validate_sway_config(target: Path, content: bytes):
    # Parse the *real* imported monitor profile with installed Sway before
    # replacing the live config. This never starts a session.
    with tempfile.NamedTemporaryFile(
            prefix=".sway-config-check-", dir=target.parent,
            delete=False) as stage:
        temp_path = Path(stage.name)
        stage.write(content)
    try:
        result = subprocess.run(
            ["sway", "-C", "-c", str(temp_path)], timeout=20,
            capture_output=True, text=True)
        if result.returncode:
            raise ValueError("Sway rejected candidate config: " + result.stderr.strip())
    finally:
        temp_path.unlink(missing_ok=True)


def atomic_replace(target, body):
    if target.is_symlink() or target.parent.is_symlink():
        raise ValueError("Refusing symlinked Sway destination")
    if not target.parent.is_dir():
        raise ValueError("Sway destination parent missing: " + str(target.parent))
    if target.exists() and not target.is_file():
        raise ValueError("Sway destination is not a file")
    previous = target.read_bytes() if target.exists() else None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    if previous is not None:
        backup = target.with_name(target.name + ".backup-" + stamp)
        with backup.open("xb") as handle:
            handle.write(previous)
            handle.flush()
            os.fsync(handle.fileno())
        backup.chmod(0o600)
    fd, name = tempfile.mkstemp(prefix=".sway-managed-", dir=target.parent)
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
        raise ValueError("Run the Sway updater as the normal user")
    home = Path.home().resolve()
    repo = args.repo.resolve()
    if not (repo / "trials/sway/setup.sh").is_file():
        raise ValueError("Sway source checkout not found")
    state = home / ".local/state/awtarchy"
    manifest = state / "sway-managed-baseline.json"
    if manifest.is_symlink() or state.is_symlink():
        raise ValueError("Unsafe Sway baseline path")
    with tempfile.TemporaryDirectory(prefix="sway-sync-") as stage:
        desired = expected_files(repo, home, Path(stage))
    actual = {}
    for path, body in desired.items():
        if path.is_symlink() or path.parent.is_symlink():
            raise ValueError("Refusing linked installed Sway path: " + str(path))
        if path.is_file():
            actual[str(path.relative_to(home))] = sha(path.read_bytes())
    if args.mode == "record":
        for path, body in desired.items():
            key = str(path.relative_to(home))
            if key == ".config/sway/awtarchy-trial/config":
                # Includes the one-time imported monitor profile, not base defaults.
                if key not in actual:
                    raise ValueError("No installed Sway configuration")
            elif actual.get(key) != sha(body):
                raise ValueError("Installed Sway stage does not match source: " + key)
        state.mkdir(parents=True, exist_ok=True)
        if manifest.exists():
            raise ValueError("Existing Sway baseline cannot be silently adopted")
        atomic_replace(manifest, json.dumps(actual, indent=2, sort_keys=True).encode() + b"\n")
        print("PASS: recorded exact initial Sway source baseline")
        return
    if not manifest.is_file():
        raise ValueError("Missing Sway baseline; refusing to assume personalized files are unmodified")
    original = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(original, dict):
        raise ValueError("Invalid Sway baseline")
    updated = dict(original)
    counts = dict(unchanged=0, update=0, preserve=0, missing=0)
    for path, body in sorted(desired.items(), key=lambda item: str(item[0])):
        key = str(path.relative_to(home))
        current = actual.get(key)
        target = sha(body)
        if current == target:
            # A new managed asset may have been installed by setup.sh after
            # the original baseline was recorded. Adopt only byte-for-byte
            # source matches, never arbitrary existing user files.
            if key not in original:
                print(("ADOPT: " if args.mode == "apply" else "WOULD ADOPT: ")
                      + key + " (exact source match; no file write)")
                if args.mode == "apply":
                    updated[key] = target
            counts["unchanged"] += 1
            continue
        if key == ".config/sway/awtarchy-trial/config":
            # Awtarchy's original installer records the installed config
            # *after* one-time monitor import. Honor that exact hash as proof
            # the user has not edited it. Preserve every personal change.
            if original.get(key) != current:
                counts["preserve"] += 1
                print("PRESERVE user-modified Sway config: " + key)
                continue
            candidate = prepare_config_update(path.read_bytes(), body)
            if sha(candidate) == current:
                counts["unchanged"] += 1
                continue
            validate_sway_config(path, candidate)
            counts["update"] += 1
            print(("UPDATE: " if args.mode == "apply" else "WOULD UPDATE: ")
                  + key + " (preserve imported monitor layout)")
            if args.mode == "apply":
                if sha(path.read_bytes()) != current:
                    raise ValueError("Sway config changed during update; refusing")
                atomic_replace(path, candidate)
                updated[key] = sha(candidate)
            continue
        if current is None:
            # New narrowly scoped brightness assets can safely be staged by
            # this managed updater. Existing unknown files still fail closed.
            new_brightness = key in (
                ".config/sway/awtarchy-trial/ddc_brightness.sh",
                ".config/sway/awtarchy-trial/hypr-ddc-brightness.sh",
                ".config/sway/awtarchy-trial/ddc.sh",
                ".config/sway/awtarchy-trial/theme-colors.sh",
                ".config/sway/awtarchy-trial/toggle-utility.py",
            )
            if not new_brightness:
                counts["missing"] += 1
                print("MISSING (manual re-stage required): " + key)
                continue
            counts["update"] += 1
            print(("INSTALL: " if args.mode == "apply" else "WOULD INSTALL: ")
                  + key + " (new Sway-only brightness helper)")
            if args.mode == "apply":
                atomic_replace(path, body)
                updated[key] = target
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
        print("Re-login recommended to load the new Sway Quickshell helpers.")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired, KeyError, json.JSONDecodeError) as exc:
        print("Sway sync: " + str(exc), file=sys.stderr)
        sys.exit(1)
