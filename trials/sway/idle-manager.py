#!/usr/bin/env python3
"""One swayidle per Awtarchy trial Sway socket, with exact process identity."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

TRIAL = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "sway/awtarchy-trial"
CONFIG = TRIAL / "swayidle.conf"


def session_identity():
    if (os.environ.get("XDG_CURRENT_DESKTOP", "").lower() != "sway"
            or not os.environ.get("WAYLAND_DISPLAY")
            or not os.environ.get("SWAYSOCK")):
        raise ValueError("Active Sway session required")
    response = subprocess.run(["swaymsg", "-r", "-t", "get_version"],
                              capture_output=True, text=True, timeout=8)
    if response.returncode:
        raise ValueError("Sway compositor IPC unavailable")
    if json.loads(response.stdout).get("loaded_config_file_name") != str(TRIAL / "config"):
        raise ValueError("Not the active Awtarchy Sway trial config")


def private_state():
    value = os.environ.get("XDG_RUNTIME_DIR")
    if not value or not Path(value).is_dir() or Path(value).is_symlink():
        raise ValueError("Safe XDG_RUNTIME_DIR required")
    stat = Path(value).stat()
    if stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError("Unsafe XDG_RUNTIME_DIR permissions")
    root = Path(value) / "awtarchy-sway-idle"
    if root.is_symlink() or (root.exists() and not root.is_dir()):
        raise ValueError("Unsafe idle state directory")
    root.mkdir(mode=0o700, exist_ok=True)
    stat = root.stat()
    if stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError("Unsafe idle state directory permissions")
    return root


def start_marker(pid):
    try:
        stat = (Path("/proc") / str(pid) / "stat").read_text()
        fields = stat[stat.rfind(") ") + 2:].split()
        return fields[0], fields[19]
    except (OSError, ValueError, IndexError):
        return None


def verified(info, executable, socket):
    if not isinstance(info, dict):
        return False
    pid, stamp = info.get("pid"), info.get("start")
    if type(pid) is not int or pid < 1 or not isinstance(stamp, str):
        return False
    marker = start_marker(pid)
    if not marker or marker[0] in ("Z", "X", "x") or marker[1] != stamp:
        return False
    try:
        args = (Path("/proc") / str(pid) / "cmdline").read_bytes().split(b"\0")
        env = (Path("/proc") / str(pid) / "environ").read_bytes().split(b"\0")
    except OSError:
        return False
    return (args == [os.fsencode(executable), b"-w", b"-C", os.fsencode(CONFIG), b""]
            and b"SWAYSOCK=" + os.fsencode(socket) in env)


def stop_exact(info, executable, socket):
    if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        raise ValueError("pidfd unavailable; refusing to signal unverified idle daemon")
    fd = os.pidfd_open(info["pid"])
    try:
        if not verified(info, executable, socket):
            raise ValueError("Idle daemon identity changed")
        signal.pidfd_send_signal(fd, signal.SIGTERM)
    finally:
        os.close(fd)
    for _ in range(60):
        if not verified(info, executable, socket):
            return
        time.sleep(0.05)
    raise ValueError("Old idle daemon still running; refusing duplicate")


def read_state(path):
    if path.is_symlink():
        raise ValueError("Unsafe idle state symlink")
    if not path.exists():
        return None
    if not path.is_file() or path.stat().st_uid != os.getuid():
        raise ValueError("Unsafe idle state file")
    try:
        return json.loads(path.read_text())
    except (ValueError, OSError) as exc:
        raise ValueError("Corrupt idle state file") from exc


def save_state(path, info):
    temp = path.with_name(path.name + ".tmp-" + str(os.getpid()))
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(info, handle, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def main(action):
    if action not in ("start", "status"):
        raise ValueError("Usage: idle-manager.py start|status")
    session_identity()
    if not CONFIG.is_file() or CONFIG.is_symlink():
        raise ValueError("Sway idle configuration missing or unsafe")
    executable = shutil.which("swayidle")
    if not executable:
        raise ValueError("swayidle is not installed")

    socket = os.environ["SWAYSOCK"]
    name = hashlib.sha256(os.fsencode(socket)).hexdigest()[:20]
    directory = private_state()
    state = directory / (name + ".json")
    lock = directory / (name + ".lock")
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        prior = read_state(state)
        running = verified(prior, executable, socket)
        config_hash = hashlib.sha256(CONFIG.read_bytes()).hexdigest()
        if action == "status":
            print("running" if running else "inactive")
            return 0 if running else 1
        if running and prior.get("config_sha") == config_hash:
            print("Sway idle daemon already running")
            return 0
        if running:
            stop_exact(prior, executable, socket)
        cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "awtarchy"
        cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        log = cache / "swayidle.log"
        with log.open("ab") as output:
            child = subprocess.Popen(
                [executable, "-w", "-C", str(CONFIG)], stdin=subprocess.DEVNULL,
                stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            time.sleep(0.3)
            if child.poll() is not None:
                raise ValueError("Swayidle terminated during startup; inspect " + str(log))
            marker = start_marker(child.pid)
            if not marker or marker[0] in ("Z", "X", "x"):
                raise ValueError("New idle daemon birth marker unavailable")
            info = {"pid": child.pid, "start": marker[1], "config_sha": config_hash}
            if not verified(info, executable, socket):
                raise ValueError("New swayidle process identity not verified")
            save_state(state, info)
            print("Sway idle active: lock 3m, screens off 4m, suspend 9m")
        except Exception:
            if child.poll() is None:
                child.terminate()
            raise
        return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1] if len(sys.argv) == 2 else "invalid"))
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print("Awtarchy Sway idle: " + str(exc), file=sys.stderr)
        sys.exit(1)
