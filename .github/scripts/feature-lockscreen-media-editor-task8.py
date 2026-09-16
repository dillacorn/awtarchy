from pathlib import Path
import hashlib

root = Path(".")
test = Path("tests/test-quickshell-lockscreen-interactive-managed-history.sh")
history = Path("local/share/awtarchy/quickshell-managed-history.sha256")

text = test.read_text(encoding="utf-8")
additions = [
    (
        "    'config/hypr/scripts/quickshell_lockscreen_editor_save.sh:.config/hypr/scripts/quickshell_lockscreen_editor_save.sh'\n",
        "    'config/hypr/scripts/quickshell_lockscreen_editor_save.sh:.config/hypr/scripts/quickshell_lockscreen_editor_save.sh'\n"
        "    'config/hypr/scripts/quickshell_lockscreen_editor.sh:.config/hypr/scripts/quickshell_lockscreen_editor.sh'\n",
    ),
    (
        "    'config/quickshell/awtarchy/LockPreviewScene.qml:.config/quickshell/awtarchy/LockPreviewScene.qml'\n",
        "    'config/quickshell/awtarchy/LockPreviewScene.qml:.config/quickshell/awtarchy/LockPreviewScene.qml'\n"
        "    'config/quickshell/awtarchy/LockMedia.qml:.config/quickshell/awtarchy/LockMedia.qml'\n",
    ),
    (
        "    'config/quickshell/awtarchy-lock/LockScene.qml:.config/quickshell/awtarchy-lock/LockScene.qml'\n",
        "    'config/quickshell/awtarchy-lock/LockScene.qml:.config/quickshell/awtarchy-lock/LockScene.qml'\n"
        "    'config/quickshell/awtarchy-lock/LockMedia.qml:.config/quickshell/awtarchy-lock/LockMedia.qml'\n",
    ),
]
for old, new in additions:
    if new in text:
        continue
    if text.count(old) != 1:
        raise SystemExit(f"managed-history test anchor changed: {old!r}")
    text = text.replace(old, new, 1)
test.write_text(text, encoding="utf-8")

managed = [
    ("config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh", ".config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"),
    ("config/hypr/scripts/quickshell_lockscreen_contrast.sh", ".config/hypr/scripts/quickshell_lockscreen_contrast.sh"),
    ("config/hypr/scripts/quickshell_lockscreen_editor.sh", ".config/hypr/scripts/quickshell_lockscreen_editor.sh"),
    ("config/quickshell/awtarchy/shell.qml", ".config/quickshell/awtarchy/shell.qml"),
    ("config/quickshell/awtarchy/QuickSettings.qml", ".config/quickshell/awtarchy/QuickSettings.qml"),
    ("config/quickshell/awtarchy/LockscreenEditor.qml", ".config/quickshell/awtarchy/LockscreenEditor.qml"),
    ("config/quickshell/awtarchy/LockPreviewScene.qml", ".config/quickshell/awtarchy/LockPreviewScene.qml"),
    ("config/quickshell/awtarchy/LockMedia.qml", ".config/quickshell/awtarchy/LockMedia.qml"),
    ("config/quickshell/awtarchy-lock/LockSurface.qml", ".config/quickshell/awtarchy-lock/LockSurface.qml"),
    ("config/quickshell/awtarchy-lock/LockScene.qml", ".config/quickshell/awtarchy-lock/LockScene.qml"),
    ("config/quickshell/awtarchy-lock/LockMedia.qml", ".config/quickshell/awtarchy-lock/LockMedia.qml"),
]

history_text = history.read_text(encoding="utf-8")
header = "\n# 2026-09-16 lockscreen media/editor polish managed hashes.\n"
entries = []
for source, installed in managed:
    data = (root / source).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in history_text:
        entries.append(line)

if entries:
    if not history_text.endswith("\n"):
        history_text += "\n"
    history_text += header + "\n".join(entries) + "\n"
    history.write_text(history_text, encoding="utf-8")
