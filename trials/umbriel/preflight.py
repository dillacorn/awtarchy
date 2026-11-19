#!/usr/bin/env python3
"""Read-only Umbriel suitability survey. Never install or modify packages."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import subprocess

VENDORS = {
    "0x1002": "AMD",
    "0x8086": "Intel",
    "0x10de": "NVIDIA",
}
PACKAGE_NAMES = ("umbriel", "umbriel-git", "xdg-desktop-portal-umbriel")
COMPOSITOR_NAMES = ("hyprland", "sway", "kwin", "jay")


def probe_package(name: str, action: str) -> bool | None:
    """Use only local pacman databases; never download/synchronize them."""
    if not shutil.which("pacman"):
        return None
    try:
        result = subprocess.run(
            ["pacman", action, "--", name],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.returncode == 0


def gpu_cards(sysfs_root: Path) -> list[tuple[str, str]]:
    """sysfs card nodes may be symlinks by design; only read their vendor IDs."""
    cards = []
    for node in sorted(sysfs_root.glob("card[0-9]*")):
        if not re.fullmatch(r"card[0-9]+", node.name):
            continue
        try:
            vendor = (node / "device/vendor").read_text(
                encoding="ascii"
            ).strip().lower()
        except (OSError, UnicodeError):
            continue
        cards.append((node.name, VENDORS.get(vendor, f"unknown ({vendor})")))
    return cards


def session_entries(path: Path) -> list[tuple[str, str]]:
    if path.is_symlink() or not path.is_dir():
        return []
    result = []
    for entry in sorted(path.glob("*.desktop")):
        if entry.is_symlink() or not entry.is_file():
            continue
        try:
            contents = entry.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        name = next(
            (s[5:] for s in contents.splitlines() if s.startswith("Name=")),
            "(unnamed)",
        )
        result.append((entry.name, name))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sysfs-root", type=Path,
                        default=Path("/sys/class/drm"))
    parser.add_argument("--session-dir", type=Path,
                        default=Path("/usr/share/wayland-sessions"))
    args = parser.parse_args()

    print("Awtarchy Umbriel feasibility survey (READ ONLY)")
    print("No installation, configuration, or Ly changes.\n")

    print("Detected DRM GPUs (vendor only; features NOT assumed):")
    cards = gpu_cards(args.sysfs_root)
    if cards:
        for card, vendor in cards:
            print(f"  {card}: {vendor}")
    else:
        print("  No readable DRM vendor IDs; hybrid GPUs may be missing.")

    print("\nRepository metadata and installed packages (local pacman data):")
    for package in PACKAGE_NAMES:
        available = probe_package(package, "-Si")
        installed = probe_package(package, "-Qq")
        status = lambda value: (
            "yes" if value is True else "no" if value is False else "unknown"
        )
        print(f"  {package}: repository={status(available)}, "
              f"installed={status(installed)}")

    print("\nExisting compositors (installed packages only):")
    for compositor in COMPOSITOR_NAMES:
        installed = probe_package(compositor, "-Qq")
        if installed is True:
            print(f"  {compositor}: installed")

    print("\nStandard Wayland session files (not authoritative for custom Ly paths):")
    entries = session_entries(args.session_dir)
    if entries:
        for filename, name in entries:
            print(f"  {filename}: {name}")
    else:
        print("  None accessible")

    print("\nDECISION: inspection only; no Umbriel session installed.")
    print("GPU vendor detection does not prove NVIDIA, tearing, HDR, "
          "VRR or direct-scanout compatibility.")
    print("Do not install AUR or third-party packages automatically.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
