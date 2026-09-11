#!/usr/bin/env python3
from pathlib import Path
import re

path = Path('.github/scripts/apply-lockscreen-expansion-pass1.py')
text = path.read_text(encoding='utf-8')
pattern = re.compile(
    r"replace_once\(PICKER, '''.*?'''\, '''.*?'''\)\n\n"
    r"# ---------------------------------------------------------------------------\n"
    r"# Secure shell/surface: logo physics rate replaces logo audio deformation\.\n"
    r"# ---------------------------------------------------------------------------",
    re.S,
)
replacement = r'''replace_once(PICKER, '''set +e
"$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e \\
    "$awtwall_path" --select-only --type images --resume --select-result "$RESULT_FILE"
terminal_rc=$?
set -e''', '''set +e
terminal_name="$(basename -- "$TERMINAL_CMD")"
if [[ "$terminal_name" == "alacritty" ]]; then
    "$TERMINAL_CMD" --option window.startup_mode=Fullscreen \\
        --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
    terminal_rc=$?
else
    "$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
    terminal_rc=$?
fi
set -e''')

# ---------------------------------------------------------------------------
# Secure shell/surface: logo physics rate replaces logo audio deformation.
# ---------------------------------------------------------------------------'''
next_text, count = pattern.subn(lambda _match: replacement, text, count=1)
if count != 1:
    raise SystemExit(f'expected one picker patch section in Pass 1 patcher, found {count}')
path.write_text(next_text, encoding='utf-8')
print('normalized Pass 1 picker patch block')
