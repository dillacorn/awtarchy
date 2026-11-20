#!/usr/bin/env python3
"""Render the existing Awtarchy manager with Umbriel-only monitor IPC."""
import argparse
import importlib.util
from pathlib import Path
import sys


def render(repo, destination):
    sway = repo / "trials/sway/render-manager.py"
    spec = importlib.util.spec_from_file_location("awtarchy_sway_manager_renderer", sway)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.render(repo / "config/hypr/scripts/quickshell.sh", destination)
    body = destination.read_text(encoding="utf-8")
    replacements = (
        ("awtarchy-sway", "awtarchy-umbriel"),
        ("quickshell-sway", "quickshell-umbriel"),
        ("need swaymsg", "need umbriel"),
        ("/sway/awtarchy-trial/", "/umbriel/awtarchy-trial/"),
    )
    for old, new in replacements:
        body = body.replace(old, new)
    if 'need swaymsg' in body or 'swaymsg ' in body or 'hyprctl ' in body:
        raise ValueError("Unported compositor-specific manager call")
    destination.write_text(body, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--dest", type=Path, required=True)
    args = parser.parse_args()
    try:
        render(args.repo, args.dest)
    except (OSError, ValueError) as error:
        print("Umbriel manager render: " + str(error), file=sys.stderr)
        sys.exit(1)
