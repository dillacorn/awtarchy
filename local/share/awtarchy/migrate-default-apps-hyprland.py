#!/usr/bin/env python3
"""Restore missing Awtarchy Default Applications bindings/rules in preserved Lua.

The updater validates the candidate, handles persistent backups, and can roll
the change back. Existing shortcuts and customized rules are never replaced.
"""

from pathlib import Path
import re
import sys

SHORTCUT = "SUPER + ALT + A"
COMMAND = 'bash ~/.config/hypr/scripts/default_applications.sh'
WINDOW_CLASS = 'class = "^awtarchy-default-apps$"'
RULE_KINDS = ("float", "size", "center")
SUBMAPS = ("noalt", "vm")


def rule_kind(line: str) -> str | None:
    if line.lstrip().startswith("--") or "hl.window_rule(" not in line:
        return None
    if WINDOW_CLASS not in line:
        return None
    for kind in RULE_KINDS:
        if f", {kind} = " in line:
            return kind
    return None


def migrate(live: Path, staged: Path, output: Path) -> None:
    original = live.read_text(encoding="utf-8")
    target = staged.read_text(encoding="utf-8")

    # Do not modify an unrelated or unrecognized Hyprland configuration.
    if "hl.bind(" not in original or "hl.window_rule(" not in original:
        raise ValueError("preserved Lua does not have the expected Awtarchy structure")
    if f'local default_apps = "{COMMAND}"' not in target:
        raise ValueError("staged Default Applications command is missing")

    rules: dict[str, str] = {}
    for line in target.splitlines():
        kind = rule_kind(line)
        if kind is not None:
            if kind in rules:
                raise ValueError(f"ambiguous staged Default Applications {kind} rule")
            rules[kind] = line
    if set(rules) != set(RULE_KINDS):
        raise ValueError("staged Default Applications rules are incomplete")

    text = original
    has_binding = any(
        SHORTCUT in line for line in original.splitlines()
        if not line.lstrip().startswith("--")
    )
    if not has_binding:
        binding = f'hl.bind("{SHORTCUT}", hl.dsp.exec_cmd("{COMMAND}"), {{}})'
        # Submap definitions register their own binds. Restore both optional
        # Awtarchy modes without touching the user's existing keybindings.
        for mode in SUBMAPS:
            pattern = re.compile(
                rf'(?m)^(?P<indent>[ \t]*)hl\.define_submap\("{mode}",\s*function\(\)\)\s*$'
            )
            matches = list(pattern.finditer(text))
            if len(matches) > 1:
                raise ValueError(f"ambiguous {mode} submap definition")
            if matches:
                match = matches[0]
                insertion = "\n" + match.group("indent") + "    " + binding
                text = text[:match.end()] + insertion + text[match.end():]
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\n-- Awtarchy Default Applications: restored missing default shortcut.\n"
        text += binding + "\n"

    existing: dict[str, int] = {}
    for line in text.splitlines():
        kind = rule_kind(line)
        if kind:
            existing[kind] = existing.get(kind, 0) + 1
    if any(count > 1 for count in existing.values()):
        raise ValueError("duplicate preserved Default Applications rules")

    missing = [rules[kind] for kind in RULE_KINDS if kind not in existing]
    if missing:
        if text and not text.endswith("\n"):
            text += "\n"
        text += "\n-- Awtarchy Default Applications: restore missing floating geometry.\n"
        text += "\n".join(missing) + "\n"

    if text != original:
        output.write_text(text, encoding="utf-8")
        print("Restored missing Default Applications shortcut/window rules.")


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: migrate-default-apps-hyprland.py LIVE STAGED OUTPUT", file=sys.stderr)
        return 2
    try:
        migrate(*(Path(arg) for arg in sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Default Applications migration: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
