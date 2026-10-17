#!/usr/bin/env python3
"""Suppress only CachyOS's stock Fish Fastfetch greeting for Awtarchy users.

Never replace a custom Fish greeting or change package-owned configuration.
The default user template sources CachyOS's system greeting before the user
may override fish_greeting; a final empty function opts out safely.
"""

import argparse
from datetime import datetime
import os
from pathlib import Path
import pwd
import re
import stat
import tempfile

CACHY_SOURCE = "source /usr/share/cachyos-fish-config/cachyos-config.fish"
OVERRIDE = (
    "\n# Awtarchy: keep interactive Foot/Fish terminals free of the CachyOS Fastfetch greeting.\n"
    "# Run fastfetch manually whenever desired.\n"
    "function fish_greeting\n"
    "end\n"
)


def apply(home: Path, vendor: Path, shell: str) -> str:
    if Path(shell).name != "fish":
        return "skip"
    if not vendor.is_file() or vendor.is_symlink():
        return "skip"
    vendor_text = vendor.read_text(encoding="utf-8", errors="replace")
    if not re.search(r"(?m)^\s*function\s+fish_greeting\s*$", vendor_text):
        return "skip"
    if not re.search(r"(?m)^\s*fastfetch(?:\s|$)", vendor_text):
        return "skip"

    fish_dir = home / ".config" / "fish"
    config = fish_dir / "config.fish"
    if fish_dir.is_symlink() or config.is_symlink() or not config.is_file():
        return "skip"
    info = config.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1:
        return "skip"
    if info.st_size > 131072:
        return "skip"

    original = config.read_bytes()
    try:
        source = original.decode("utf-8")
    except UnicodeDecodeError:
        return "skip"
    # Only the known CachyOS default template is safe to adjust silently.
    # Any uncommented customization (including an existing greeting) wins.
    active = [line.strip() for line in source.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    if active != [CACHY_SOURCE]:
        return "skip"

    output = source.rstrip("\n") + "\n" + OVERRIDE
    if output.encode("utf-8") == original:
        return "skip"

    # Preserve original bytes before an atomic, mode-preserving replacement.
    # Neither package-managed /usr/share files nor symlinks are touched.
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = fish_dir / f"config.fish.backup.{timestamp}"
    backup_fd = None
    temp_path = None
    try:
        backup_fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                            stat.S_IMODE(info.st_mode))
        with os.fdopen(backup_fd, "wb") as stream:
            backup_fd = None
            stream.write(original)
            stream.flush()
            os.fsync(stream.fileno())

        with tempfile.NamedTemporaryFile(mode="wb", dir=fish_dir,
                                         prefix=".awtarchy-fish-", delete=False) as stream:
            temp_path = Path(stream.name)
            stream.write(output.encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_path, stat.S_IMODE(info.st_mode))
        # Re-check the target immediately before replacing it.
        latest = config.stat()
        if (latest.st_dev, latest.st_ino, latest.st_size, latest.st_mtime_ns) != (
                info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns):
            raise RuntimeError("Fish config changed during greeting adjustment")
        os.replace(temp_path, config)
        temp_path = None
        return "changed"
    finally:
        if backup_fd is not None:
            os.close(backup_fd)
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, required=True)
    # These overrides support hermetic fixtures. Production callers use defaults.
    parser.add_argument("--vendor-config", type=Path,
                        default=Path("/usr/share/cachyos-fish-config/cachyos-config.fish"))
    parser.add_argument("--shell", default=pwd.getpwuid(os.geteuid()).pw_shell)
    args = parser.parse_args()
    try:
        result = apply(args.home, args.vendor_config, args.shell)
    except (OSError, RuntimeError) as error:
        print(f"CachyOS Fish greeting adjustment failed: {error}", file=__import__("sys").stderr)
        return 1
    if result == "changed":
        print("Disabled CachyOS's automatic Fish Fastfetch greeting (original backed up).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
