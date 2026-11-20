#!/usr/bin/env python3
"""xdg-desktop-portal-wlr dmenu chooser using the existing Awtarchy Sway shell.

Only exact portal-supplied choices may reach stdout. Cancellation or failure
must never fall back to silently sharing an arbitrary monitor.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

PREFIX = "awtarchy-screencast-"
MAX_CHOICES = 64
MAX_INPUT = 32768
TIMEOUT_SECONDS = 90


def runtime():
    value = os.environ.get("XDG_RUNTIME_DIR")
    if not value:
        raise ValueError("Missing XDG_RUNTIME_DIR")
    root = Path(value)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Unsafe runtime directory")
    stat = root.stat()
    if stat.st_uid != os.geteuid() or stat.st_mode & 0o077:
        raise ValueError("XDG_RUNTIME_DIR must belong to this user and be private")
    return root


def validate_request(value):
    path = Path(value)
    root = runtime()
    if (path.name != "request.json" or path.parent.parent != root
            or not re.fullmatch(PREFIX + r"[a-z0-9_]+", path.parent.name)
            or not path.parent.is_dir() or path.parent.is_symlink()
            or not path.is_file() or path.is_symlink()):
        raise ValueError("Untrusted screencast request path")
    if (path.stat().st_uid != os.geteuid()
            or path.parent.stat().st_uid != os.geteuid()
            or path.parent.stat().st_mode & 0o077):
        raise ValueError("Unsafe screencast request ownership")
    document = json.loads(path.read_text(encoding="utf-8"))
    choices = document.get("choices") if isinstance(document, dict) else None
    if (not isinstance(choices, list) or not 1 <= len(choices) <= MAX_CHOICES
            or any(not isinstance(v, str) or not v or "\n" in v
                   or "\r" in v or "\x00" in v for v in choices)):
        raise ValueError("Invalid screencast request choices")
    return path, choices


def respond(value, index):
    path, choices = validate_request(value)
    try:
        selection = int(index)
    except (TypeError, ValueError) as exc:
        raise ValueError("Invalid source index") from exc
    if not -1 <= selection < len(choices):
        raise ValueError("Source index outside offered choices")
    reply = path.parent / "reply.json"
    # First response wins. Reject duplicate clicks/competing requests.
    fd = os.open(reply, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as file:
        json.dump({"index": selection}, file)
        file.write("\n")
    return 0


def choose(stream, *, deadline=TIMEOUT_SECONDS):
    if os.environ.get("XDG_CURRENT_DESKTOP", "").lower() != "sway":
        raise ValueError("Sway session required")
    data = stream.read(MAX_INPUT + 1)
    if len(data) > MAX_INPUT:
        raise ValueError("Portal source list too large")
    choices = data.splitlines()
    if (not 1 <= len(choices) <= MAX_CHOICES
            or any(not isinstance(s, str) or not s or "\x00" in s
                   for s in choices)):
        raise ValueError("Invalid portal source list")
    stage = Path(tempfile.mkdtemp(dir=runtime(), prefix=PREFIX))
    try:
        request = stage / "request.json"
        fd = os.open(request, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump({"choices": choices}, file, ensure_ascii=False)
            file.write("\n")
        response = subprocess.run(
            ["qs", "-c", "awtarchy-sway", "ipc", "call", "screenshare", "open",
             str(request)],
            capture_output=True, text=True, timeout=8)
        if response.returncode or response.stdout.strip().lower() != "true":
            raise ValueError("Quickshell chooser did not accept request")
        end = time.monotonic() + deadline
        reply = stage / "reply.json"
        while time.monotonic() < end:
            if reply.exists():
                if reply.is_symlink() or not reply.is_file():
                    raise ValueError("Invalid screencast reply")
                answer = json.loads(reply.read_text(encoding="utf-8"))
                index = answer.get("index") if isinstance(answer, dict) else None
                if type(index) is not int or not -1 <= index < len(choices):
                    raise ValueError("Invalid screencast selection")
                if index >= 0:
                    print(choices[index], flush=True)
                return 0
            time.sleep(0.075)
        raise ValueError("Screencast selector timed out")
    finally:
        shutil.rmtree(stage)


def main():
    try:
        if len(sys.argv) == 1:
            return choose(sys.stdin)
        if len(sys.argv) == 4 and sys.argv[1] == "respond":
            return respond(sys.argv[2], sys.argv[3])
        raise ValueError("Usage: portal-chooser.py [respond REQUEST INDEX]")
    except (OSError, ValueError, json.JSONDecodeError,
            subprocess.TimeoutExpired) as exc:
        print("Awtarchy Sway screencast chooser: " + str(exc), file=sys.stderr)
        # xdpw reserves exit 127 for 'chooser not found'.
        return 1


if __name__ == "__main__":
    sys.exit(main())
