#!/usr/bin/env python3
"""Umbriel-native application screencopy exclusion, private to this session."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

# IDs, labels, sections, defaults and conservative app_id expressions.
# These are native application toplevel rules; layer-shell panels are not
# protected by Umbriel's block_capture window-rule property.
TARGETS = [
    ("security", "Passwords & Security", "protected", True,
     r"^(org[.]keepassxc[.]KeePassXC|KeePassXC|bitwarden|com[.]bitwarden[.]desktop|1Password|com[.]1password[.]1password)$"),
    ("mullvad-browser", "Mullvad Browser", "protected", True, r"^(mullvad-browser|Mullvad Browser)$"),
    ("localsend", "LocalSend", "protected", True, r"^(localsend|org[.]localsend[.]localsend_app)$"),
    ("telegram", "Telegram", "protected", True, r"^(TelegramDesktop|org[.]telegram[.]desktop|telegram-desktop)$"),
    ("matrix", "Element / Matrix", "protected", True, r"^(Element|im[.]riot[.]Riot|element-desktop)$"),
    ("discord", "Discord / Vesktop / Fluxer", "protected", True, r"^(discord|vesktop|Vesktop|fluxer)$"),
    ("teams", "Teams", "protected", True, r"^(teams-for-linux|Microsoft Teams|teams)$"),
    ("messages", "Messages", "protected", True, r"^(signal|org[.]signal[.]Signal|WhatsApp|whatsapp-for-linux)$"),
    ("obs", "OBS", "optional", False, r"^(com[.]obsproject[.]Studio|obs)$"),
    ("steam", "Steam", "optional", False, r"^(steam|Steam)$"),
    ("rustdesk", "RustDesk", "optional", False, r"^(rustdesk|RustDesk)$"),
    ("files", "Files", "optional", False, r"^(pcmanfm-qt|thunar|org[.]gnome[.]Nautilus|dolphin)$"),
    ("wallpicker", "Wallpicker", "optional", False, r"^(wallpicker)$"),
    ("virt-manager", "Virtual Machine Manager", "optional", False, r"^(virt-manager|Virtual Machine Manager)$"),
    ("foot", "Foot", "optional", False, r"^(foot|Foot)$"),
    ("mpv", "mpv", "optional", False, r"^(mpv|io[.]mpv[.]Mpv)$"),
]
REGISTRY = {row[0]: row for row in TARGETS}


def config_root() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def state_root() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")


def paths() -> tuple[Path, Path, Path, Path]:
    root = config_root() / "umbriel/awtarchy"
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR required")
    return (root / "capture-rules.toml",
            state_root() / "awtarchy/umbriel-screenshare-guard.json",
            Path(runtime) / "awtarchy-umbriel-guard-session.json",
            Path(runtime) / "awtarchy-umbriel-guard.lock")


def load_json(path: Path) -> dict:
    if path.is_symlink():
        raise ValueError("Unsafe guard symlink: " + str(path))
    if not path.exists():
        return {}
    if not path.is_file() or path.stat().st_uid != os.getuid():
        raise ValueError("Unowned guard file: " + str(path))
    data = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(data, dict) or
            any(key not in REGISTRY or type(value) is not bool
                for key, value in data.items())):
        raise ValueError("Invalid screen guard state: " + str(path))
    return data


def atomic_write(path: Path, body: bytes):
    parent = path.parent
    if parent.is_symlink() or (parent.exists() and
                             (not parent.is_dir() or parent.stat().st_uid != os.getuid())):
        raise ValueError("Unsafe guard destination: " + str(parent))
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or (path.exists() and
                            (not path.is_file() or path.stat().st_uid != os.getuid())):
        raise ValueError("Unsafe guard target: " + str(path))
    fd, tmp = tempfile.mkstemp(prefix=".awtarchy-guard-", dir=parent)
    try:
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


def desired(locked: dict, temporary: dict) -> dict[str, bool]:
    return {id: (locked[id] if id in locked else
                 temporary[id] if id in temporary else default)
            for id, _, _, default, _ in TARGETS}


def render(values: dict[str, bool]) -> bytes:
    result = [
        "# Awtarchy Umbriel Screen Share Guard. Application windows only.",
        "# Quickshell layer surfaces are not protected by these window rules.",
        "# Changes are made only through the Umbriel Screen Share Guard.",
        "",
    ]
    for id, label, _, _, pattern in TARGETS:
        if values[id]:
            result.extend([
                "[[window_rule]]",
                "match.app_id = " + json.dumps(pattern),
                "block_capture = true",
                "",
            ])
    body = ("\n".join(result) + "\n").encode()
    tomllib.loads(body.decode())
    return body


def render_defaults() -> bytes:
    return render(desired({}, {}))


def reported_effective(path: Path) -> set[str] | None:
    if path.is_symlink() or not path.is_file():
        return None
    parsed = tomllib.loads(path.read_text(encoding="utf-8"))
    actual = {rule.get("match", {}).get("app_id")
              for rule in parsed.get("window_rule", [])
              if isinstance(rule, dict) and rule.get("block_capture") is True}
    return {id for id, _, _, _, pattern in TARGETS if pattern in actual}


def status(locked: dict, temporary: dict, rules: Path) -> dict:
    values = desired(locked, temporary)
    effective = reported_effective(rules)
    entries = {}
    for order, (id, label, section, default, _) in enumerate(TARGETS):
        exists = effective is not None
        active = id in effective if exists else None
        entries[id] = {
            "id": id, "label": label, "section": section, "order": order,
            "default_protected": default, "desired_protected": values[id],
            "effective_protected": active, "locked": id in locked,
            "session_override": temporary.get(id) if id not in locked else None,
            "in_sync": exists and active == values[id],
        }
    return {"targets": entries}


def apply(action: str, target: str | None, preference: str | None):
    rules, permanent_path, session_path, lock_path = paths()
    if os.environ.get("XDG_CURRENT_DESKTOP", "").casefold() != "umbriel":
        raise ValueError("Native Umbriel session required")
    if action == "status-json":
        print(json.dumps(status(load_json(permanent_path),
                                load_json(session_path), rules),
                         separators=(",", ":")))
        return
    if target is not None and target not in REGISTRY:
        raise ValueError("Unknown capture guard target")
    runtime = lock_path.parent
    if (not runtime.is_dir() or runtime.is_symlink() or
            runtime.stat().st_uid != os.getuid() or runtime.stat().st_mode & 0o077):
        raise ValueError("Unsafe XDG_RUNTIME_DIR")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        locked = load_json(permanent_path)
        session = load_json(session_path)
        before = rules.read_bytes() if rules.exists() and not rules.is_symlink() else None
        if action == "set":
            if preference not in ("protected", "allowed"):
                raise ValueError("Expected protected or allowed")
            values = locked if target in locked else session
            values[target] = preference == "protected"
        elif action == "lock":
            locked[target] = desired(locked, session)[target]
            session.pop(target, None)
        elif action == "unlock":
            value = desired(locked, session)[target]
            locked.pop(target, None)
            session[target] = value
        elif action == "reset":
            locked.clear()
            session.clear()
        else:
            raise ValueError("Invalid Screen Share Guard action")
        rendered = render(desired(locked, session))
        atomic_write(rules, rendered)
        try:
            response = subprocess.run(
                ["umbriel", "msg", "config-reload"], check=True,
                capture_output=True, text=True, timeout=12)
            if '"err"' in response.stdout:
                raise ValueError(response.stdout.strip())
        except (OSError, ValueError, subprocess.CalledProcessError,
                subprocess.TimeoutExpired):
            if before is not None:
                atomic_write(rules, before)
                subprocess.run(["umbriel", "msg", "config-reload"],
                               capture_output=True, text=True, timeout=12)
            raise
        atomic_write(permanent_path, (json.dumps(locked, sort_keys=True) + "\n").encode())
        atomic_write(session_path, (json.dumps(session, sort_keys=True) + "\n").encode())
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        arguments = sys.argv[1:]
        if arguments == ["status-json"]:
            apply("status-json", None, None)
        elif arguments == ["reset"]:
            apply("reset", None, None)
        elif len(arguments) == 2 and arguments[0] in ("lock", "unlock"):
            apply(arguments[0], arguments[1], None)
        elif len(arguments) == 3 and arguments[0] == "set":
            apply(arguments[0], arguments[1], arguments[2])
        else:
            raise ValueError("Usage: screenshare-guard.py status-json|reset|set ID protected|allowed|lock ID|unlock ID")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError,
            subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Umbriel Screen Share Guard: " + str(error), file=sys.stderr)
        sys.exit(1)
