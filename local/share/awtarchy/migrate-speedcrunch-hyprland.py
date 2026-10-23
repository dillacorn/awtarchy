#!/usr/bin/env python3
"""Migrate only Awtarchy's old SpeedCrunch class rules in preserved Hyprland Lua.

Leave every unrelated line, user override, and custom rule untouched. Generate
a candidate for the existing updater's validation, backup, and rollback path.
"""

from pathlib import Path
import sys

OLD_CLASS = r"org\\.speedcrunch\\.speedcrunch"
NEW_CLASS = r"org\\.speedcrunch\\.(speedcrunch|SpeedCrunch)"
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

    lines = original.splitlines(keepends=True)
    matches: dict[str, int] = {}
    for index, line in enumerate(lines):
        for kind in RULES:
            if rule_kind(line, old_rules[kind]) == kind:
                if kind in matches:
                    raise ValueError(f"duplicate legacy SpeedCrunch {kind} rule")
                matches[kind] = index
                break

    if not matches:
        return 0
    # A partial set might reflect intentional customization: change nothing.
    if set(matches) != set(RULES):
        print("SpeedCrunch rule migration skipped: incomplete legacy rule set.", file=sys.stderr)
        return 0

    # Preserve all properties and exact formatting. Change only the class regex.
    for kind, index in matches.items():
        line = lines[index]
        old = old_rules[kind]
        new = new_rules[kind]
        if line.count(old) != 1:
            raise ValueError(f"legacy SpeedCrunch {kind} class is ambiguous")
        lines[index] = line.replace(old, new, 1)

    output.write_text("".join(lines), encoding="utf-8")
    return len(matches)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: migrate-speedcrunch-hyprland.py LIVE STAGED OUTPUT",
            file=sys.stderr,
        )
        return 2
    try:
        count = migrate(*(Path(arg) for arg in sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"SpeedCrunch rule migration: {exc}", file=sys.stderr)
        return 1
    if count:
        print(f"Migrated {count} legacy SpeedCrunch rules in preserved Hyprland Lua.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
