#!/usr/bin/env python3
"""Update colors in open Foot terminals without restarting them.

Foot reads foot.ini at launch; OSC 4/10/11 can recolor existing windows.
Only current-user Foot process descendants with an actual /dev/pts tty are
eligible. Do not touch the root-owned PolicyKit authentication frontend.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import stat
import sys

PALETTE_KEYS = ("background", "foreground") + tuple(
    f"{group}{i}" for group in ("regular", "bright") for i in range(8)
)
TTY_PATTERN = re.compile(r"/dev/pts/[0-9]+\Z")
FOOT_EXECUTABLES = ("/usr/bin/foot", "/usr/bin/footclient")


def read_palette(path: Path) -> dict[str, str]:
    colors: dict[str, str] = {}
    section = "main"
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section != "colors-dark" or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key not in PALETTE_KEYS:
            continue
        if key in colors or not re.fullmatch(r"[0-9a-fA-F]{6}", value):
            raise ValueError(f"invalid or duplicate Foot color: {key}")
        colors[key] = value.lower()
    if set(colors) != set(PALETTE_KEYS):
        raise ValueError("Foot config is missing one or more colors-dark palette entries")
    return colors


def osc_palette(colors: dict[str, str]) -> bytes:
    """Use OSC 4 for ANSI 0-15, OSC 10/11 for default foreground/background."""
    sequences = [
        f"\x1b]4;{index};#{colors[f'{group}{index % 8}']}\x1b\\"
        for index, group in ((i, "regular" if i < 8 else "bright") for i in range(16))
    ]
    sequences += [
        f"\x1b]10;#{colors['foreground']}\x1b\\",
        f"\x1b]11;#{colors['background']}\x1b\\",
    ]
    return "".join(sequences).encode("ascii")


def read_uid(proc: Path) -> int | None:
    try:
        for line in (proc / "status").read_text(encoding="ascii").splitlines():
            if line.startswith("Uid:"):
                return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return None


def child_pids(proc: Path) -> set[int]:
    result: set[int] = set()
    try:
        for task in (proc / "task").iterdir():
            if not task.name.isdigit():
                continue
            try:
                data = (task / "children").read_text(encoding="ascii")
                result.update(int(pid) for pid in data.split() if pid.isdigit())
            except OSError:
                continue
    except OSError:
        pass
    return result


def tty_for_child(proc: Path) -> str | None:
    for fd in ("0", "1", "2"):
        try:
            link = os.readlink(proc / "fd" / fd)
        except OSError:
            continue
        if TTY_PATTERN.fullmatch(link):
            return link
    return None


def foot_ttys(
    proc_root: Path = Path("/proc"),
    uid: int | None = None,
    executables: tuple[str, ...] = FOOT_EXECUTABLES,
    session: str = "",
) -> set[str]:
    owner = os.getuid() if uid is None else uid
    terminals: set[str] = set()
    allowed = set(executables)
    try:
        processes = list(proc_root.iterdir())
    except OSError:
        return terminals
    for proc in processes:
        if not proc.name.isdigit() or read_uid(proc) != owner:
            continue
        try:
            exe = os.path.realpath(proc / "exe")
            if exe not in allowed:
                continue
            argv = (proc / "cmdline").read_bytes().split(b"\0")
            if any(b"awtarchy-polkit-agent" in argument for argument in argv):
                continue
            if session:
                env = (proc / "environ").read_bytes().split(b"\0")
                prefixes = [
                    field.split(b"=", 1)[1].decode("ascii", "ignore")
                    for field in env
                    if field.startswith(b"HYPRLAND_INSTANCE_SIGNATURE=")
                ]
                if prefixes and prefixes[0] != session:
                    continue
        except OSError:
            continue

        # foot forks the terminal command, which inherits its PTY slave.
        # Discover nested children, but never follow unrelated process trees.
        pending = list(child_pids(proc))
        seen: set[int] = set()
        while pending and len(seen) < 512:
            pid = pending.pop()
            if pid in seen:
                continue
            seen.add(pid)
            child = proc_root / str(pid)
            if read_uid(child) != owner:
                continue
            tty = tty_for_child(child)
            if tty is not None:
                terminals.add(tty)
            pending.extend(child_pids(child) - seen)
    return terminals


def broadcast(colors: dict[str, str]) -> int:
    payload = osc_palette(colors)
    owner = os.getuid()
    session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    updated = 0
    for tty in sorted(foot_ttys(uid=owner, session=session)):
        try:
            st = os.stat(tty)
            if not stat.S_ISCHR(st.st_mode) or st.st_uid != owner:
                continue
            fd = os.open(tty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK | os.O_CLOEXEC)
            try:
                opened = os.fstat(fd)
                if not stat.S_ISCHR(opened.st_mode) or opened.st_uid != owner:
                    continue
                # Keep all 18 escape sequences together in one small write.
                if os.write(fd, payload) == len(payload):
                    updated += 1
            finally:
                os.close(fd)
        except OSError:
            # An old window may close while the theme changes. Never break
            # the theme transaction because a transient PTY disappeared.
            continue
    return updated


def main() -> int:
    if os.geteuid() == 0:
        return 0
    if len(sys.argv) != 2:
        print("usage: foot_theme_live.py FOOT_INI", file=sys.stderr)
        return 2
    try:
        colors = read_palette(Path(sys.argv[1]))
        broadcast(colors)
    except (OSError, ValueError) as exc:
        print(f"Foot live theme: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
