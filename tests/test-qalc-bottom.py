#!/usr/bin/env python3
"""Validate Qalc's bottom input, upward history, and nonblocking live preview."""

import importlib.util
import os
from pathlib import Path
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / "config/hypr/scripts/qalc-bottom.py"
LAUNCHER = ROOT / "config/hypr/scripts/qalc-terminal.sh"
spec = importlib.util.spec_from_file_location("awtarchy_qalc_bottom", FRONTEND)
assert spec and spec.loader
calc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calc)

# Retained frontend is no longer selected; Foot scrollback belongs to native Qalc.
assert "qalc-bottom.py" not in LAUNCHER.read_text()
assert calc.qalc_command("-4 + 5")[-2:] == ["--", "-4 + 5"]
assert not calc.is_calculable("10+")
assert calc.is_calculable("-4+5")
assert calc.result_text("\n 20 \n") == "20"
assert calc.history_rows([("10+10", "20"), ("6+7", "13")], 3) == [
    ("> 6+7", False), ("  = 13", True), ("", False)
]


class FakeScreen:
    def __init__(self):
        self.lines = []
        self.cursor = None

    def erase(self):
        self.lines.clear()

    def getmaxyx(self):
        return 26, 40

    def addnstr(self, y, x, text, count, attr=0):
        self.lines.append((y, x, text[:count]))

    def hline(self, *args):
        pass

    def move(self, y, x):
        self.cursor = (y, x)

    def refresh(self):
        pass


calc.curses.has_colors = lambda: False
calc.curses.ACS_HLINE = ord("-")
screen = FakeScreen()
calc.draw(screen, "2+7", 3, [("10+10", "20"), ("6+7", "13")], "9")
assert (1, 2, "Qalc") in screen.lines
assert (24, 2, ">") in screen.lines
assert (24, 4, "2+7") in screen.lines
assert (22, 2, "= 9") in screen.lines
assert next(y for y, x, text in screen.lines if text == "> 6+7") < 22
assert next(y for y, x, text in screen.lines if text == "  = 13") < 22
assert screen.cursor == (24, 7)

# When history fills the window, no text may touch the heading/divider.
# Only whole expression/result groups remain visible, newest nearest input.
full_history = [(f"{i}+{i}", str(i * 2)) for i in range(40)]
calc.draw(screen, "", 0, full_history, "")
assert (1, 2, "Qalc") in screen.lines
shown = [(y, text) for y, x, text in screen.lines
         if text.startswith("> ") or text.startswith("  = ")]
assert shown
assert all(4 <= y <= 20 for y, text in shown), shown
assert [text for y, text in shown if text.startswith("> ")] == [
    f"> {i}+{i}" for i in range(35, 40)
]
assert [text for y, text in shown if text.startswith("  = ")] == [
    f"  = {i * 2}" for i in range(35, 40)
]

# A short terminal must also keep completed calculations below the header.
screen.getmaxyx = lambda: (12, 40)
calc.draw(screen, "", 0, full_history, "")
short_rows = [(y, text) for y, x, text in screen.lines
              if text.startswith("> ") or text.startswith("  = ")]
assert short_rows == [(4, "> 39+39"), (5, "  = 78")], short_rows

with tempfile.TemporaryDirectory(prefix="awtarchy-qalc-bottom-") as temp:
    fake = Path(temp) / "qalc"
    fake.write_text(
        '#!/bin/sh\n'
        'case "$*" in\n'
        '  *10+10*) echo 20 ;;\n'
        '  *6+7*) echo 13 ;;\n'
        '  *) echo unsupported ;;\n'
        'esac\n',
        encoding="utf-8",
    )
    fake.chmod(0o755)
    original_path = os.environ.get("PATH", "")
    os.environ["PATH"] = f"{temp}:{original_path}"
    try:
        assert calc.evaluate("10+10") == "20"
        live = calc.LivePreview()
        live.set_expression("10+10")
        limit = time.monotonic() + 2
        while not live.result and time.monotonic() < limit:
            live.tick()
            time.sleep(0.02)
        assert live.result == "20", live.result
        assert live.commit("10+10") == "20"
        assert live.expr == ""
        live.set_expression("6+7")
        limit = time.monotonic() + 2
        while not live.result and time.monotonic() < limit:
            live.tick()
            time.sleep(0.02)
        assert live.result == "13", live.result
        live.stop()
    finally:
        os.environ["PATH"] = original_path

print("PASS: Qalc bottom input, reverse-positioned history and live preview")
