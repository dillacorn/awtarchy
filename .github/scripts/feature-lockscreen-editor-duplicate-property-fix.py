#!/usr/bin/env python3
from pathlib import Path

path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
text = path.read_text(encoding="utf-8")

properties = [
    "property var draftSharedProfile:",
    "property var draftMonitorOverrides:",
    "property string activeMonitorName:",
    "property bool profileLoadActive:",
    "property var profileUndoStacks:",
    "property var profileRedoStacks:",
]

for declaration in properties:
    count = text.count(declaration)
    if count != 2:
        raise SystemExit(
            f"expected exactly two pre-fix declarations for {declaration}, found {count}"
        )

anchor = """    property var draftSharedAutoAccents: defaultAutoAccents()\n    property var draftMonitorAutoAccents: ({})\n"""
duplicate = """    property var draftSharedProfile: ({})\n    property var draftMonitorOverrides: ({})\n    property string activeMonitorName: \"\"\n    property bool profileLoadActive: false\n    property var profileUndoStacks: ({})\n    property var profileRedoStacks: ({})\n"""
needle = anchor + duplicate

if text.count(needle) != 1:
    raise SystemExit("duplicate multi-monitor property block anchor not found exactly once")

text = text.replace(needle, anchor, 1)

for declaration in properties:
    count = text.count(declaration)
    if count != 1:
        raise SystemExit(
            f"post-fix declaration count wrong for {declaration}: found {count}"
        )

path.write_text(text, encoding="utf-8")
