#!/usr/bin/env python3
"""Align Sway folder opening with Awtarchy's existing file-manager choice.

Read the same user-owned default-applications.json as Hyprland. Change only
inode/directory in the shared XDG mimeapps.list, never other MIME defaults.
A desktop-specific Sway override or an unsafe path is deliberately preserved.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

DESKTOP_IDS = {
    "pcmanfm-qt": "pcmanfm-qt.desktop",
    "thunar": "thunar.desktop",
    "dolphin": "org.kde.dolphin.desktop",
    "nautilus": "org.gnome.Nautilus.desktop",
    "nemo": "nemo.desktop",
    "pcmanfm": "pcmanfm.desktop",
}
GROUP = re.compile(r"^\s*\[([^\]]+)\]\s*$")
DIRECTORY = re.compile(r"^\s*inode/directory\s*=")


def refuse_links(path):
    for parent in (path, path.parent):
        if parent.is_symlink():
            raise ValueError("Refusing symlinked MIME settings: " + str(parent))
    if path.exists() and (not path.is_file() or not path.stat().st_uid == os.getuid()):
        raise ValueError("Refusing unsafe MIME settings: " + str(path))


def chosen_app(config_home):
    state = config_home / "awtarchy/default-applications.json"
    refuse_links(state)
    try:
        saved = json.loads(state.read_text(encoding="utf-8"))
    except FileNotFoundError:
        saved = {}
    if not isinstance(saved, dict):
        raise ValueError("Awtarchy default applications file is not a JSON object")
    selected = saved.get("file-manager", "pcmanfm-qt")
    if selected not in DESKTOP_IDS:
        raise ValueError("Unsupported configured file manager; preserving MIME associations")
    if shutil.which(selected) is None:
        raise ValueError("Configured file manager is not installed: " + selected)
    return selected, DESKTOP_IDS[selected]


def verify_desktop(desktop_id):
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    data_dirs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    for base in (data_home, *data_dirs):
        if not base or not os.path.isabs(base):
            continue
        path = Path(base) / "applications" / desktop_id
        if path.is_file():
            return
    raise ValueError("Desktop entry is unavailable: " + desktop_id)


def read_content(path):
    refuse_links(path)
    if not path.exists():
        return ""
    data = path.read_bytes()
    if len(data) > 1024 * 1024 or b"\0" in data:
        raise ValueError("Refusing unusual MIME settings file")
    return data.decode("utf-8")


def current_directory_entry(body):
    section = ""
    entries = []
    for line in body.splitlines():
        match = GROUP.fullmatch(line.strip())
        if match:
            section = match.group(1)
            continue
        if section == "Default Applications" and DIRECTORY.match(line):
            entries.append(line.split("=", 1)[1].strip().split(";", 1)[0].strip())
    if len(entries) > 1:
        raise ValueError("Multiple directory defaults; preserving custom MIME state")
    return entries[0] if entries else None


def proposed_content(body, desktop_id):
    lines = body.splitlines(keepends=True)
    group_start = None
    group_end = None
    matches = []
    for i, line in enumerate(lines):
        match = GROUP.fullmatch(line.strip())
        if match:
            if match.group(1) == "Default Applications":
                if group_start is not None:
                    raise ValueError("Duplicate Default Applications groups")
                group_start = i
            elif group_start is not None and group_end is None:
                group_end = i
    replacement = "inode/directory=" + desktop_id + ";\n"
    if group_start is None:
        prefix = "" if not body or body.endswith("\n") else "\n"
        return body + prefix + "[Default Applications]\n" + replacement
    stop = group_end if group_end is not None else len(lines)
    for i in range(group_start + 1, stop):
        if DIRECTORY.match(lines[i]):
            matches.append(i)
    if len(matches) > 1:
        raise ValueError("Duplicate directory defaults; preserving custom MIME state")
    if matches:
        current = lines[matches[0]]
        newline = "\r\n" if current.endswith("\r\n") else "\n"
        lines[matches[0]] = replacement[:-1] + newline
    else:
        lines.insert(group_start + 1, replacement)
    return "".join(lines)


def write_update(path, old, new):
    if old == new:
        return False
    if not path.parent.is_dir() or path.parent.is_symlink():
        raise ValueError("XDG config directory is unavailable or unsafe")
    refuse_links(path)
    if path.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
        backup = path.with_name(path.name + ".backup-" + stamp)
        with backup.open("xb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(old.encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
    fd, stage = tempfile.mkstemp(prefix=".awtarchy-mime-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(new.encode("utf-8"))
            output.flush()
            os.fsync(output.fileno())
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
        os.chmod(stage, mode)
        refuse_links(path)
        if (path.read_text(encoding="utf-8") if path.exists() else "") != old:
            raise ValueError("MIME settings changed during update; refusing replacement")
        os.replace(stage, path)
    finally:
        if os.path.exists(stage):
            os.unlink(stage)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("review", "apply"))
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise ValueError("Run as the normal desktop user")
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config"))
    if not config_home.is_dir() or config_home.is_symlink():
        raise ValueError("Unsafe or missing XDG configuration directory")
    app, desktop_id = chosen_app(config_home)
    verify_desktop(desktop_id)
    sway_override = config_home / "sway-mimeapps.list"
    if current_directory_entry(read_content(sway_override)):
        raise ValueError("Explicit sway-mimeapps.list directory default exists; preserving it")
    path = config_home / "mimeapps.list"
    original = read_content(path)
    current = current_directory_entry(original)
    if current == desktop_id:
        print("PASS: folder MIME default already matches " + app)
        return
    candidate = proposed_content(original, desktop_id)
    if args.action == "review":
        print("WOULD SET: inode/directory: " + str(current or "(unset)") + " -> " + desktop_id)
        return
    write_update(path, original, candidate)
    print("SET: inode/directory=" + desktop_id + "; (existing MIME entries preserved)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError) as exc:
        print("Sway MIME parity: " + str(exc), file=sys.stderr)
        sys.exit(1)
