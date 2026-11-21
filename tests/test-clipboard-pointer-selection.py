#!/usr/bin/env python3
"""Exercise the real ClipboardMenu QML pointer-selection policy offline."""
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / "config/quickshell/awtarchy/ClipboardMenu.qml").read_text(encoding="utf-8")

assert "onPositionChanged: mouse => root.selectOnPointerMotion(row, mouse)" in source
assert "onEntered: clipboardList.currentIndex = row.index" not in source
assert "function resetPointerTracking()" in source
assert "resetPointerTracking();\n        FlyoutManager.claim(\"clipboard\", target.name);" in source
assert "root.resetPointerTracking();\n                Qt.callLater(() => {" in source
assert "root.resetPointerTracking();\n                                    clipboardList.currentIndex" in source
assert "root.resetPointerTracking();\n                                clipboardList.currentIndex = 0;" in source
assert "clipboardList.currentIndex = 0;\n            Qt.callLater(() => clipboardList.positionViewAtBeginning());" in source
assert "root.pointerSelectionActive\n                                && (rowMouse.containsMouse" in source
assert source.count("&& root.pointerSelectionActive") >= 2
assert "onClicked: root.choose(row.modelData)" in source
assert "if (event.key === Qt.Key_Down && clipboardList.count > 0)" in source
assert "Math.min(clipboardList.count - 1, clipboardList.currentIndex + 1)" in source

fn = re.search(r"^    function selectOnPointerMotion\(row, mouse\) \{.*?^    \}",
               source, re.MULTILINE | re.DOTALL)
reset = re.search(r"^    function resetPointerTracking\(\) \{.*?^    \}",
                  source, re.MULTILINE | re.DOTALL)
assert fn and reset, "Could not extract actual ClipboardMenu QML pointer functions"
assert shutil.which("node"), "Node.js is required for the QML selection regression"

js = r"""
let pointerSelectionActive = false;
let pointerSampleValid = false;
let lastPointerX = 0;
let lastPointerY = 0;
const clipboardList = { currentIndex: 0, count: 8 };
const panel = {};
""" + reset.group(0) + "\n" + fn.group(0) + r"""
function check(ok, description) { if (!ok) throw new Error(description); }
const row = {
    index: 6, x: 0, y: 280,
    mapToItem(_target, localX, localY) {
        return {x: this.x + localX, y: this.y + localY};
    }
};
// First hovered result after opening must not steal initial keyboard selection.
selectOnPointerMotion(row, {x: 8, y: 18});
check(clipboardList.currentIndex === 0 && !pointerSelectionActive,
      "initial clipboard hover stole first entry");
// A filtered or newly loaded list can change delegate-relative mouse coords.
row.y = 210;
selectOnPointerMotion(row, {x: 8, y: 88});
check(clipboardList.currentIndex === 0 && !pointerSelectionActive,
      "moving list under a stationary cursor stole selection");
// Down from first clipboard entry must navigate to the second, not past
// whatever row the pointer happens to occupy.
clipboardList.currentIndex = Math.min(clipboardList.count - 1,
                                      clipboardList.currentIndex + 1);
check(clipboardList.currentIndex === 1, "Down should select clipboard entry 2");
// Genuine mouse movement transfers selection to the hovered item.
selectOnPointerMotion(row, {x: 12, y: 88});
check(clipboardList.currentIndex === 6 && pointerSelectionActive,
      "actual pointer movement did not enable clipboard hover selection");
// Search typing resets mouse ownership; fresh filtered entry begins at index 0.
resetPointerTracking();
clipboardList.currentIndex = 0;
row.index = 4;
selectOnPointerMotion(row, {x: 12, y: 88});
check(clipboardList.currentIndex === 0 && !pointerSelectionActive,
      "new clipboard search was overridden by stationary cursor");
selectOnPointerMotion(row, {x: 22, y: 88});
check(clipboardList.currentIndex === 4 && pointerSelectionActive,
      "clipboard hover failed to recover after pointer movement");
console.log("PASS: clipboard initial selection, one-Down navigation, and motion-only hover");
"""
run = subprocess.run(["node", "-"], input=js, text=True, capture_output=True, timeout=15)
assert run.returncode == 0, run.stdout + run.stderr
print(run.stdout.strip())
