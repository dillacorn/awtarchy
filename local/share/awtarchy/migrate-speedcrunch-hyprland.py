#!/usr/bin/env python3
"""Migrate stock SpeedCrunch window rules in a preserved Hyprland Lua config.

Replace only recognized Awtarchy defaults. Leave unrelated window rules,
user-selected sizes, and other customizations untouched. The updater handles
candidate validation, backups, and rollback before installing this output.
"""

from pathlib import Path
import sys

OLD_CLASS = r"org\\.speedcrunch\\.speedcrunch"
NEW_CLASS = r"org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)"
OLD_SIZE = 'size = { "(monitor_w*0.15)", "(monitor_h*0.55)" }'
NEW_SIZE = "size = { 347, 510 }"
RULES = ("opacity", "float", "size", "center")


def rule_kind(line: str, class_pattern: str) -> str | None:
    if "hl.window_rule(" not in line or class_pattern not in line:
        return None
    if ", opacity = " in line and "class = " in line:
        return "opacity"
    if f'class = "{class_pattern}"' not in line:
        return None
    if ", float = true" in line:
        return "float"
    if ", size = " in line:
        return "size"
    if ", center = true" in line:
        return "center"
    return None


def migrate(live: Path, staged: Path, output: Path) -> int:
    original = live.read_text(encoding="utf-8")
    target = staged.read_text(encoding="utf-8")
    old_rules = {
        "opacity": OLD_CLASS,
        "float": f"^{OLD_CLASS}$",
        "size": f"^{OLD_CLASS}$",
        "center": f"^{OLD_CLASS}$",
    }
    new_rules = {
        "opacity": NEW_CLASS,
        "float": f"^{NEW_CLASS}$",
        "size": f"^{NEW_CLASS}$",
        "center": f"^{NEW_CLASS}$",
    }

    target_lines = target.splitlines()
    for kind in RULES:
        if sum(rule_kind(line, new_rules[kind]) == kind for line in target_lines) != 1:
            raise ValueError(f"staged Awtarchy SpeedCrunch {kind} rule is missing or ambiguous")
    target_size_rule = next(
        line for line in target_lines
        if rule_kind(line, new_rules["size"]) == "size"
    )
    if NEW_SIZE not in target_size_rule:
        raise ValueError("staged Awtarchy SpeedCrunch size no longer matches the migration")

    lines = original.splitlines(keepends=True)
    old_matches: dict[str, int] = {}
    for index, line in enumerate(lines):
        for kind in RULES:
            if rule_kind(line, old_rules[kind]) == kind:
                if kind in old_matches:
                    raise ValueError(f"duplicate legacy SpeedCrunch {kind} rule")
                old_matches[kind] = index
                break

    # A partial legacy set might reflect intentional customization.
    if old_matches and set(old_matches) != set(RULES):
        print("SpeedCrunch rule migration skipped: incomplete legacy rule set.", file=sys.stderr)
        return 0

    count = 0
    for kind, index in old_matches.items():
        line = lines[index]
        old = old_rules[kind]
        if line.count(old) != 1:
            raise ValueError(f"legacy SpeedCrunch {kind} class is ambiguous")
        lines[index] = line.replace(old, new_rules[kind], 1)
        count += 1

    size_matches = [
        index for index, line in enumerate(lines)
        if rule_kind(line, new_rules["size"]) == "size"
    ]
    if len(size_matches) > 1:
        raise ValueError("duplicate SpeedCrunch size rules")
    if size_matches:
        index = size_matches[0]
        if OLD_SIZE in lines[index]:
            if lines[index].count(OLD_SIZE) != 1:
                raise ValueError("ambiguous legacy SpeedCrunch size")
            lines[index] = lines[index].replace(OLD_SIZE, NEW_SIZE, 1)
            count += 1

    if count:
        output.write_text("".join(lines), encoding="utf-8")
    return count


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: migrate-speedcrunch-hyprland.py LIVE STAGED OUTPUT", file=sys.stderr)
        return 2
    try:
        count = migrate(*(Path(arg) for arg in sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"SpeedCrunch rule migration: {exc}", file=sys.stderr)
        return 1
    if count:
        print(f"Migrated {count} legacy SpeedCrunch rule or size changes in preserved Hyprland Lua.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
