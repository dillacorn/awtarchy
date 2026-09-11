#!/usr/bin/env python3
from pathlib import Path

path = Path('.github/scripts/apply-lockscreen-expansion-pass1.py')
text = path.read_text(encoding='utf-8')
old = '''replace_once(PICKER, ''' + "'''" + '''"$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e "$awtwall_path" --select-only --type images --resume --select-result "$RESULT_FILE"

if [[ ! -s "$RESULT_FILE" ]]; then''' + "'''" + ''', ''' + "'''" + '''terminal_name="$(basename -- "$TERMINAL_CMD")"
if [[ "$terminal_name" == "alacritty" ]]; then
    "$TERMINAL_CMD" --option window.startup_mode=Fullscreen \\
        --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
else
    "$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e "$awtwall_path" \\
        --select-only --type images --resume --select-result "$RESULT_FILE"
fi

if [[ ! -s "$RESULT_FILE" ]]; then''' + "'''" + ''')'''
new = '''replace_once(PICKER, ''' + "'''" + '''set +e
"$TERMINAL_CMD" --class awtarchy-lock-wallpaper -e \\
    "$awtwall_path" --select-only --type images --resume --select-result "$RESULT_FILE"
terminal_rc=$?
set -e''' + "'''" + ''', ''' + "'''" + '''set +e
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
set -e''' + "'''" + ''')'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one picker patch block in Pass 1 patcher, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('normalized Pass 1 picker patch block')
