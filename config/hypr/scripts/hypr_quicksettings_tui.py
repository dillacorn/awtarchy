#!/usr/bin/env python3
import curses
import os
import subprocess
import time
from pathlib import Path

BRIGHTNESS_SCRIPT = os.environ.get(
    "HYPR_BRIGHTNESS_SCRIPT",
    os.path.expanduser("~/.config/hypr/scripts/hypr-ddc-brightness.sh"),
)
SUNSET_SCRIPT = os.environ.get(
    "HYPR_SUNSET_SCRIPT",
    os.path.expanduser("~/.config/hypr/scripts/hyprsunset_ctl.sh"),
)
VIBRANCE_SCRIPT = os.environ.get(
    "HYPR_VIBRANCE_SCRIPT",
    os.path.expanduser("~/.config/hypr/scripts/vibrance_shader.sh"),
)

HYPR_CONF = os.environ.get(
    "HYPRLAND_CONF",
    os.path.expanduser("~/.config/hypr/hyprland.conf"),
)
VIBRANCE_SHADER = os.environ.get(
    "VIBRANCE_SHADER_FILE",
    os.path.expanduser("~/.config/hypr/shaders/vibrance"),
)

BRIGHTNESS_STEP = int(os.environ.get("HYPR_BRIGHTNESS_STEP", "5"))
CMD_TIMEOUT = float(os.environ.get("HYPR_SETTINGS_TIMEOUT", "6"))

LR_REPEAT_GUARD_MS = int(os.environ.get("HYPR_TUI_LR_GUARD_MS", "320"))


def run(cmd: list[str], env: dict | None = None) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=CMD_TIMEOUT,
            check=False,
            env=env,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except FileNotFoundError:
        return 127, "", "not found"


def safe_call(cmd: list[str], env: dict | None = None) -> str | None:
    rc, _, err = run(cmd, env=env)
    if rc == 0:
        return None
    return err or f"exit {rc}"


def flush_input() -> None:
    try:
        curses.flushinp()
    except Exception:
        pass


def parse_kv(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def vibrance_value() -> str:
    try:
        p = Path(VIBRANCE_SHADER)
        if not p.is_file():
            return "N/A"
        for line in p.read_text(errors="ignore").splitlines():
            s = line.strip()
            if s.startswith("#define") and "VIBRANCE" in s:
                parts = s.split()
                if len(parts) >= 3 and parts[1] == "VIBRANCE":
                    try:
                        return f"{float(parts[2]):.2f}"
                    except ValueError:
                        return parts[2]
        return "0.00"
    except Exception:
        return "N/A"


def vibrance_enabled() -> bool | None:
    try:
        p = Path(HYPR_CONF)
        if not p.is_file():
            return None
        for raw in p.read_text(errors="ignore").splitlines():
            line = raw.rstrip("\r")
            t = line.lstrip()
            if t.startswith("#"):
                continue
            if not t.startswith("screen_shader"):
                continue
            if "=" not in t:
                continue
            rhs = t.split("=", 1)[1]
            rhs = rhs.split("#", 1)[0]
            rhs = "".join(rhs.split())
            if rhs.endswith("/shaders/vibrance"):
                return True
        return False
    except Exception:
        return None


def brightness_status() -> dict[str, str]:
    rc, out, _ = run([BRIGHTNESS_SCRIPT, "status"])
    if rc != 0 or not out:
        return {"conn": "N/A", "cur": "N/A", "max": "N/A"}
    return parse_kv(out)


def sunset_status() -> dict[str, str]:
    rc, out, _ = run([SUNSET_SCRIPT, "status"])
    if rc != 0 or not out:
        return {"temp": "N/A", "identity": "unknown", "enabled": "0"}
    return parse_kv(out)


def format_brightness(st: dict[str, str]) -> str:
    conn = st.get("conn", "N/A")
    cur = st.get("cur", "N/A")
    mx = st.get("max", "N/A")
    return f"{conn} {cur}/{mx}"


def format_sunset(st: dict[str, str]) -> str:
    temp = st.get("temp", "N/A")
    ident = st.get("identity", "unknown")
    enabled = st.get("enabled", "0")
    if ident == "true":
        onoff = "off"
    elif ident == "false":
        onoff = "on"
    else:
        onoff = "on" if enabled == "1" else "off"
    return f"{temp} ({onoff})"


def format_vibrance() -> str:
    val = vibrance_value()
    en = vibrance_enabled()
    if en is True:
        return f"{val} (on)"
    if en is False:
        return f"{val} (off)"
    return f"{val} (unknown)"


def prompt_number(stdscr, label: str, default: str = "") -> str | None:
    h, w = stdscr.getmaxyx()
    y = h - 1

    flush_input()
    curses.echo()
    curses.curs_set(1)

    stdscr.move(y, 0)
    stdscr.clrtoeol()
    prompt = f"{label} "
    stdscr.addstr(y, 0, prompt[: max(0, w - 1)])

    if default:
        try:
            stdscr.addstr(
                y,
                min(len(prompt), w - 1),
                default[: max(0, w - 1 - len(prompt))],
            )
            stdscr.move(y, min(len(prompt) + len(default), w - 1))
        except curses.error:
            pass

    stdscr.refresh()

    try:
        raw = stdscr.getstr(y, min(len(prompt), w - 1), 16)
        s = raw.decode(errors="ignore").strip()
    except Exception:
        s = ""

    curses.noecho()
    curses.curs_set(0)
    flush_input()

    if not s:
        return None
    return s


def brightness_set_abs(target: int) -> str | None:
    return safe_call([BRIGHTNESS_SCRIPT, "set", str(target)])


def brightness_adjust_inplace(bst: dict[str, str], delta: int) -> tuple[str | None, dict[str, str]]:
    try:
        cur = int(bst.get("cur", "0"))
        mx = int(bst.get("max", "0"))
        conn = bst.get("conn", "N/A")
        if mx <= 0 or conn == "N/A":
            raise ValueError
    except Exception:
        bst = brightness_status()
        try:
            cur = int(bst.get("cur", "0"))
            mx = int(bst.get("max", "0"))
        except Exception:
            return "bad brightness status", bst

    target = cur + delta
    if target < 0:
        target = 0
    if mx > 0 and target > mx:
        target = mx

    err = brightness_set_abs(target)

    bst = dict(bst)
    bst["cur"] = str(target)
    return err, bst


def ui(stdscr) -> None:
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.keypad(True)

    items = ["brightness", "sunset", "vibrance"]
    sel = 0
    msg = ""

    last_lr_ts = 0.0

    def refresh() -> dict:
        b = brightness_status()
        s = sunset_status()
        v = {"value": vibrance_value()}
        ve = vibrance_enabled()
        v["enabled"] = "1" if ve is True else ("0" if ve is False else "?")
        return {"brightness": b, "sunset": s, "vibrance": v}

    state = refresh()

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        title = "Hypr Quick Settings (TUI)"
        help1 = "Up/Down: select   Left/Right: adjust   Enter: toggle/edit   r: refresh   q: quit"

        stdscr.addstr(0, 0, title[: max(0, w - 1)])
        stdscr.addstr(1, 0, help1[: max(0, w - 1)])

        lines = [
            ("Brightness", format_brightness(state["brightness"])),
            ("Night Light", format_sunset(state["sunset"])),
            ("Vibrance", format_vibrance()),
        ]

        y0 = 3
        for i, (k, v) in enumerate(lines):
            prefix = "-> " if i == sel else "   "
            line = f"{prefix}{k:<11} {v}"
            if y0 + i < h - 2:
                if i == sel:
                    stdscr.addstr(y0 + i, 0, line[: max(0, w - 1)], curses.A_REVERSE)
                else:
                    stdscr.addstr(y0 + i, 0, line[: max(0, w - 1)])

        if msg and h >= 2:
            stdscr.addstr(h - 1, 0, msg[: max(0, w - 1)])

        stdscr.refresh()

        ch = stdscr.getch()
        msg = ""

        if ch in (ord("q"), 27):
            return
        if ch == curses.KEY_UP:
            sel = (sel - 1) % len(items)
            continue
        if ch == curses.KEY_DOWN:
            sel = (sel + 1) % len(items)
            continue
        if ch in (ord("r"), ord("R")):
            flush_input()
            state = refresh()
            continue

        current = items[sel]

        if ch in (curses.KEY_LEFT, curses.KEY_RIGHT):
            now = time.monotonic()
            if (now - last_lr_ts) * 1000.0 < LR_REPEAT_GUARD_MS:
                flush_input()
                continue
            last_lr_ts = now

            flush_input()

            if current == "brightness":
                delta = -BRIGHTNESS_STEP if ch == curses.KEY_LEFT else BRIGHTNESS_STEP
                err, new_b = brightness_adjust_inplace(state["brightness"], delta)
                if err:
                    msg = f"brightness: {err}"
                state["brightness"] = new_b
                flush_input()
                continue

            if current == "sunset":
                direction = "down" if ch == curses.KEY_LEFT else "up"
                err = safe_call([SUNSET_SCRIPT, direction])
                if err:
                    msg = f"night light: {err}"
                state = refresh()
                flush_input()
                continue

            if current == "vibrance":
                direction = "down" if ch == curses.KEY_LEFT else "up"
                err = safe_call([VIBRANCE_SCRIPT, direction])
                if err:
                    msg = f"vibrance: {err}"
                state = refresh()
                flush_input()
                continue

        if ch in (10, 13, curses.KEY_ENTER):
            if current == "brightness":
                b = state["brightness"]
                try:
                    cur = int(b.get("cur", "0"))
                    mx = int(b.get("max", "0"))
                    if mx <= 0:
                        raise ValueError
                except Exception:
                    b = brightness_status()
                    state["brightness"] = b
                    try:
                        cur = int(b.get("cur", "0"))
                        mx = int(b.get("max", "0"))
                    except Exception:
                        msg = "brightness: bad status"
                        continue

                s = prompt_number(stdscr, f"Set brightness (0-{mx})", default=str(cur))
                if s is None:
                    continue
                if not s.isdigit():
                    msg = "brightness: numbers only"
                    continue

                val = int(s)
                if val < 0:
                    val = 0
                if val > mx:
                    val = mx

                flush_input()
                err = brightness_set_abs(val)
                if err:
                    msg = f"brightness: {err}"
                state["brightness"] = dict(state["brightness"])
                state["brightness"]["cur"] = str(val)
                flush_input()
                continue

            if current == "sunset":
                flush_input()
                err = safe_call([SUNSET_SCRIPT, "toggle"])
                if err:
                    msg = f"night light: {err}"
                state = refresh()
                flush_input()
                continue

            if current == "vibrance":
                flush_input()
                err = safe_call([VIBRANCE_SCRIPT, "toggle"])
                if err:
                    msg = f"vibrance: {err}"
                state = refresh()
                flush_input()
                continue

            msg = "nothing to toggle/edit here"
            continue


def main() -> None:
    for p in (BRIGHTNESS_SCRIPT, SUNSET_SCRIPT, VIBRANCE_SCRIPT):
        if not Path(p).exists():
            print(f"missing: {p}")
            return
    curses.wrapper(ui)


if __name__ == "__main__":
    main()
