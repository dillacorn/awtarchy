#!/usr/bin/env python3
"""Migrate stock SpeedCrunch launcher/rules in preserved Hyprland Lua.

The updater validates the candidate and handles backups and rollback. Custom
calculator commands, window rules and all unrelated user changes are retained.
"""

from pathlib import Path
import sys

OLD_CALC = 'local calculator = "speedcrunch"'
NEW_CALC = 'local calculator = "foot --app-id awtarchy-qalc --title Qalc qalc -s \'autocalc on\'"'
OLD_CLASS = r'class = "^org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)$"'
NEW_CLASS = 'class = "^awtarchy-qalc$"'
OPACITY_ENTRY = r'|org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)'
KINDS = ("float", "size", "center")


def rule_kind(line):
    if "hl.window_rule(" not in line:
        return None
    for action in KINDS:
        if f", {action} = " in line:
            return action
    return None


def migrate(live, staged, output):
    original = live.read_text(encoding="utf-8")
    target = staged.read_text(encoding="utf-8")
    if target.count(NEW_CALC) != 1:
        raise ValueError("staged Qalc command is missing or ambiguous")

    rules = {}
    for line in target.splitlines():
        if NEW_CLASS in line:
            action = rule_kind(line)
            if action in rules:
                raise ValueError("ambiguous staged Qalc rules")
            if action:
                rules[action] = line
    if set(rules) != set(KINDS):
        raise ValueError("staged Qalc float/size/center rules are missing")

    if original.count(OLD_CALC) > 1:
        raise ValueError("ambiguous SpeedCrunch command")
    text = original.replace(OLD_CALC, NEW_CALC, 1)
    migrated = []
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if OLD_CLASS in stripped:
            action = rule_kind(stripped)
            if (
                (action == "float" and stripped.endswith(", float = true })"))
                or (action == "center" and stripped.endswith(", center = true })"))
                or (action == "size" and (
                    stripped.endswith(", size = { 347, 510 } })")
                    or stripped.endswith(
                        ', size = { "(monitor_w*0.15)", "(monitor_h*0.55)" } })'
                    )
                ))
            ):
                continue  # Exact old stock window rule; keep personalized rules.
        if OPACITY_ENTRY in line and ", opacity = " in line:
            line = line.replace(OPACITY_ENTRY, "", 1)
        migrated.append(line)

    text = "".join(migrated)
    for action in KINDS:
        matches = [
            line for line in text.splitlines()
            if NEW_CLASS in line and rule_kind(line) == action
        ]
        if len(matches) > 1:
            raise ValueError("duplicate Qalc rule in preserved user config")
        if not matches:
            if text and not text.endswith("\n"):
                text += "\n"
            text += rules[action] + "\n"

    if text != original:
        output.write_text(text, encoding="utf-8")
        print("Updated preserved calculator command and floating window rules.")


def main():
    if len(sys.argv) != 4:
        print("usage: migrate-qalc-hyprland.py LIVE STAGED OUTPUT", file=sys.stderr)
        return 2
    try:
        migrate(*(Path(arg) for arg in sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Qalc migration: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
