#!/usr/bin/env python3
"""Wayland-native pixel picker for Mango's SUPER+I shortcut.

Reads one grim PPM pixel in memory; copies only the hex color, never images
or window contents. No dependency on Hyprland or an image library.
"""
from pathlib import Path
import re
import subprocess
import sys


def ppm_color(blob: bytes) -> str:
    if len(blob) > 256 * 1024:
        raise ValueError("Unexpectedly large single-pixel capture")
    pos = 0
    tokens = []
    while len(tokens) < 4:
        while pos < len(blob) and blob[pos] in b" \t\r\n":
            pos += 1
        if pos < len(blob) and blob[pos] == ord("#"):
            nl = blob.find(b"\n", pos)
            if nl == -1:
                raise ValueError("Truncated PPM comment")
            pos = nl + 1
            continue
        start = pos
        while pos < len(blob) and blob[pos] not in b" \t\r\n#":
            pos += 1
        if pos == start:
            raise ValueError("Incomplete PPM header")
        tokens.append(blob[start:pos])
    if tokens[0] != b"P6" or tokens[3] != b"255":
        raise ValueError("Unsupported PPM pixel format")
    try:
        width, height = int(tokens[1]), int(tokens[2])
    except ValueError as exc:
        raise ValueError("Invalid PPM image dimensions") from exc
    if not (1 <= width <= 32 and 1 <= height <= 32):
        raise ValueError("Invalid single-pixel screenshot dimensions")
    if pos >= len(blob) or blob[pos] not in b" \t\r\n":
        raise ValueError("Missing PPM data separator")
    pos += 1  # The next byte may itself be a whitespace-valued color.
    if len(blob) - pos != width * height * 3:
        raise ValueError("PPM pixel data is incomplete")
    return "#" + blob[pos:pos + 3].hex()


def main() -> int:
    try:
        region = subprocess.run(
            ["slurp", "-p"], text=True, capture_output=True,
            timeout=45, check=True).stdout.strip()
    except subprocess.CalledProcessError:
        return 0  # Escape cancels without modifying the clipboard.
    if not re.fullmatch(r"-?\d+,-?\d+ [1-9]\d*x[1-9]\d*", region):
        raise ValueError("Unexpected slurp pixel geometry")
    ppm = subprocess.run(["grim", "-g", region, "-t", "ppm", "-"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         timeout=8, check=True).stdout
    color = ppm_color(ppm)
    subprocess.run(["wl-copy"], input=color, text=True, timeout=8,
                   check=True)
    if Path("/usr/bin/notify-send").is_file():
        subprocess.run(["notify-send", "-a", "Awtarchy Color Picker",
                        "Color copied", color], timeout=4, check=False)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired) as exc:
        print(f"Mango color picker: {exc}", file=sys.stderr)
        sys.exit(1)
