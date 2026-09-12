#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

contains() {
    local file="$1" needle="$2" message="$3"
    grep -Fq -- "$needle" "$file" || fail "$message"
}

rejects() {
    local file="$1" needle="$2" message="$3"
    ! grep -Fq -- "$needle" "$file" || fail "$message"
}

# The secure frozen desktop must enter the same background composition as the
# configured lockscreen background before Blur is applied.  This is the key
# ordering invariant for Background Opacity < 100%: there must be no separate
# sharp desktop sibling left underneath a wallpaper/color-only blur effect.
contains "$SURFACE" 'desktopBackingSource: desktopBacking' \
    'secure scene does not receive the frozen desktop as a composition input'
rejects "$SURFACE" 'desktopCapture.layer.enabled' \
    'captured desktop is still blurred independently instead of in final composition'

contains "$SCENE" 'property Item desktopBackingSource: null' \
    'presentation scene has no optional secure desktop composition input'
contains "$SCENE" 'id: backgroundCompositionContent' \
    'presentation scene has no unified background composition item'
contains "$SCENE" 'id: desktopBackingTexture' \
    'unified composition does not render the secure frozen desktop input'
contains "$SCENE" 'sourceItem: root.desktopBackingSource' \
    'desktop composition texture does not source the secure frozen desktop'
contains "$SCENE" 'hideSource: root.desktopBackingSource !== null' \
    'secure frozen desktop source is not hidden after being copied into composition'
contains "$SCENE" 'id: backgroundLayer' \
    'configured wallpaper/color background layer is missing'
contains "$SCENE" 'opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100' \
    'configured background opacity is not applied inside final composition'
contains "$SCENE" 'layer.effect: MultiEffect' \
    'unified background composition has no smooth blur effect'
contains "$SCENE" 'id: backgroundCompositionPixelatedBlur' \
    'unified background composition has no pixelated blur output'
contains "$SCENE" 'sourceItem: backgroundCompositionContent' \
    'pixelated blur does not consume the complete background composition'
rejects "$SCENE" 'id: wallpaperPixelatedBlur' \
    'wallpaper is still pixelated independently of the visible desktop composition'

# Check nesting/order rather than only the presence of identifiers.  The frozen
# desktop copy and translucent configured background must both occur inside the
# item that owns the final blur, while foreground lockscreen UI stays outside.
python3 - "$SCENE" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
composition = text.index("id: backgroundCompositionContent")
desktop = text.index("id: desktopBackingTexture", composition)
background = text.index("id: backgroundLayer", desktop)
visual = text.index("id: visualLayer", background)
segment = text[composition:visual]

required = [
    "sourceItem: root.desktopBackingSource",
    "opacity: Math.max(0, Math.min(100, root.backgroundOpacity)) / 100",
    "layer.enabled: root.wallpaperBlur > 0",
    'root.blurStyle === "smooth"',
    "layer.effect: MultiEffect",
]
for needle in required:
    if needle not in segment:
        raise SystemExit(f"FAIL: final background composition segment lacks {needle!r}")

if not (composition < desktop < background < visual):
    raise SystemExit("FAIL: desktop/background/foreground composition order is wrong")
PY

# Numeric compositing oracle for the runtime failure.  Model obvious sharp
# desktop detail under a 40%-opaque background.  The required order is:
#     blur(alpha(background, desktop))
# not:
#     alpha(blur(background), sharp_desktop)
# The latter leaves the desktop's high-frequency detail visible and is exactly
# the failure observed on Hyprland.
python3 <<'PY'
def alpha_over(top, bottom, alpha):
    return [alpha * t + (1.0 - alpha) * b for t, b in zip(top, bottom)]


def box_blur(values, radius=2):
    out = []
    for i in range(len(values)):
        lo = max(0, i - radius)
        hi = min(len(values), i + radius + 1)
        out.append(sum(values[lo:hi]) / (hi - lo))
    return out


def adjacent_contrast(values):
    return sum(abs(values[i] - values[i - 1]) for i in range(1, len(values))) / (len(values) - 1)

# Alternating black/white pixels make any surviving sharp desktop unmistakable.
desktop = [float(i % 2) for i in range(64)]
alpha = 0.40

for label, configured_background in (
    ("no-wallpaper black background", [0.0] * len(desktop)),
    ("wallpaper background", [0.30 + 0.20 * (i / (len(desktop) - 1)) for i in range(len(desktop))]),
):
    composited = alpha_over(configured_background, desktop, alpha)
    expected = box_blur(composited)
    wrong = alpha_over(box_blur(configured_background), desktop, alpha)

    expected_contrast = adjacent_contrast(expected)
    wrong_contrast = adjacent_contrast(wrong)
    if expected_contrast >= wrong_contrast * 0.45:
        raise SystemExit(
            f"FAIL: {label}: final-composition blur did not sufficiently suppress desktop detail "
            f"(expected={expected_contrast:.4f}, wrong={wrong_contrast:.4f})"
        )
PY

# The unlocked editor captures each real output while its own windows are hidden.
# Primary and secondary previews feed those frozen frames into the same
# desktopBackingSource composition used by secure runtime, so Blur updates the
# complete preview composition live without recursively capturing the editor UI.
contains "$EDITOR" 'desktopBackingSource: editorTransitionStart' \
    'primary editor preview does not feed its synthetic desktop into live blur composition'
contains "$EDITOR" 'desktopBackingSource: secondaryTransitionStart' \
    'secondary editor preview does not feed its synthetic desktop into live blur composition'
contains "$EDITOR" 'wallpaperBlur: root.draftWallpaperBlur' \
    'editor preview blur strength is not bound to the live draft value'

cmp -s "$SCENE" "$PREVIEW" \
    || fail 'secure/editor presentation scenes diverged'

printf '%s\n' 'PASS: blur consumes the complete translucent runtime and editor-preview background composition'
