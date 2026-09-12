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
WORKFLOW = ROOT / ".github/workflows/validate-quickshell-lockscreen-interactive-effects.yml"
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


# Secure captured desktop: one source owns smooth rendering; the pixelated
# provider hides that source only while pixelated mode is actually active.
replace_once(
    SURFACE,
    """                fillMode: Image.Stretch\n                visible: status === Image.Ready\n            }\n""",
    """                fillMode: Image.Stretch\n                visible: status === Image.Ready\n\n                layer.enabled: root.transitionComplete\n                    && root.wallpaperBlur > 0\n                    && root.blurStyle === \"smooth\"\n                layer.effect: MultiEffect {\n                    autoPaddingEnabled: false\n                    blurEnabled: true\n                    blurMax: 32\n                    blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))\n                }\n            }\n""",
)
regex_once(
    SURFACE,
    r"\n            ShaderEffectSource \{\n                id: desktopCaptureTexture\n.*?\n            \}\n\n            MultiEffect \{\n                id: desktopCaptureSmoothBlur\n.*?\n            \}\n",
    "\n",
)
replace_once(
    SURFACE,
    """                sourceItem: desktopCapture\n                live: true\n""",
    """                sourceItem: desktopCapture\n                hideSource: root.transitionComplete\n                    && root.wallpaperBlur > 0\n                    && root.blurStyle === \"pixelated\"\n                    && desktopCapture.status === Image.Ready\n                live: true\n""",
)

# Wallpaper follows the same single-visible-source model in both secure and
# preview scenes. Apply identical edits and then assert byte-for-byte parity.
for scene in SCENES:
    replace_once(
        scene,
        """            asynchronous: true\n            cache: true\n        }\n""",
        """            asynchronous: true\n            cache: true\n\n            layer.enabled: root.wallpaperBlur > 0\n                && root.blurStyle === \"smooth\"\n            layer.effect: MultiEffect {\n                autoPaddingEnabled: false\n                blurEnabled: true\n                blurMax: 32\n                blur: Math.max(0, Math.min(1, root.wallpaperBlur / 100))\n            }\n        }\n""",
    )
    regex_once(
        scene,
        r"\n        ShaderEffectSource \{\n            id: wallpaperTexture\n.*?\n        \}\n\n        MultiEffect \{\n            id: wallpaperSmoothBlur\n.*?\n        \}\n",
        "\n",
    )
    replace_once(
        scene,
        """            sourceItem: wallpaperImage\n            live: true\n""",
        """            sourceItem: wallpaperImage\n            hideSource: root.wallpaperBlur > 0\n                && root.blurStyle === \"pixelated\"\n                && wallpaperImage.status === Image.Ready\n            live: true\n""",
    )

if SCENES[0].read_bytes() != SCENES[1].read_bytes():
    raise SystemExit("secure/editor LockScene parity diverged after blur patch")

# Migrate permanent contracts away from the broken shared texture-provider
# architecture to the direct layer + conditional pixelated-source architecture.
replace_once(
    BACKGROUND_TEST,
    """# LockScene independently blurs the wallpaper through a texture provider so\n# smooth and pixelated effects can coexist without exposing a sharp source.\n""",
    """# LockScene renders exactly one wallpaper source: smooth blur is an Image\n# layer effect, while pixelated mode conditionally hides the sharp image.\n""",
)
for old, new in [
    ("require_text \"$PREVIEW\" 'id: wallpaperTexture' 'wallpaper has no texture-provider path'\n", "require_text \"$PREVIEW\" 'layer.enabled: root.wallpaperBlur > 0' 'wallpaper smooth blur layer is not enabled'\n"),
    ("require_text \"$PREVIEW\" 'sourceItem: wallpaperImage' 'wallpaper texture does not source the wallpaper image'\n", "require_text \"$PREVIEW\" 'layer.effect: MultiEffect' 'wallpaper smooth blur has no direct layer effect'\n"),
    ("require_text \"$PREVIEW\" 'hideSource: true' 'wallpaper source is not hidden through its texture provider'\n", "require_text \"$PREVIEW\" 'root.blurStyle === \"smooth\"' 'wallpaper smooth blur is not style-gated'\n"),
    ("require_text \"$PREVIEW\" 'id: wallpaperSmoothBlur' 'wallpaper smooth blur has no rendered effect path'\n", "forbid_text \"$PREVIEW\" 'id: wallpaperTexture' 'wallpaper still has a competing texture-provider copy'\n"),
    ("require_text \"$PREVIEW\" 'source: wallpaperTexture' 'wallpaper smooth blur does not source the texture provider'\n", "require_text \"$PREVIEW\" 'hideSource: root.wallpaperBlur > 0' 'pixelated wallpaper does not hide the sharp source'\n"),
]:
    replace_once(BACKGROUND_TEST, old, new)
replace_once(
    BACKGROUND_TEST,
    """# Secure LockSurface owns the frozen-desktop blur. The capture is always fed\n# through a texture provider, then smooth or pixelated composition blur covers\n# it underneath every lockscreen background mode.\n""",
    """# Secure LockSurface owns the frozen-desktop blur. Smooth mode transforms\n# the capture directly; pixelated mode conditionally hides that same source.\n""",
)
for old, new in [
    ("require_text \"$SURFACE\" 'id: desktopCaptureTexture' 'secure surface has no desktop texture provider'\n", "require_text \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'secure capture has no direct smooth-blur layer gate'\n"),
    ("require_text \"$SURFACE\" 'sourceItem: desktopCapture' 'desktop texture does not source the frozen capture'\n", "require_text \"$SURFACE\" 'layer.effect: MultiEffect' 'secure capture has no direct smooth-blur effect'\n"),
    ("require_text \"$SURFACE\" 'hideSource: true' 'desktop source is not hidden through its texture provider'\n", "require_text \"$SURFACE\" 'root.blurStyle === \"smooth\"' 'smooth desktop blur is not style-gated'\n"),
    ("require_text \"$SURFACE\" 'id: desktopCaptureSmoothBlur' 'secure surface has no smooth desktop blur effect'\n", "forbid_text \"$SURFACE\" 'id: desktopCaptureTexture' 'secure surface still renders a competing desktop texture copy'\n"),
    ("require_text \"$SURFACE\" 'source: desktopCaptureTexture' 'smooth desktop blur does not source the texture provider'\n", "require_text \"$SURFACE\" 'hideSource: root.transitionComplete' 'pixelated desktop path does not hide the sharp source'\n"),
]:
    replace_once(BACKGROUND_TEST, old, new)

replace_once(
    BLUR_TEST,
    """# Secure runtime always renders the captured desktop through a texture source,\n# so blur still exists with black/color backgrounds and underneath wallpaper.\n""",
    """# Secure runtime renders one captured desktop source: direct smooth layer or\n# conditionally source-hiding pixelated provider under every background mode.\n""",
)
for old, new in [
    ("require_text \"$SURFACE\" 'id: desktopCaptureTexture' 'desktop capture has no texture-provider path'\n", "require_text \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'desktop capture has no direct smooth-blur layer'\n"),
    ("require_text \"$SURFACE\" 'sourceItem: desktopCapture' 'desktop texture does not source the captured Hyprland frame'\n", "require_text \"$SURFACE\" 'layer.effect: MultiEffect' 'desktop capture has no direct MultiEffect layer'\n"),
    ("require_text \"$SURFACE\" 'hideSource: true' 'captured desktop source is not hidden through the texture provider'\n", "require_text \"$SURFACE\" 'hideSource: root.transitionComplete' 'pixelated desktop path does not hide the sharp capture'\n"),
    ("require_text \"$SURFACE\" 'id: desktopCaptureSmoothBlur' 'smooth desktop blur path is missing'\n", "forbid_text \"$SURFACE\" 'id: desktopCaptureTexture' 'competing desktop texture-provider path remains'\n"),
    ("require_text \"$PREVIEW\" 'id: wallpaperTexture' 'wallpaper has no texture-provider path'\n", "require_text \"$PREVIEW\" 'layer.enabled: root.wallpaperBlur > 0' 'wallpaper has no direct smooth-blur layer'\n"),
    ("require_text \"$PREVIEW\" 'sourceItem: wallpaperImage' 'wallpaper texture does not source wallpaper image'\n", "require_text \"$PREVIEW\" 'layer.effect: MultiEffect' 'wallpaper has no direct MultiEffect layer'\n"),
    ("require_text \"$PREVIEW\" 'id: wallpaperSmoothBlur' 'smooth wallpaper blur path is missing'\n", "forbid_text \"$PREVIEW\" 'id: wallpaperTexture' 'competing wallpaper texture-provider path remains'\n"),
]:
    replace_once(BLUR_TEST, old, new)

for old, new in [
    ("contains \"$SCENE\" 'id: wallpaperTexture' \\\n    'wallpaper has no texture-provider render path'\n", "contains \"$SCENE\" 'layer.enabled: root.wallpaperBlur > 0' \\\n    'wallpaper has no direct smooth-blur layer gate'\n"),
    ("contains \"$SCENE\" 'sourceItem: wallpaperImage' \\\n    'wallpaper texture is not sourced from the wallpaper image'\n", "contains \"$SCENE\" 'layer.effect: MultiEffect' \\\n    'wallpaper has no direct MultiEffect smooth blur path'\n"),
    ("contains \"$SCENE\" 'id: wallpaperSmoothBlur' \\\n    'wallpaper has no actual MultiEffect smooth blur render path'\n", "rejects \"$SCENE\" 'id: wallpaperTexture' \\\n    'wallpaper still has a competing texture-provider copy'\n"),
    ("contains \"$SCENE\" 'source: wallpaperTexture' \\\n    'wallpaper smooth blur is not sourced from its texture provider'\n", "contains \"$SCENE\" 'hideSource: root.wallpaperBlur > 0' \\\n    'pixelated wallpaper path does not hide the sharp image'\n"),
    ("contains \"$SURFACE\" 'id: desktopCaptureTexture' \\\n    'captured desktop has no texture-provider render path'\n", "contains \"$SURFACE\" 'layer.enabled: root.transitionComplete' \\\n    'captured desktop has no direct smooth-blur layer gate'\n"),
    ("contains \"$SURFACE\" 'sourceItem: desktopCapture' \\\n    'captured desktop texture is not sourced from the secure capture image'\n", "contains \"$SURFACE\" 'layer.effect: MultiEffect' \\\n    'captured desktop has no direct MultiEffect smooth blur path'\n"),
    ("contains \"$SURFACE\" 'id: desktopCaptureSmoothBlur' \\\n    'captured desktop has no actual MultiEffect smooth blur render path'\n", "rejects \"$SURFACE\" 'id: desktopCaptureTexture' \\\n    'captured desktop still has a competing texture-provider copy'\n"),
    ("contains \"$SURFACE\" 'source: desktopCaptureTexture' \\\n    'captured desktop smooth blur is not sourced from its texture provider'\n", "contains \"$SURFACE\" 'hideSource: root.transitionComplete' \\\n    'pixelated desktop path does not hide the sharp capture'\n"),
]:
    replace_once(THIRD_TEST, old, new)

for old, new in [
    ("has \"$SURFACE\" 'id: desktopCaptureTexture' 'secure frozen desktop has no texture-provider blur backing'\n", "has \"$SURFACE\" 'layer.enabled: root.transitionComplete' 'secure frozen desktop has no direct smooth-blur layer gate'\n"),
    ("has \"$SURFACE\" 'id: desktopCaptureSmoothBlur' 'smooth blur is not applied to the secure frozen desktop backing'\n", "has \"$SURFACE\" 'layer.effect: MultiEffect' 'smooth blur is not applied directly to the secure frozen desktop'\n"),
    ("has \"$SURFACE\" 'source: desktopCaptureTexture' 'smooth secure blur does not consume the frozen desktop texture'\n", "lacks \"$SURFACE\" 'id: desktopCaptureTexture' 'secure frozen desktop still has a competing texture-provider copy'\n"),
]:
    replace_once(ACCEPTANCE_TEST, old, new)

# Make the RED regression a permanent read-only PR gate.
replace_once(
    WORKFLOW,
    "          bash -n tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n",
    "          bash -n tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n          bash -n tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
)
replace_once(
    WORKFLOW,
    "          shellcheck tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n",
    "          shellcheck tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n          shellcheck tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
)
replace_once(
    WORKFLOW,
    "          bash tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n",
    "          bash tests/test-quickshell-lockscreen-blur-iris-editor-controls.sh\n          bash tests/test-quickshell-lockscreen-composition-blur-rendering.sh\n",
)

# Preserve all historical managed hashes and append only the new production
# blobs produced by this patch.
history = HISTORY.read_text()
managed = [
    "config/quickshell/awtarchy-lock/LockSurface.qml",
    "config/quickshell/awtarchy-lock/LockScene.qml",
    "config/quickshell/awtarchy/LockPreviewScene.qml",
]
append = []
for rel in managed:
    digest = sha256((ROOT / rel).read_bytes()).hexdigest()
    line = f"{digest}  {rel}"
    if line not in history:
        append.append(line)
if append:
    if history and not history.endswith("\n"):
        history += "\n"
    HISTORY.write_text(history + "\n".join(append) + "\n")

print("Applied direct lockscreen composition blur rendering patch.")
