#!/usr/bin/env python3
"""Exercise the launcher QML pointer-selection policy without a compositor."""
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
launcher = (root / "config/quickshell/awtarchy/Launcher.qml").read_text(encoding="utf-8")

assert "onTextChanged: root.resetSelection()" in launcher
assert "function resetSelection() {\n        resetPointerTracking();" in launcher
assert "onPositionChanged: mouse => root.selectOnPointerMotion(row, mouse)" in launcher
assert "root.pointerSelectionActive && hover.containsMouse" in launcher
assert "root.resetPointerTracking();\n                positionTimer.restart();" in launcher
assert "|| event.key === Qt.Key_Left || event.key === Qt.Key_Right)" in launcher
assert "root.resetPointerTracking();" in launcher
assert "const pos = row.mapToItem(launcherPanel, mouse.x, mouse.y);" in launcher
assert "appList.currentIndex = row.index;" in launcher

found = re.search(r"^    function selectOnPointerMotion\(row, mouse\) \{.*?^    \}",
                  launcher, flags=re.MULTILINE | re.DOTALL)
assert found, "Could not extract actual QML selection function"
assert shutil.which("node"), "Node.js required for a real JS policy regression"

scenario = r"""
let pointerSelectionActive = false;
let pointerSampleValid = false;
let lastPointerX = 0;
let lastPointerY = 0;
const appList = {currentIndex: 0};
const launcherPanel = {};
// Use the REAL function extracted from Launcher.qml.
""" + found.group(0) + r"""
const row = {
    index: 5, x: 100, y: 240,
    mapToItem(_panel, mx, my) { return { x: this.x + mx, y: this.y + my }; }
};
function insist(ok, description) { if (!ok) throw Error(description); }
// Pointer already over an item when the search field receives focus.
selectOnPointerMotion(row, {x: 15, y: 10});
insist(appList.currentIndex === 0 && !pointerSelectionActive, "initial hover stole selection");
// The results move beneath a physically stationary pointer; local mouse y
// changes, but coordinates relative to the launcher remain identical.
row.y = 190;
selectOnPointerMotion(row, {x: 15, y: 60});
insist(appList.currentIndex === 0 && !pointerSelectionActive, "stationary pointer stole selection");
// Subpixel jitter does not override keyboard selection.
selectOnPointerMotion(row, {x: 15.5, y: 60});
insist(appList.currentIndex === 0 && !pointerSelectionActive, "jitter stole selection");
// Real pointer movement transfers control to the hovered row.
selectOnPointerMotion(row, {x: 19, y: 60});
insist(appList.currentIndex === 5 && pointerSelectionActive, "real pointer motion ignored");
// Typing another query resets pointer ownership before results reorganize.
appList.currentIndex = 0;
pointerSampleValid = false;
pointerSelectionActive = false;
row.index = 3;
row.y = 145;
selectOnPointerMotion(row, {x: 19, y: 105});
insist(appList.currentIndex === 0 && !pointerSelectionActive, "typing did not retain result zero");
selectOnPointerMotion(row, {x: 30, y: 105});
insist(appList.currentIndex === 3 && pointerSelectionActive, "pointer motion did not restore hover control");
console.log("PASS: launcher ignores stationary cursor, tracks real motion, restores keyboard control");
"""
result = subprocess.run(["node", "-"], input=scenario, text=True,
                        capture_output=True, timeout=15)
assert result.returncode == 0, result.stdout + result.stderr
print(result.stdout.strip())
