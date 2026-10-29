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

assert "qalc-bottom.py" in LAUNCHER.read_text()
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
