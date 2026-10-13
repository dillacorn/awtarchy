#!/usr/bin/env python3
"""Migrate only intact pre-Foot Awtarchy Hyprland terminal commands.

Used during a managed update after preserving/merging personalized hyprland.lua.
Unknown or customized commands are never rewritten. The staged release's
Hyprland configuration supplies the replacement commands.
"""

from pathlib import Path
import sys

# Exact shipped v3.8.9 lines. Unrelated user changes survive byte-for-byte.
LEGACY_COMMANDS = (
    ("autostart", "    hl.exec_cmd(\"sh -lc 'exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e \\\"$HOME/.config/hypr/scripts/awtarchy-tips-tui.sh\\\" --autostart'\")"),
    ("terminal", "local terminal = \"alacritty\""),
    ("yazi", "local yazi = \"alacritty -o 'font.normal.family=\\\"JetBrainsMono Nerd Font Mono\\\"' -o 'font.bold.family=\\\"JetBrainsMono Nerd Font Mono\\\"' -o 'font.italic.family=\\\"JetBrainsMono Nerd Font Mono\\\"' -o 'font.bold_italic.family=\\\"JetBrainsMono Nerd Font Mono\\\"' -e yazi\""),
    ("awtarchy_tips_tui", "local awtarchy_tips_tui = \"~/.config/hypr/scripts/launch_handler.sh awtarchy-tips-tui \\\"alacritty --class awtarchy-tips-tui -e ~/.config/hypr/scripts/awtarchy-tips-tui.sh\\\"\""),
    ("wiremix", "local wiremix = \"~/.config/hypr/scripts/launch_handler.sh wiremix \\\"alacritty --class Wiremix -e wiremix\\\"\""),
    ("pulsemixer", "local pulsemixer = \"~/.config/hypr/scripts/launch_handler.sh pulsemixer \\\"alacritty --class Pulsemixer -e pulsemixer\\\"\""),
    ("wallpicker", "local wallpicker = \"~/.config/hypr/scripts/launch_handler.sh wallpicker \\\"alacritty --class wallpicker -e awtwall --resume\\\"\""),
    ("maccel", "local maccel = \"~/.config/hypr/scripts/launch_handler.sh maccel \\\"alacritty --class maccel -e maccel\\\"\""),
    ("btop", "local btop = \"~/.config/hypr/scripts/launch_handler.sh btop \\\"alacritty --class btop -e btop\\\"\""),
)


def managed_line(lines: list[str], key: str) -> str:
    if key == "autostart":
        candidates = [
            line for line in lines
            if line.lstrip().startswith('hl.exec_cmd("sh -lc ')
            and "awtarchy-tips-tui" in line and "--autostart" in line
        ]
    else:
        candidates = [
            line for line in lines
            if line.startswith(f"local {key} = ")
        ]
    if len(candidates) != 1:
        raise ValueError(f"staged Foot command is missing or ambiguous: {key}")
    line = candidates[0]
    if "foot" not in line or "alacritty" in line:
        raise ValueError(f"staged command is not Foot-based: {key}")
    return line


def migrate(live: Path, target: Path, output: Path) -> int:
    original = live.read_text(encoding="utf-8")
    staged = target.read_text(encoding="utf-8").splitlines()
    result = original.splitlines(keepends=True)
    count = 0
    for key, legacy in LEGACY_COMMANDS:
        indices = [
            index for index, line in enumerate(result)
            if line.rstrip("\r\n") == legacy
        ]
        if len(indices) > 1:
            raise ValueError(f"duplicate legacy Awtarchy terminal command: {key}")
        if not indices:
            continue
        replacement = managed_line(staged, key)
        i = indices[0]
        ending = "\r\n" if result[i].endswith("\r\n") else ("\n" if result[i].endswith("\n") else "")
        result[i] = replacement + ending
        count += 1
    if count:
        output.write_text("".join(result), encoding="utf-8")
    return count


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: migrate-foot-hyprland.py LIVE_HYPRLAND STAGED_HYPRLAND OUTPUT", file=sys.stderr)
        return 2
    try:
        count = migrate(*(Path(arg) for arg in sys.argv[1:]))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"Foot Hyprland migration: {exc}", file=sys.stderr)
        return 1
    if count:
        print(f"Migrated {count} known legacy Alacritty launch commands to Foot.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
