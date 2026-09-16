#!/usr/bin/env python3
from pathlib import Path


def replace_all(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"missing patch target: {label}")
    path.write_text(text.replace(old, new))


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"missing/ambiguous patch target: {label}")
    path.write_text(text.replace(old, new, 1))


picker = Path("config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh")
replace_all(
    picker,
    "--select-only --type images --resume",
    "--select-only --type all --resume",
    "Awtwall all-media filter",
)

runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")
replace_once(
    runtime,
    "hyprsunset quickshell grim satty",
    "hyprsunset quickshell qt6-multimedia qt6-multimedia-ffmpeg grim satty",
    "mandatory Qt Multimedia packages",
)

picker_test = Path("tests/test-quickshell-lockscreen-picker-targeting.sh")
replace_once(
    picker_test,
    "require_text \"$PICKER\" '--select-only --type images' \\\n    'picker no longer uses Awtwall selection-only mode'",
    "require_text \"$PICKER\" '--select-only --type all' \\\n    'picker no longer uses Awtwall all-media selection-only mode'",
    "picker targeting media expectation",
)

acceptance_test = Path("tests/test-quickshell-lockscreen-runtime-acceptance-187.sh")
replace_once(
    acceptance_test,
    "has \"$PICKER\" '--select-only --type images' 'picker no longer uses selection-only mode'",
    "has \"$PICKER\" '--select-only --type all' 'picker no longer uses all-media selection-only mode'",
    "runtime acceptance picker expectation",
)

polish_test = Path("tests/test-quickshell-lockscreen-runtime-polish.sh")
replace_once(
    polish_test,
    "require_text \"$PICKER_HELPER\" '--type' \\\n    'lockscreen wallpaper picker does not filter to images'\nrequire_text \"$PICKER_HELPER\" 'images' \\\n    'lockscreen wallpaper picker does not request image media'",
    "require_text \"$PICKER_HELPER\" '--type all' \\\n    'lockscreen wallpaper picker does not expose all supported Awtwall media'",
    "runtime polish media expectation",
)
