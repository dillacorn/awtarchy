#!/usr/bin/env python3
"""Set Awtarchy's managed Hyprland cursor policy for the installed GPU."""

import argparse
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile


GPU_PCI_VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}
CURSOR_HEADER = re.compile(r"(?m)^([ \t]*)cursor[ \t]*=[ \t]*\{[ \t]*$")
CURSOR_MODE = re.compile(
    r"(?m)^[ \t]*no_hardware_cursors[ \t]*=[ \t]*([012])([ \t]*,[^\n]*)$"
)


def detect_gpu(sysfs_root: Path) -> str | None:
    """Return nvidia, other, or unknown; NVIDIA wins on hybrid machines."""
    vendors = set()
    for path in sysfs_root.glob("card[0-9]*/device/vendor"):
        try:
            vendor = path.read_text(encoding="ascii").strip().lower()
        except (OSError, UnicodeError):
            continue
        if vendor in GPU_PCI_VENDORS:
            vendors.add(GPU_PCI_VENDORS[vendor])

    # Catch NVIDIA GPUs which are present on PCI but not exposed as DRM cards.
    try:
        output = subprocess.run(
            ["lspci", "-nn"], check=False, capture_output=True,
            text=True, timeout=3,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        output = ""

    for line in output.splitlines():
        if not re.search(
            r"\b(?:VGA compatible|3D|Display|2D) controller\b",
            line, re.IGNORECASE,
        ):
            continue
        for pci_id, vendor in GPU_PCI_VENDORS.items():
            if re.search(r"\[" + pci_id[2:] + r":[0-9a-f]{4}\]", line, re.IGNORECASE):
                vendors.add(vendor)

    if "nvidia" in vendors:
        return "nvidia"
    if vendors.intersection({"amd", "intel"}):
        return "other"
    return None


def cursor_mode_match(text: str):
    """Find the single literal policy inside the managed cursor table."""
    headers = list(CURSOR_HEADER.finditer(text))
    if len(headers) != 1:
        return None

    header = headers[0]
    indent = header.group(1)
    end_pattern = re.compile(
        r"(?m)^" + re.escape(indent) + r"\},[ \t]*(?:--[^\n]*)?$"
    )
    end = end_pattern.search(text, header.end())
    if end is None:
        return None

    start = header.end()
    body = text[start:end.start()]
    modes = list(CURSOR_MODE.finditer(body))
    if len(modes) != 1:
        return None
    match = modes[0]
    return start + match.start(1), start + match.end(1), match.group(1)


def apply_policy(config: Path, gpu: str | None, fallback: Path | None = None) -> str:
    if config.is_symlink() or not config.is_file():
        raise ValueError(f"Hyprland cursor target is not a regular file: {config}")

    original = config.read_text(encoding="utf-8")
    match = cursor_mode_match(original)
    if match is None:
        return "skipped (cursor setting is not in the expected Awtarchy format)"

    if gpu == "nvidia":
        desired = "1"
    elif gpu == "other":
        desired = "2"
    else:
        desired = None
        if fallback is not None and fallback.is_file() and not fallback.is_symlink():
            old_match = cursor_mode_match(fallback.read_text(encoding="utf-8"))
            if old_match:
                desired = old_match[2]
        if desired is None:
            return "skipped (GPU detection unavailable)"

    start, end, old = match
    if old == desired:
        return f"unchanged ({desired})"

    updated = original[:start] + desired + original[end:]
    fd, temporary = tempfile.mkstemp(prefix=".awtarchy-gpu-cursor-", dir=config.parent)
    try:
        os.fchmod(fd, stat.S_IMODE(config.stat().st_mode))
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(updated)
        os.replace(temporary, config)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return f"updated ({old} -> {desired})"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--fallback", type=Path)
    parser.add_argument("--sysfs-root", type=Path, default=Path("/sys/class/drm"))
    args = parser.parse_args()

    gpu = detect_gpu(args.sysfs_root)
    result = apply_policy(args.config, gpu, args.fallback)
    print(f"GPU cursor policy ({gpu or 'unknown'}): {result}")


if __name__ == "__main__":
    main()
