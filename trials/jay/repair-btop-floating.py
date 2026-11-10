#!/usr/bin/env python3
"""Safely add Awtarchy's btop Foot floating rule to an installed Jay trial.

The regular Jay sync preserves personal config.toml, including imported displays.
This one-off helper only appends the missing btop rule, with a dated backup.
"""
import argparse
import importlib.util
from pathlib import Path
import os
import stat
import sys
import tomllib

HERE = Path(__file__).resolve().parent
RULE = (
    "# Foot btop is launched with --app-id btop by ALT/SUPER+SHIFT+B.\n"
    "# Current 1920x1080 displays: 80% width / 85% height from Hyprland.\n"
    "[[windows]]\n"
    'match.app-id = "btop"\n'
    'initial-tile-state = "floating"\n'
    "initial-floating-size = { width = 1536, height = 918 }\n"
)

def updated_bytes(original: bytes) -> bytes:
    body = original.decode("utf-8")
    data = tomllib.loads(body)
    if "# Awtarchy Jay session (experimental)." not in body:
        raise ValueError("Unknown Jay configuration; refusing automatic edit")
    existing = [
        rule for rule in data.get("windows", [])
        if rule.get("match", {}).get("app-id") == "btop"
    ]
    if existing:
        if len(existing) == 1 and existing[0].get("initial-tile-state") == "floating" and (
            existing[0].get("initial-floating-size") == {"width": 1536, "height": 918}
        ):
            return original
        raise ValueError("Existing customized btop rule; refusing to overwrite")
    if not any(rule.get("match", {}).get("app-id") == "awtarchy-qalc"
               for rule in data.get("windows", [])):
        raise ValueError("Recognizable Awtarchy utility rules missing")
    new_body = body.rstrip("\n") + "\n\n" + RULE
    parsed = tomllib.loads(new_body)
    if parsed.get("outputs") != data.get("outputs"):
        raise ValueError("Monitor profile would change")
    if len(parsed.get("windows", [])) != len(data.get("windows", [])) + 1:
        raise ValueError("Rule count unexpected")
    if parsed["windows"][-1]["match"]["app-id"] != "btop":
        raise ValueError("App ID mismatch")
    return new_body.encode("utf-8")

def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--preview", action="store_true")
    mode.add_argument("--apply", action="store_true")
    ap.add_argument("--config", type=Path, default=Path(
        os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    ) / "jay/config.toml")
    args = ap.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run as the normal user, not root")
    path = args.config
    if path.is_symlink() or path.parent.is_symlink() or not path.is_file():
        raise ValueError("Missing or unsafe Jay config: " + str(path))
    metadata = path.stat()
    if (not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1):
        raise ValueError("Jay config must be a single-link regular file owned by user")
    old = path.read_bytes()
    new = updated_bytes(old)
    if new == old:
        print("btop floating rule already present; no changes")
        return
    if args.preview:
        print("WOULD ADD: btop Foot initial floating 1536x918 (1920x1080 trial displays)")
        print("Existing Jay configuration and saved monitor profile remain unchanged")
        return
    # Reuse the existing guarded backup and atomic replacement machinery.
    spec = importlib.util.spec_from_file_location(
        "appearance_repair", HERE / "repair-first-login-appearance.py"
    )
    if spec is None or spec.loader is None:
        raise ValueError("Appearance migration helper unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    backup = module.apply(path, new, old, stat.S_IMODE(metadata.st_mode))
    if path.read_bytes() != new:
        raise ValueError("Could not verify updated Jay configuration; backup: " + str(backup))
    print("PASS: added btop floating rule; backup: " + str(backup))
    print("Jay should load the change automatically; test a newly opened btop window.")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError, tomllib.TOMLDecodeError) as err:
        print("Jay btop migration: " + str(err), file=sys.stderr)
        sys.exit(1)
