#!/usr/bin/env python3
from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SURFACE = ROOT / "config/quickshell/awtarchy-lock/LockSurface.qml"
SCENES = [
    ROOT / "config/quickshell/awtarchy-lock/LockScene.qml",
    ROOT / "config/quickshell/awtarchy/LockPreviewScene.qml",
]
BACKGROUND_TEST = ROOT / "tests/test-quickshell-lockscreen-background-composition.sh"
BLUR_TEST = ROOT / "tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh"
THIRD_TEST = ROOT / "tests/test-quickshell-lockscreen-third-runtime-pass.sh"
ACCEPTANCE_TEST = ROOT / "tests/test-quickshell-lockscreen-runtime-acceptance-187.sh"
HISTORY = ROOT / "local/share/awtarchy/quickshell-managed-history.sha256"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one replacement target, found {count}")
    path.write_text(text.replace(old, new, 1))


def regex_once(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one regex replacement target, found {count}")
    path.write_text(updated)


# Keep LockSurface's frozen desktop as the raw transition source and fail-closed
# backing only. The final background blur is owned by LockScene after the
# configured translucent background has been composited over this frozen frame.
replace_once(
    SURFACE,
    """                visible: status === Image.Ready\n\n                layer.enabled: root.transitionComplete\n                    && root.wallpaperBlur > 0\n                    && root.blurStyle === \"smooth\"\n                layer.effect: MultiEffect {\n                    autoPaddingEnabled: false\n                    blurEnabled: true\n                    blurMax: 32\n                    blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))\n                }\n            }\n\n\n            ShaderEffectSource {\n                id: desktopCapturePixelatedBlur\n                anchors.fill: parent\n                sourceItem: desktopCapture\n                hideSource: root.transitionComplete\n                    && root.wallpaperBlur > 0\n                    && root.blurStyle === \"pixelated\"\n                    && desktopCapture.status === Image.Ready\n                live: true\n                recursive: false\n                smooth: false\n                readonly property real pixelFactor: 1\n                    + 63 * Math.pow(Math.max(0, Math.min(1, root.wallpaperBlur / 100)), 1.2)\n                textureSize: Qt.size(\n                    Math.max(1, Math.round(width / pixelFactor)),\n                    Math.max(1, Math.round(height / pixelFactor)))\n                visible: root.transitionComplete\n                    && root.wallpaperBlur > 0\n                    && root.blurStyle === \"pixelated\"\n                    && desktopCapture.status === Image.Ready\n            }\n""",
    """                visible: status === Image.Ready\n            }\n""",
)
replace_once(
    SURFACE,
    """            backgroundOpacity: root.backgroundOpacity\n            previewMode: false\n""",
    """            backgroundOpacity: root.backgroundOpacity\n            desktopBackingSource: desktopBacking\n            previewMode: false\n""",
)

# Both secure and editor scene copies use one ordering: optional frozen desktop,
# configured background at Background Opacity, then one final blur operation.
# Foreground lockscreen UI remains outside this composition.
background_block = """    Item {\n        id: backgroundCompositionContent\n        anchors.fill: parent\n\n        ShaderEffectSource {\n            id: desktopBackingTexture\n            anchors.fill: parent\n            sourceItem: root.desktopBackingSource\n            hideSource: root.desktopBackingSource !== null\n            live: true\n            recursive: false\n            smooth: true\n            visible: root.desktopBackingSource !== null\n        }\n\n        Item {\n            id: backgroundLayer\n            anchors.fill: parent\n            opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100\n\n            Rectangle {\n                anchors.fill: parent\n                color: root.backgroundMode === \"color\" ? root.backgroundColor : \"#000000\"\n            }\n\n            Image {\n                id: wallpaperImage\n                readonly property var geometry: root.wallpaperGeometry()\n                x: geometry.x\n                y: geometry.y\n                width: geometry.width\n                height: geometry.height\n                visible: root.backgroundMode === \"wallpaper\" && root.wallpaperSource.length > 0\n                source: root.wallpaperSource\n                fillMode: Image.Stretch\n                asynchronous: true\n                cache: true\n            }\n\n            Rectangle {\n                id: backgroundOverlay\n                anchors.fill: parent\n                visible: root.overlayMode !== \"none\" && root.overlayStrength > 0\n                color: root.overlayMode === \"light\" ? \"#ffffff\" : \"#000000\"\n                opacity: Math.max(0, Math.min(100, root.overlayStrength)) / 100\n            }\n        }\n\n        layer.enabled: root.wallpaperBlur > 0\n            && root.blurStyle === \"smooth\"\n        layer.effect: MultiEffect {\n            autoPaddingEnabled: false\n            blurEnabled: true\n            blurMax: 32\n            blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))\n        }\n    }\n\n    ShaderEffectSource {\n        id: backgroundCompositionPixelatedBlur\n        anchors.fill: parent\n        sourceItem: backgroundCompositionContent\n        hideSource: root.wallpaperBlur > 0\n            && root.blurStyle === \"pixelated\"\n        live: true\n        recursive: false\n        smooth: false\n        readonly property real pixelFactor: 1\n            + 63 * Math.pow(Math.max(0, Math.min(1, root.wallpaperBlur / 100)), 1.2)\n        textureSize: Qt.size(\n            Math.max(1, Math.round(width / pixelFactor)),\n            Math.max(1, Math.round(height / pixelFactor)))\n        visible: root.wallpaperBlur > 0\n            && root.blurStyle === \"pixelated\"\n    }\n\n"""

for scene in SCENES:
    replace_once(
        scene,
        """    required property var audioBands\n    required property int backgroundOpacity\n\n    property bool previewMode: false\n""",
        """    required property var audioBands\n    required property int backgroundOpacity\n    property Item desktopBackingSource: null\n\n    property bool previewMode: false\n""",
    )
    regex_once(
        scene,
        r"    Item \{\n        id: backgroundLayer\n.*?\n    \}\n\n    Item \{\n        id: visualLayer",
        background_block + "    Item {\n        id: visualLayer",
    )

if SCENES[0].read_bytes() != SCENES[1].read_bytes():
    raise SystemExit("secure/editor LockScene parity diverged after composition patch")

# Permanent contracts now describe one final background composition rather than
# two independently blurred image inputs.
regex_once(
    BACKGROUND_TEST,
    r"# LockScene renders exactly one wallpaper source:.*?\n# Secure LockSurface owns the frozen-desktop blur\..*?\n(?=# Detailed composition stays editor-owned)",
    """# LockScene composes the optional secure frozen desktop underneath the\n# configured translucent background, then applies one final blur before UI.\nrequire_text \"$PREVIEW\" 'required property string wallpaperFit' 'scene has no wallpaper-fit input'\nrequire_text \"$PREVIEW\" 'required property real wallpaperFocalX' 'scene has no focal-x input'\nrequire_text \"$PREVIEW\" 'required property real wallpaperFocalY' 'scene has no focal-y input'\nrequire_text \"$PREVIEW\" 'required property string overlayMode' 'scene has no overlay-mode input'\nrequire_text \"$PREVIEW\" 'required property real overlayStrength' 'scene has no overlay-strength input'\nrequire_text \"$PREVIEW\" 'required property real wallpaperBlur' 'scene has no blur input for shared editor/runtime state'\nrequire_text \"$PREVIEW\" 'required property string blurStyle' 'scene has no blur-style input'\nrequire_text \"$PREVIEW\" 'property Item desktopBackingSource: null' 'scene has no optional frozen desktop composition input'\nrequire_text \"$PREVIEW\" 'function wallpaperGeometry()' 'scene has no cover/contain focal geometry helper'\nrequire_text \"$PREVIEW\" 'root.wallpaperFit === \"contain\"' 'scene does not distinguish contain from cover'\nrequire_text \"$PREVIEW\" 'id: backgroundCompositionContent' 'scene has no final background composition item'\nrequire_text \"$PREVIEW\" 'id: desktopBackingTexture' 'scene cannot include the secure frozen desktop in final composition'\nrequire_text \"$PREVIEW\" 'sourceItem: root.desktopBackingSource' 'scene desktop texture does not consume the secure frozen backing'\nrequire_text \"$PREVIEW\" 'id: backgroundLayer' 'configured background layer is missing'\nrequire_text \"$PREVIEW\" 'layer.enabled: root.wallpaperBlur > 0' 'final composition smooth blur layer is not enabled'\nrequire_text \"$PREVIEW\" 'layer.effect: MultiEffect' 'final composition smooth blur has no MultiEffect'\nrequire_text \"$PREVIEW\" 'root.blurStyle === \"smooth\"' 'final composition smooth blur is not style-gated'\nrequire_text \"$PREVIEW\" 'id: backgroundCompositionPixelatedBlur' 'final composition pixelated blur path is missing'\nrequire_text \"$PREVIEW\" 'sourceItem: backgroundCompositionContent' 'pixelated blur does not source final composition'\nforbid_text \"$PREVIEW\" 'id: wallpaperPixelatedBlur' 'wallpaper is still pixelated independently of final composition'\nrequire_text \"$PREVIEW\" 'id: backgroundOverlay' 'scene has no readability overlay'\nrequire_text \"$PREVIEW\" 'root.overlayMode === \"light\" ? \"#ffffff\" : \"#000000\"' 'overlay cannot switch dark/light'\nrequire_text \"$PREVIEW\" 'Math.max(0, Math.min(100, root.overlayStrength)) / 100' 'overlay strength is not bounded'\nrequire_text \"$PREVIEW\" 'opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100' 'scene background opacity is not bounded'\n\n# LockSurface remains the opaque capture/fallback and transition owner, but no\n# longer attempts to blur that capture independently from the translucent layer.\nrequire_text \"$SURFACE\" 'color: \"#000000\"' 'secure surface does not fail closed to opaque black'\nrequire_text \"$SURFACE\" 'id: desktopBacking' 'secure surface has no frozen desktop backing'\nrequire_text \"$SURFACE\" 'id: desktopCapture' 'secure surface has no per-output frozen desktop image'\nrequire_text \"$SURFACE\" 'desktopBackingSource: desktopBacking' 'secure scene does not receive frozen desktop composition input'\nforbid_text \"$SURFACE\" 'id: desktopCapturePixelatedBlur' 'surface still pixelates desktop independently of final composition'\nforbid_text \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'surface still smooth-blurs desktop independently of final composition'\n\n""",
)

regex_once(
    BLUR_TEST,
    r"# Secure runtime renders one captured desktop source:.*?\n(?=# Iris Reveal must have a live texture-provider mask)",
    """# Secure runtime passes the frozen desktop into the same final composition as\n# the configured background. Smooth/Pixelated consume that final composition.\nrequire_text \"$LOCK_SHELL\" 'property string lockBlurStyle: \"smooth\"' 'secure shell has no blur-style state'\nrequire_text \"$LOCK_SHELL\" 'readonly property string blurStyle:' 'secure shell does not normalize blur style'\nrequire_text \"$LOCK_SHELL\" 'blurStyle: root.blurStyle' 'secure surface does not receive blur style'\nrequire_text \"$SURFACE\" 'required property string blurStyle' 'secure surface has no blur-style input'\nrequire_text \"$SURFACE\" 'desktopBackingSource: desktopBacking' 'secure frozen desktop is not passed into final composition'\nforbid_text \"$SURFACE\" 'id: desktopCapturePixelatedBlur' 'desktop still has an independent pixelated blur path'\nforbid_text \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'desktop still has an independent smooth blur path'\n\nrequire_text \"$PREVIEW\" 'required property string blurStyle' 'presentation scene has no blur-style input'\nrequire_text \"$PREVIEW\" 'property Item desktopBackingSource: null' 'presentation scene has no optional frozen desktop input'\nrequire_text \"$PREVIEW\" 'id: backgroundCompositionContent' 'presentation scene has no final background composition'\nrequire_text \"$PREVIEW\" 'sourceItem: root.desktopBackingSource' 'final composition cannot consume secure desktop backing'\nrequire_text \"$PREVIEW\" 'layer.enabled: root.wallpaperBlur > 0' 'final composition has no smooth-blur layer'\nrequire_text \"$PREVIEW\" 'layer.effect: MultiEffect' 'final composition has no MultiEffect smooth blur'\nrequire_text \"$PREVIEW\" 'id: backgroundCompositionPixelatedBlur' 'final composition has no pixelated blur path'\nrequire_text \"$PREVIEW\" 'sourceItem: backgroundCompositionContent' 'pixelated blur does not consume final composition'\nrequire_text \"$PREVIEW\" 'root.blurStyle === \"pixelated\"' 'final composition pixelated blur is not style-gated'\nforbid_text \"$PREVIEW\" 'id: wallpaperPixelatedBlur' 'wallpaper still has an independent pixelated blur path'\n\n""",
)

regex_once(
    THIRD_TEST,
    r"# Pass B: wallpaper and captured desktop each have real rendered composition\n.*?cmp -s \"\$SCENE\" \"\$PREVIEW_SCENE\" \\\n    \|\| fail 'secure/editor scene copies diverged'\n",
    """# Pass B: Blur owns the complete visible background composition. The frozen\n# desktop is copied into LockScene first, Background Opacity blends the configured\n# wallpaper/color above it, and only then Smooth/Pixelated is applied.\ncontains \"$SURFACE\" 'desktopBackingSource: desktopBacking' \\\n    'secure frozen desktop is not passed into the final background composition'\nrejects \"$SURFACE\" 'id: desktopCapturePixelatedBlur' \\\n    'desktop still has an independent pixelated blur path'\nrejects \"$SURFACE\" 'layer.enabled: root.transitionComplete' \\\n    'desktop still has an independent smooth blur path'\ncontains \"$SCENE\" 'property Item desktopBackingSource: null' \\\n    'scene has no optional frozen desktop composition input'\ncontains \"$SCENE\" 'id: backgroundCompositionContent' \\\n    'scene has no final background composition item'\ncontains \"$SCENE\" 'sourceItem: root.desktopBackingSource' \\\n    'final composition does not consume frozen desktop backing'\ncontains \"$SCENE\" 'opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100' \\\n    'configured background opacity is not inside final composition'\ncontains \"$SCENE\" 'layer.enabled: root.wallpaperBlur > 0' \\\n    'final composition has no smooth blur gate'\ncontains \"$SCENE\" 'layer.effect: MultiEffect' \\\n    'final composition has no smooth MultiEffect path'\ncontains \"$SCENE\" 'id: backgroundCompositionPixelatedBlur' \\\n    'final composition has no pixelated blur path'\ncontains \"$SCENE\" 'sourceItem: backgroundCompositionContent' \\\n    'pixelated blur does not consume final composition'\nrejects \"$SCENE\" 'id: wallpaperPixelatedBlur' \\\n    'wallpaper still has an independent pixelated blur path'\ncmp -s \"$SCENE\" \"$PREVIEW_SCENE\" \\\n    || fail 'secure/editor scene copies diverged'\n""",
)

replace_once(
    ACCEPTANCE_TEST,
    """has \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'secure frozen desktop has no direct smooth-blur layer gate'\nhas \"$SURFACE\" 'layer.effect: MultiEffect' 'smooth blur is not applied directly to the secure frozen desktop'\nlacks \"$SURFACE\" 'id: desktopCaptureTexture' 'secure frozen desktop still has a competing texture-provider copy'\nhas \"$SURFACE\" 'id: desktopCapturePixelatedBlur' 'pixelated blur is not applied to the secure frozen desktop backing'\nhas \"$SURFACE\" 'root.blurStyle === \"pixelated\"' 'secure pixelated blur is not style-gated'\n""",
    """has \"$SURFACE\" 'desktopBackingSource: desktopBacking' 'secure frozen desktop is not fed into final background composition'\nlacks \"$SURFACE\" 'id: desktopCapturePixelatedBlur' 'secure frozen desktop still has an independent pixelated blur path'\nlacks \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'secure frozen desktop still has an independent smooth blur path'\nhas \"$SCENE\" 'id: backgroundCompositionContent' 'complete visible background has no shared composition item'\nhas \"$SCENE\" 'sourceItem: root.desktopBackingSource' 'shared composition does not consume frozen desktop backing'\nhas \"$SCENE\" 'layer.effect: MultiEffect' 'smooth blur is not applied to the complete visible background'\nhas \"$SCENE\" 'id: backgroundCompositionPixelatedBlur' 'pixelated blur is not applied to the complete visible background'\nhas \"$SCENE\" 'sourceItem: backgroundCompositionContent' 'pixelated blur does not consume complete visible background'\n""",
)

# Managed updater history is append-only: retain every old stock hash and append
# new hashes for the managed files changed by this patch.
history_lines = HISTORY.read_text().splitlines()
for source, installed in [
    (SURFACE, ".config/quickshell/awtarchy-lock/LockSurface.qml"),
    (SCENES[0], ".config/quickshell/awtarchy-lock/LockScene.qml"),
    (SCENES[1], ".config/quickshell/awtarchy/LockPreviewScene.qml"),
]:
    digest = sha256(source.read_bytes()).hexdigest()
    entry = f"{digest}\t{installed}"
    if entry not in history_lines:
        history_lines.append(entry)
HISTORY.write_text("\n".join(history_lines) + "\n")
