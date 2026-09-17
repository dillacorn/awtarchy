#!/usr/bin/env python3
from pathlib import Path
import hashlib
import re
import sys

root = Path(".")
test_path = root / "tests/test-quickshell-lockscreen-interactive-managed-history.sh"
history_path = root / "local/share/awtarchy/quickshell-managed-history.sha256"

mode = sys.argv[1] if len(sys.argv) > 1 else "all"
if mode not in {"coverage", "history", "all"}:
    raise SystemExit("usage: feature-lockscreen-monitor-profile-task8.py [coverage|history|all]")

text = test_path.read_text(encoding="utf-8")
hypr_entry = "    'config/hypr/hyprland.lua:.config/hypr/hyprland.lua'\n"
if mode in {"coverage", "all"} and hypr_entry not in text:
    anchor = "managed_files=(\n"
    if anchor not in text:
        raise SystemExit("managed_files anchor missing")
    text = text.replace(anchor, anchor + hypr_entry, 1)
    test_path.write_text(text, encoding="utf-8")

if mode in {"history", "all"}:
    text = test_path.read_text(encoding="utf-8")
    entries = []
    in_array = False
    for line in text.splitlines():
        if line.strip() == "managed_files=(":
            in_array = True
            continue
        if in_array and line.strip() == ")":
            break
        if not in_array:
            continue
        match = re.fullmatch(r"\s*'([^']+):([^']+)'\s*", line)
        if match:
            entries.append((match.group(1), match.group(2)))

    if not entries:
        raise SystemExit("no managed files parsed")

    history = history_path.read_text(encoding="utf-8")
    missing = []
    for source, installed in entries:
        source_path = root / source
        if not source_path.is_file():
            raise SystemExit(f"managed source missing: {source}")
        digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
        record = f"{digest}\t{installed}"
        if record not in history.splitlines():
            missing.append(record)

    if missing:
        if history and not history.endswith("\n"):
            history += "\n"
        history += "\n# 2026-09-17 lockscreen media editor and multi-monitor profile stock hashes.\n"
        history += "\n".join(missing) + "\n"
        history_path.write_text(history, encoding="utf-8")
