#!/usr/bin/env python3
from pathlib import Path

path = Path(".github/scripts/feature-lockscreen-monitor-profile-task3.py")
text = path.read_text(encoding="utf-8")
replacements = {
    'and (["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"] | index(.spawn_animation) != null)':
        'and (.spawn_animation as $spawn | ["none", "pixel-warp", "closest-edge", "top", "bottom", "left", "right"] | index($spawn) != null)',
    'and (["during-logo", "after-logo"] | index(.spawn_timing) != null)':
        'and (.spawn_timing as $timing | ["during-logo", "after-logo"] | index($timing) != null)',
    'and (["left", "center", "right"] | index(.alignment) != null)':
        'and (.alignment as $alignment | ["left", "center", "right"] | index($alignment) != null)',
}
for old, new in replacements.items():
    if old not in text and new not in text:
        raise SystemExit(f"Task 3 enum anchor missing: {old}")
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
