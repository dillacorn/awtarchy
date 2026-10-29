#!/usr/bin/env python3
"""Bottom-input Awtarchy calculator using Qalc as the calculation engine."""

from __future__ import annotations

import curses
import subprocess
import sys
import time
from collections import OrderedDict

PREVIEW_DELAY = 0.12
QALC_TIMEOUT = 3.0
MAX_INPUT = 500
MAX_HISTORY = 100


def is_calculable(expression: str) -> bool:
    text = expression.strip()
    return bool(text) and text[-1] not in "+-*/^(=," and not text.startswith(("/", "#"))


def result_text(output: str) -> str:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return " | ".join(lines[:3])[:600]


def qalc_command(expression: str) -> list[str]:
    # -- prevents negative expressions being interpreted as CLI options.
    return ["qalc", "--terse", "--time", "1500", "--", expression]


def evaluate(expression: str) -> str:
    if not is_calculable(expression):
        return ""
    try:
        result = subprocess.run(
            qalc_command(expression), capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=QALC_TIMEOUT,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "Calculation unavailable"
    if result.returncode != 0:
        return result_text(result.stderr) or "Invalid expression"
    return result_text(result.stdout)


class LivePreview:
    """One bounded asynchronous Qalc process, cancelled on every input change."""

    def __init__(self) -> None:
        self.expr = ""
        self.changed = time.monotonic()
        self.process: subprocess.Popen[str] | None = None
        self.running_expr = ""
        self.launched = 0.0
        self.cache: OrderedDict[str, str] = OrderedDict()
        self.result = ""

    def stop(self) -> None:
        proc = self.process
        self.process = None
        self.running_expr = ""
        if proc is not None:
            if proc.poll() is None:
                proc.kill()
            try:
                proc.communicate(timeout=0.2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    def set_expression(self, expression: str) -> None:
        if expression == self.expr:
            return
        self.stop()
        self.expr = expression
        self.result = self.cache.get(expression, "")
        self.changed = time.monotonic()

    def tick(self) -> None:
        now = time.monotonic()
        if self.process is not None:
            if self.process.poll() is not None:
                proc = self.process
                expr = self.running_expr
                stdout, stderr = proc.communicate()
                value = result_text(stdout) if proc.returncode == 0 else (
                    result_text(stderr) or "Invalid expression")
                self.process = None
                self.running_expr = ""
                self._remember(expr, value)
                if self.expr == expr:
                    self.result = value
            elif now - self.launched > QALC_TIMEOUT:
                self.stop()
                self.result = "Calculation timed out"
            return
        if (self.result or not is_calculable(self.expr)
                or now - self.changed < PREVIEW_DELAY):
            return
        try:
            self.process = subprocess.Popen(
                qalc_command(self.expr), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, encoding="utf-8",
                errors="replace",
            )
            self.running_expr = self.expr
            self.launched = now
        except OSError:
            self.result = "Qalc executable not found"

    def _remember(self, expr: str, value: str) -> None:
        if not value:
            return
        self.cache[expr] = value
        self.cache.move_to_end(expr)
        if len(self.cache) > 128:
            self.cache.popitem(last=False)

    def commit(self, expression: str) -> str:
        if expression == self.expr and self.result:
            result = self.result
        else:
            self.stop()
            result = self.cache.get(expression, "") or evaluate(expression)
        self._remember(expression, result)
        self.set_expression("")
        return result


def history_rows(history: list[tuple[str, str]], height: int) -> list[tuple[str, bool]]:
    """Keep the newest complete expression/result groups; never split one."""
    visible = history[-(height // 3):] if height >= 3 else []
    rows: list[tuple[str, bool]] = []
    for expr, result in visible:
        rows.extend((("> " + expr, False), ("  = " + result, True), ("", False)))
    return rows


def add_line(stdscr: curses.window, row: int, column: int, text: str,
             width: int, attr: int = 0) -> None:
    if width <= 0 or not text:
        return
    try:
        stdscr.addnstr(row, column, text, width, attr)
    except curses.error:
        pass


def draw(stdscr: curses.window, expression: str, cursor: int,
         history: list[tuple[str, str]], preview: str) -> None:
    stdscr.erase()
    height, width = stdscr.getmaxyx()
    if height < 7 or width < 18:
        add_line(stdscr, 0, 0, "Resize Qalc window", width)
        stdscr.refresh()
        return

    margin = 2 if width > 22 else 1
    content_width = max(1, width - margin * 2)
    bold = curses.A_BOLD
    cyan = curses.color_pair(1) if curses.has_colors() else bold
    muted = curses.A_DIM

    add_line(stdscr, 1, margin, "Qalc", content_width, bold)
    try:
        stdscr.hline(2, margin, curses.ACS_HLINE, content_width)
    except curses.error:
        pass

    input_y = height - 2
    preview_y = height - 4
    history_top = 4  # Keep a blank row below the header divider (row 2).
    history_bottom = preview_y - 2
    available_history = max(0, history_bottom - history_top + 1)
    rows = history_rows(history, available_history)
    first_row = history_bottom - len(rows) + 1
    for i, (text, is_result) in enumerate(rows):
        row = first_row + i
        if history_top <= row <= history_bottom:
            add_line(stdscr, row, margin, text, content_width,
                     cyan if is_result else muted)

    if preview:
        add_line(stdscr, preview_y, margin, "= " + preview,
                 content_width, cyan)
    add_line(stdscr, input_y, margin, ">", 1, bold)
    input_width = max(1, content_width - 2)
    offset = max(0, cursor - input_width + 1)
    add_line(stdscr, input_y, margin + 2,
             expression[offset:offset + input_width], input_width)
    x = min(width - 1, margin + 2 + cursor - offset)
    try:
        stdscr.move(input_y, x)
    except curses.error:
        pass
    stdscr.refresh()


def main(stdscr: curses.window) -> None:
    stdscr.keypad(True)
    stdscr.timeout(40)
    curses.noecho()
    try:
        curses.curs_set(1)
    except curses.error:
        pass
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_CYAN, -1)

    current = ""
    position = 0
    history: list[tuple[str, str]] = []
    hist_cursor = 0
    scratch = ""
    live = LivePreview()
    try:
        while True:
            live.tick()
            draw(stdscr, current, position, history, live.result)
            try:
                key = stdscr.get_wch()
            except curses.error:
                continue
            if isinstance(key, int):
                if key == curses.KEY_RESIZE:
                    continue
                if key == curses.KEY_LEFT:
                    position = max(0, position - 1)
                    continue
                if key == curses.KEY_RIGHT:
                    position = min(len(current), position + 1)
                    continue
                if key == curses.KEY_HOME:
                    position = 0
                    continue
                if key == curses.KEY_END:
                    position = len(current)
                    continue
                if key == curses.KEY_DC:
                    current = current[:position] + current[position + 1:]
                elif key == curses.KEY_BACKSPACE:
                    if position:
                        current = current[:position - 1] + current[position:]
                        position -= 1
                elif key == curses.KEY_UP and history:
                    if hist_cursor == len(history):
                        scratch = current
                    hist_cursor = max(0, hist_cursor - 1)
                    current = history[hist_cursor][0]
                    position = len(current)
                elif key == curses.KEY_DOWN and history:
                    hist_cursor = min(len(history), hist_cursor + 1)
                    current = (history[hist_cursor][0] if hist_cursor < len(history)
                               else scratch)
                    position = len(current)
                else:
                    continue
            elif key in ("\x03", "\x04", "\x1b"):
                return
            elif key in ("\n", "\r"):
                if current.strip():
                    result = live.commit(current.strip())
                    history.append((current.strip(), result or "(no result)"))
                    del history[:-MAX_HISTORY]
                current = ""
                position = 0
                scratch = ""
                hist_cursor = len(history)
            elif key in ("\b", "\x7f"):
                if position:
                    current = current[:position - 1] + current[position:]
                    position -= 1
            elif key == "\x01":
                position = 0
                continue
            elif key == "\x05":
                position = len(current)
                continue
            elif key == "\x15":
                current = ""
                position = 0
            elif key == "\x0c":
                history.clear()
                hist_cursor = 0
                continue
            elif key.isprintable() and len(current) < MAX_INPUT:
                current = current[:position] + key + current[position:]
                position += len(key)
            else:
                continue
            live.set_expression(current)
    finally:
        live.stop()


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        sys.exit(0)
