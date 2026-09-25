#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="${ROOT}/config/hypr/hyprland.lua"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -Fq '    binds = {' "$HYPR" \
  || fail 'Hyprland config has no binds option section'
grep -Fq '        hide_special_on_workspace_change = true' "$HYPR" \
  || fail 'normal workspace changes do not hide the visible special workspace'
if grep -A10 -F '    general = {' "$HYPR" | grep -Fq 'hide_special_on_workspace_change'; then
  fail 'hide_special_on_workspace_change is incorrectly placed under general'
fi

grep -Fq 'local scratchpad_origins = {}' "$HYPR" \
  || fail 'scratchpad origin state is not kept in Hyprland Lua'
grep -Fq 'local function scratchpad_toggle_active_window()' "$HYPR" \
  || fail 'native scratchpad toggle function is missing'
grep -Fq 'local function scratchpad_move_active_to_workspace(workspace)' "$HYPR" \
  || fail 'scratchpad-aware native numbered move function is missing'
grep -Fq 'hl.get_active_window()' "$HYPR" \
  || fail 'scratchpad handling does not use the native active-window API'
grep -Fq 'workspace = "special:magic"' "$HYPR" \
  || fail 'native scratchpad toggle does not target special:magic'
grep -Fq 'follow = true' "$HYPR" \
  || fail 'scratchpad restore/send does not follow the active app when appropriate'
grep -Fq 'window.workspace.id' "$HYPR" \
  || fail 'scratchpad send does not record the prior workspace'
grep -Fq 'x = window.at.x' "$HYPR" \
  || fail 'scratchpad send does not record the prior floating position'
grep -Fq 'width = window.size.x' "$HYPR" \
  || fail 'scratchpad send does not record the prior floating size'
grep -Fq 'scratchpad_restore_geometry(window, origin)' "$HYPR" \
  || fail 'scratchpad restore does not attempt to restore saved geometry'
grep -Fq 'scratchpad_hide_if_empty()' "$HYPR" \
  || fail 'numbered moves do not close an empty visible scratchpad'
grep -Fq 'hl.bind("SUPER + CTRL + X", scratchpad_toggle_active_window, {})' "$HYPR" \
  || fail 'SUPER+CTRL+X is not bound directly to native scratchpad Lua'

if grep -Fq 'hl.dsp.exec_cmd(scratchpad_toggle_window' "$HYPR"; then
  fail 'scratchpad/window-number binds still depend on the external helper process'
fi

python3 - "$HYPR" <<'PY' || fail 'workspace-number scratchpad bindings are incomplete'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

required = [
    'hl.bind("ALT + SHIFT + " .. key, function()',
    'hl.bind("SUPER + SHIFT + " .. key, function()',
    'hl.bind("SUPER + SHIFT + " .. bind[1], function()',
    'hl.bind("SUPER + ALT + SHIFT + " .. bind[1], function()',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"missing native numbered move binding: {needle}")

if text.count("scratchpad_move_active_to_workspace(workspace)") < 4:
    raise SystemExit("not all numbered move families dispatch through native scratchpad handling")
PY

printf '%s\n' 'PASS: scratchpad and numbered workspace moves use native Hyprland Lua, remember origin geometry, and hide an empty scratchpad.'
