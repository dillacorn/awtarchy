#!/usr/bin/env python3
"""Validate Awtarchy stable release notes before publication."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_HEADINGS = (
    "## Install and update",
    "## Validation",
)

FORBIDDEN_HEADINGS = (
    "## Post-release updates",
)

INSTALL_GUIDE_URL = "https://github.com/dillacorn/awtarchy/blob/main/INSTALL.md"
UPDATING_GUIDE_URL = "https://github.com/dillacorn/awtarchy/blob/main/UPDATING.md"


def fail(message: str) -> None:
    print(f"release-notes validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def section(body: str, heading: str) -> str:
    marker = f"{heading}\n"
    if body.count(marker) != 1:
        fail(f"expected exactly one {heading!r} heading")
    start = body.index(marker) + len(marker)
    next_heading = re.search(r"(?m)^## ", body[start:])
    end = start + next_heading.start() if next_heading else len(body)
    return body[start:end].strip()


def require_text(haystack: str, needle: str, context: str) -> None:
    if needle not in haystack:
        fail(f"{context} is missing required text: {needle}")


def validate(
    version: str,
    notes_path: Path,
    previous_path: Path | None,
    release_title: str | None,
) -> None:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
        fail(f"invalid stable version {version!r}; expected vX.Y.Z")

    body = notes_path.read_text(encoding="utf-8")
    title_prefix = f"Awtarchy {version}"
    first_line = body.partition("\n")[0]

    if release_title is not None:
        if release_title != title_prefix and not release_title.startswith(title_prefix + " "):
            fail(
                f"release title must be {title_prefix!r} or begin with "
                f"{(title_prefix + ' ')!r}"
            )
        expected_heading = f"# {release_title}"
        if first_line != expected_heading:
            fail(f"release must start with {expected_heading!r}")
    else:
        expected_heading = f"# {title_prefix}"
        if first_line != expected_heading and not first_line.startswith(expected_heading + " "):
            fail(
                f"release must start with {expected_heading!r} or a themed "
                f"suffix such as {expected_heading + ' Yazi'!r}"
            )

    title_end = len(first_line) + 1
    install_update_pos = body.find("## Install and update")
    if install_update_pos < 0 or not body[title_end:install_update_pos].strip():
        fail("release overview is missing before Install and update")

    positions: list[int] = []
    for heading in REQUIRED_HEADINGS:
        marker = f"{heading}\n"
        if body.count(marker) != 1:
            fail(f"expected exactly one {heading!r} heading")
        positions.append(body.index(marker))
    if positions != sorted(positions):
        fail("required stable release sections are out of order")

    install_update = section(body, "## Install and update")
    require_text(install_update, INSTALL_GUIDE_URL, "Install and update")
    require_text(install_update, UPDATING_GUIDE_URL, "Install and update")

    validation = section(body, "## Validation")
    if not validation:
        fail("Validation section is empty")

    for heading in FORBIDDEN_HEADINGS:
        if heading in body:
            fail(f"retired stable release section is not allowed: {heading}")

    if previous_path is not None:
        previous = previous_path.read_text(encoding="utf-8")
        for heading in REQUIRED_HEADINGS:
            if heading in previous and heading not in body:
                fail(f"protected section from previous stable release disappeared: {heading}")

    print(f"PASS: stable release notes satisfy the {version} release contract")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--title")
    parser.add_argument("--notes", required=True, type=Path)
    parser.add_argument("--previous", type=Path)
    args = parser.parse_args()
    validate(args.version, args.notes, args.previous, args.title)


if __name__ == "__main__":
    main()
