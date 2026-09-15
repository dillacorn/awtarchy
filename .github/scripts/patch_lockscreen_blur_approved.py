#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, found {count}: {old!r}")
    target.write_text(text.replace(old, new, 1))


def replace_all_exact(path: str, old: str, new: str, expected: int) -> None:
    target = ROOT / path
    text = target.read_text()
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} matches, found {count}: {old!r}")
    target.write_text(text.replace(old, new))


state = "config/hypr/scripts/quickshell_application_state.sh"
replace_once(state,
'''        lockscreen_wallpaper_blur: 0,
        lockscreen_blur_style: "smooth",''',
'''        lockscreen_wallpaper_blur: 10,
        lockscreen_blur_style: "pixelated",''')
replace_once(state,
'''normalize_lockscreen_visualizer_json() {''',
'''normalize_lockscreen_blur_integer() {
    local value="$1" label="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || {
        printf '%s must be an integer\\n' "$label" >&2
        exit 2
    }
    local numeric=$((10#$value))
    (( numeric >= 0 && numeric <= 200 )) || {
        printf '%s must be 0-200\\n' "$label" >&2
        exit 2
    }
    printf '%d' "$numeric"
}

normalize_lockscreen_visualizer_json() {''')
replace_once(state, 'local wallpaper_blur="${11:-0}"', 'local wallpaper_blur="${11:-10}"')
replace_once(state, 'local blur_style="${19:-smooth}"', 'local blur_style="${19:-pixelated}"')
replace_once(state,
'''wallpaper_blur="$(normalize_percent_integer "$wallpaper_blur" 'lockscreen wallpaper blur')"''',
'''wallpaper_blur="$(normalize_lockscreen_blur_integer "$wallpaper_blur" 'lockscreen wallpaper blur')"''')
replace_once(state,
'''        | .lockscreen_wallpaper_blur = 0
        | .lockscreen_blur_style = "smooth"''',
'''        | .lockscreen_wallpaper_blur = 10
        | .lockscreen_blur_style = "pixelated"''')

bar = "config/quickshell/awtarchy/BarState.qml"
replace_once(bar,
'''        lockscreen_wallpaper_blur: 0,
        lockscreen_blur_style: "smooth",''',
'''        lockscreen_wallpaper_blur: 10,
        lockscreen_blur_style: "pixelated",''')
replace_once(bar,
'''return Number.isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : 0;
    }

    function lockscreenBlurStyle() {
        const value = String(data().lockscreen_blur_style || "smooth");
        return ["smooth", "pixelated"].indexOf(value) >= 0 ? value : "smooth";''',
'''return Number.isFinite(value) ? Math.max(0, Math.min(200, Math.round(value))) : 10;
    }

    function lockscreenBlurStyle() {
        const value = String(data().lockscreen_blur_style || "pixelated");
        return ["smooth", "pixelated"].indexOf(value) >= 0 ? value : "pixelated";''')

editor = "config/quickshell/awtarchy/LockscreenEditor.qml"
replace_once(editor, 'property int draftWallpaperBlur: 0\n    property string draftBlurStyle: "smooth"',
             'property int draftWallpaperBlur: 10\n    property string draftBlurStyle: "pixelated"')
replace_once(editor,
'''draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(100, Math.round(wallpaperBlur))) : 0;''',
'''draftWallpaperBlur = Number.isFinite(wallpaperBlur)
            ? Math.max(0, Math.min(200, Math.round(wallpaperBlur))) : 10;''')
replace_once(editor,
'''draftBlurStyle = ["smooth", "pixelated"].indexOf(String(snapshot.blurStyle)) >= 0
            ? String(snapshot.blurStyle) : "smooth";''',
'''draftBlurStyle = ["smooth", "pixelated"].indexOf(String(snapshot.blurStyle)) >= 0
            ? String(snapshot.blurStyle) : "pixelated";''')
replace_once(editor,
'''setDraftWallpaperBlur(Number(pointerX) * 100 / Number(trackWidth));''',
'''setDraftWallpaperBlur(Number(pointerX) * 200 / Number(trackWidth));''')
replace_once(editor,
'''draftWallpaperBlur = Math.max(0, Math.min(100, Math.round(next)));''',
'''draftWallpaperBlur = Math.max(0, Math.min(200, Math.round(next)));''')
replace_once(editor,
'''function resetDraftWallpaperBlur() { setDraftWallpaperBlur(0); }''',
'''function resetDraftWallpaperBlur() { setDraftWallpaperBlur(10); }''')
replace_once(editor,
'''draftWallpaperFit = "cover"; draftWallpaperFocalX = 0.5; draftWallpaperFocalY = 0.5; draftOverlayMode = "none"; draftOverlayStrength = 0; draftWallpaperBlur = 0; draftBlurStyle = "smooth"; draftWallpaperBlurExplicit = false;''',
'''draftWallpaperFit = "cover"; draftWallpaperFocalX = 0.5; draftWallpaperFocalY = 0.5; draftOverlayMode = "none"; draftOverlayStrength = 0; draftWallpaperBlur = 10; draftBlurStyle = "pixelated"; draftWallpaperBlurExplicit = false;''')
replace_once(editor,
'''Rectangle { width: root.draftWallpaperBlur * parent.width / 100; height: parent.height; radius: height / 2; color: Theme.focus }
                            Rectangle { x: root.draftWallpaperBlur * parent.width / 100 - width / 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Theme.foreground }''',
'''Rectangle { width: root.draftWallpaperBlur * parent.width / 200; height: parent.height; radius: height / 2; color: Theme.focus }
                            Rectangle { x: root.draftWallpaperBlur * parent.width / 200 - width / 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: Theme.foreground }''')
replace_once(editor,
'''validator: IntValidator { bottom: 0; top: 100 }
                             selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftWallpaperBlur(text)''',
'''validator: IntValidator { bottom: 0; top: 200 }
                             selectByMouse: true; font.pixelSize: 9; onEditingFinished: root.setDraftWallpaperBlur(text)''')

scene_helper_anchor = '''    function wallpaperGeometry() {'''
scene_helpers = '''    function smoothBlurMaximum() {
        const value = Math.max(0, Math.min(200, Number(root.wallpaperBlur)));
        const extra = Math.max(0, Math.min(1, (value - 100) / 100));
        return Math.round(32 + 96 * extra);
    }

    function pixelBlurFactor() {
        const value = Math.max(0, Math.min(200, Number(root.wallpaperBlur)));
        const base = 63 * Math.pow(Math.max(0, Math.min(1, value / 100)), 1.2);
        const extra = 64 * Math.max(0, Math.min(1, (value - 100) / 100));
        return 1 + base + extra;
    }

    function wallpaperGeometry() {'''
for scene in ("config/quickshell/awtarchy/LockPreviewScene.qml", "config/quickshell/awtarchy-lock/LockScene.qml"):
    replace_once(scene, scene_helper_anchor, scene_helpers)
    replace_once(scene, 'blurMax: 32', 'blurMax: root.smoothBlurMaximum()')
    replace_once(scene,
'''readonly property real pixelFactor: 1
            + 63 * Math.pow(Math.max(0, Math.min(1, root.wallpaperBlur / 100)), 1.2)''',
'''readonly property real pixelFactor: root.pixelBlurFactor()''')

shell = "config/quickshell/awtarchy-lock/shell.qml"
replace_once(shell, 'property int lockWallpaperBlur: 0\n    property string lockBlurStyle: "smooth"',
             'property int lockWallpaperBlur: 10\n    property string lockBlurStyle: "pixelated"')
replace_once(shell,
'''readonly property int wallpaperBlur: normalizedPercent(lockWallpaperBlur)''',
'''readonly property int wallpaperBlur: normalizedBlurPercent(lockWallpaperBlur)''')
replace_once(shell,
'''function normalizedBlurStyle(value) {
        const key = String(value || "");
        return ["smooth", "pixelated"].indexOf(key) >= 0 ? key : "smooth";
    }

    function normalizedUnitInterval''',
'''function normalizedBlurStyle(value) {
        const key = String(value || "");
        return ["smooth", "pixelated"].indexOf(key) >= 0 ? key : "pixelated";
    }

    function normalizedBlurPercent(value) {
        const numeric = Number(value);
        return Number.isFinite(numeric) ? Math.max(0, Math.min(200, Math.round(numeric))) : 10;
    }

    function normalizedUnitInterval''')
replace_all_exact(shell, 'lockWallpaperBlur = 0;\n        lockBlurStyle = "smooth";',
                  'lockWallpaperBlur = 10;\n        lockBlurStyle = "pixelated";', 1)
replace_all_exact(shell, 'lockWallpaperBlur = normalizedPercent(parsed.lockscreen_wallpaper_blur);',
                  'lockWallpaperBlur = normalizedBlurPercent(parsed.lockscreen_wallpaper_blur);', 1)
