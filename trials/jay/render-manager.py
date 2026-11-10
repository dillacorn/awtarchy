#!/usr/bin/env python3
"""Port the current Awtarchy Quickshell manager to isolated Jay output IPC."""
import argparse
from pathlib import Path
import sys

def render(source: Path, target: Path):
    if source.is_symlink() or not source.is_file():
        raise ValueError("Unsafe Hyprland source manager")
    if target.exists() or target.is_symlink():
        raise ValueError("Existing Jay manager would be overwritten")
    body = source.read_text(encoding="utf-8")
    substitutions = [
        ('CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy}"',
         'CONFIG_NAME="${QUICKSHELL_CONFIG_NAME:-awtarchy-jay}"'),
        ('need hyprctl', 'need jay'),
        # Quickshell IPC can return a zero status with a textual error.\n        # A started process is not equivalent to a registered control handler.\n        ('    ipc control ping >/dev/null 2>&1',\n         '    [[ "$(ipc control ping 2>/dev/null)" == "ok" ]]'),
        ('hyprctl monitors -j 2>/dev/null',
         'python3 "${CONFIG_HOME}/jay/awtarchy-trial/monitor-info.py" monitors 2>/dev/null'),
        ('hyprctl activeworkspace -j 2>/dev/null',
         'python3 "${CONFIG_HOME}/jay/awtarchy-trial/monitor-info.py" activeworkspace 2>/dev/null'),
        ('nohup qs -c "$CONFIG_NAME" 7>&- 8>&-',
         'nohup jay run-tagged awtarchy-jay-shell qs -c "$CONFIG_NAME" 7>&- 8>&-'),
        ('/hypr/scripts/quickshell_cursor_theme.sh',
         '/jay/awtarchy-trial/cursor-theme.sh'),
        ('LOG_FILE="${STATE_DIR}/quickshell.log"', 'LOG_FILE="${STATE_DIR}/quickshell-jay.log"'),
        ('START_LOCK_FILE="${STATE_DIR}/quickshell-start.lock"', 'START_LOCK_FILE="${STATE_DIR}/quickshell-jay-start.lock"'),
    ]
    for old, new in substitutions:
        if old not in body:
            raise ValueError("Awtarchy Quickshell manager changed, missing: " + old)
        body = body.replace(old, new)
    if 'hyprctl ' in body or 'need hyprctl' in body:
        raise ValueError("Unported Hyprland manager IPC")
    target.write_text(body, encoding="utf-8")
    target.chmod(0o755)

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--dest", type=Path, required=True)
    o = p.parse_args()
    try:
        render(o.source, o.dest)
    except (OSError, ValueError) as exc:
        print("Jay Quickshell manager render: " + str(exc), file=sys.stderr)
        sys.exit(1)
