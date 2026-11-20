#!/usr/bin/env python3
"""Isolated, always-preserve Umbriel/Quickshell staging and baseline updates."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def desired_files(repo: Path, home: Path, stage: Path) -> dict[Path, bytes]:
    src = repo / "compositors/umbriel"
    config = home / ".config"
    target = config / "umbriel/awtarchy-trial"
    sources = {
        config / "umbriel/config.toml": src / "native-config.toml",
        target / "config.toml": src / "config.toml",
    }
    # Keep the generated migration in Umbriel's private include. It is
    # regenerated from the selected source, never executed as Lua/Sway shell.
    spec = importlib.util.spec_from_file_location("awtarchy_umbriel_migrate", src / "migrate.py")
    migrator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migrator)
    override = os.environ.get("AWTARCHY_MIGRATE_FROM", "auto")
    migrated, info = migrator.migrate(home, override)
    print("MIGRATION: " + info["source"] + " (" + info["selection"] +
          "), displays=" + str(info["outputs"]) +
          ", shortcuts=" + str(info["keybinds"]))
    if info["outputs"] == 0:
        print("MIGRATION: no verified explicit display rules; defaults retained")
    result = {target / "migrated.toml": migrated}
    for name in ("session.sh", "ipc.sh", "monitor-info.py", "workspace-state.py",
                 "position.sh", "runtime-rules.sh"):
        sources[target / name] = src / name
    for dst, origin in sources.items():
        if origin.is_symlink() or not origin.is_file():
            raise ValueError("Unsafe Umbriel source " + str(origin))
        result[dst] = origin.read_bytes()
    tomllib.loads(result[target / "config.toml"].decode())
    tomllib.loads(result[config / "umbriel/config.toml"].decode())
    # Validate the full include stack before staging any live user config.
    # An invalid native config must not be installed or activated.
    if shutil.which("umbriel") is not None:
        testroot = stage / "validate/umbriel"
        testroot.mkdir(parents=True, exist_ok=True)
        for name, data in (
            ("config.toml", result[config / "umbriel/config.toml"]),
            ("awtarchy-trial/config.toml", result[target / "config.toml"]),
            ("awtarchy-trial/migrated.toml", result[target / "migrated.toml"]),
        ):
            dest = testroot / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = str(testroot.parent)
        check = subprocess.run(["umbriel", "config", "validate"], env=env,
                               capture_output=True, text=True, timeout=12)
        if check.returncode:
            raise ValueError("Umbriel rejected migrated config: " +
                             (check.stderr or check.stdout).strip()[:2500])

    rendered = stage / "awtarchy-umbriel"
    manager = stage / "quickshell.sh"
    subprocess.run([sys.executable, str(src / "render-quickshell.py"),
                    "--repo", str(repo), "--dest", str(rendered)],
                   check=True, timeout=70)
    subprocess.run([sys.executable, str(src / "render-manager.py"),
                    "--repo", str(repo), "--dest", str(manager)],
                   check=True, timeout=40)
    for asset in sorted(rendered.iterdir()):
        if not asset.is_file() or asset.is_symlink():
            raise ValueError("Unexpected rendered Umbriel shell asset")
        result[config / "quickshell/awtarchy-umbriel" / asset.name] = asset.read_bytes()
    result[target / "quickshell.sh"] = manager.read_bytes()
    return result


def safe_directories(home: Path):
    for relative in (".config", ".config/umbriel",
                     ".config/umbriel/awtarchy-trial",
                     ".config/quickshell", ".config/quickshell/awtarchy-umbriel",
                     ".local", ".local/state", ".local/state/awtarchy"):
        item = home / relative
        if item.is_symlink() or (item.exists() and not item.is_dir()):
            raise ValueError("Unsafe Umbriel destination directory " + str(item))
        if item.exists() and item.stat().st_uid != os.geteuid():
            raise ValueError("Unowned Umbriel destination directory " + str(item))


def atomic_write(path: Path, data: bytes, backup: bool):
    staged_name = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".umbriel-stage-", dir=path.parent,
                                         delete=False) as staged:
            staged_name = staged.name
            staged.write(data)
            staged.flush()
            os.fsync(staged.fileno())
        os.chmod(staged_name, 0o755 if path.suffix == ".sh" else 0o644)
        if backup:
            import datetime
            tag = datetime.datetime.now(datetime.timezone.utc).strftime(
                "%Y%m%d-%H%M%S-%f")
            previous = path.with_name(path.name + ".backup-" + tag)
            with previous.open("xb") as handle:
                os.fchmod(handle.fileno(), 0o600)
                handle.write(path.read_bytes())
                handle.flush()
                os.fsync(handle.fileno())
        os.replace(staged_name, path)
        staged_name = None
    finally:
        if staged_name is not None and os.path.exists(staged_name):
            os.unlink(staged_name)


def reconcile(repo: Path, home: Path, mode: str):
    if mode not in ("preview", "apply"):
        raise ValueError("Invalid Umbriel staging mode")
    if os.geteuid() == 0:
        raise ValueError("Do not stage Umbriel files as root")
    if home.is_symlink() or not home.is_dir():
        raise ValueError("Unsafe home directory")
    safe_directories(home)
    state = home / ".local/state/awtarchy/umbriel-trial-baseline.json"
    if state.is_symlink() or (state.exists() and (not state.is_file()
            or state.stat().st_uid != os.geteuid())):
        raise ValueError("Unsafe Umbriel managed baseline")
    baseline = {}
    if state.is_file():
        contents = json.loads(state.read_text(encoding="utf-8"))
        if (not isinstance(contents, dict) or contents.get("version") != 1
                or not isinstance(contents.get("hashes"), dict)):
            raise ValueError("Invalid Umbriel baseline manifest")
        baseline = contents["hashes"]
        if any(not isinstance(k, str) or not isinstance(v, str)
               or not re.fullmatch(r"[0-9a-f]{64}", v) for k, v in baseline.items()):
            raise ValueError("Invalid Umbriel baseline entries")
    with tempfile.TemporaryDirectory(prefix="umbriel-render-") as temp:
        desired = desired_files(repo, home, Path(temp))
    native = home / ".config/umbriel/config.toml"
    native_source = desired[native]
    # Never quietly install a shell that the native session will not load.
    if native.is_symlink() or (native.is_file()
            and native.read_bytes() != native_source
            and baseline.get(str(native.relative_to(home)))
                != digest(native.read_bytes())):
        raise ValueError(
            "Personal Umbriel config exists. Preserved; refusing to override "
            "it or misrepresent that Awtarchy will launch. Add an include manually "
            "or test on a fresh Umbriel config.")
    for target in desired:
        if target.is_symlink() or (target.exists() and (
                not target.is_file() or target.stat().st_uid != os.geteuid())):
            raise ValueError("Unsafe or unowned Umbriel file " + str(target))
    updated = dict(baseline)
    new_files = changes = preserved = 0
    # Install migration data before publishing an include that references it.
    # On an already running Umbriel session this avoids an incomplete reload.
    native = home / ".config/umbriel/config.toml"
    ordered = sorted(desired, key=lambda path: (
        path == native, str(path)))
    for target in ordered:
        content = desired[target]
        key = str(target.relative_to(home))
        expected = digest(content)
        existing = target.read_bytes() if target.exists() else None
        if existing == content:
            if mode == "apply":
                updated[key] = expected
            continue
        if existing is None:
            new_files += 1
            print(("INSTALL " if mode == "apply" else "WOULD INSTALL ") + key)
            if mode == "apply":
                target.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(target, content, False)
                updated[key] = expected
            continue
        if baseline.get(key) != digest(existing):
            preserved += 1
            print("PRESERVE personalized file " + key)
            continue
        changes += 1
        print(("UPDATE " if mode == "apply" else "WOULD UPDATE ")
              + key + " (original backup)")
        if mode == "apply":
            # A settings editor may modify the file after our initial scan.
            # Never turn a stale baseline into authority over a newer edit.
            if target.is_symlink() or not target.is_file() or target.read_bytes() != existing:
                raise ValueError("Umbriel file changed during update; preserving " + key)
            atomic_write(target, content, True)
            updated[key] = expected
    if mode == "apply":
        state.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(state, (json.dumps({"version": 1, "hashes": updated},
                     indent=2, sort_keys=True) + "\n").encode(), bool(state.exists()))
    print("Umbriel files: new=%s updated=%s preserved=%s"
          % (new_files, changes, preserved))
    print("Other compositor configurations and installed packages are untouched.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preview", "apply"))
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    try:
        reconcile(args.repo.resolve(), Path.home().resolve(), args.mode)
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Umbriel staging: " + str(error), file=sys.stderr)
        sys.exit(1)
