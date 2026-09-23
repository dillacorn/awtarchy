#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KEYMAP="$ROOT/config/yazi/keymap.toml"
PACKAGE="$ROOT/config/yazi/package.toml"
YAZI_CONFIG="$ROOT/config/yazi/yazi.toml"
YAZI_INIT="$ROOT/config/yazi/init.lua"
MIMEAPPS="$ROOT/config/mimeapps.list"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'wl-copy -t text/uri-list' "$KEYMAP" \
  || fail 'Yazi system clipboard copy is not using wl-copy text/uri-list'
grep -Fq 'for path in %s' "$KEYMAP" \
  || fail 'Yazi system clipboard copy does not preserve multi-file selection'
if grep -Fq 'plugin clipboard' "$KEYMAP"; then
  fail 'Yazi keymap still invokes the deprecated custom clipboard plugin name'
fi
python3 - "$KEYMAP" <<'PY_KEYMAP' || fail 'Yazi manager keybindings do not preserve native g/G behavior and wraparound movement'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

bindings = config.get("mgr", {}).get("prepend_keymap", [])
if not isinstance(bindings, list):
    raise SystemExit(1)

by_keys = {}
for binding in bindings:
    if not isinstance(binding, dict):
        continue
    keys = binding.get("on")
    if isinstance(keys, str):
        keys = [keys]
    if isinstance(keys, list):
        by_keys[tuple(keys)] = binding

for keys in [("g",), ("a",), ("/",), ("n",), ("N",)]:
    if keys in by_keys:
        raise SystemExit(1)

expected = {
    ("<Up>",): "arrow prev",
    ("<Down>",): "arrow next",
    ("k",): "arrow prev",
    ("j",): "arrow next",
    ("g", "g"): "arrow top",
    ("G",): "arrow bot",
    ("<Enter>",): 'lua "AwtarchyYaziSmartEnter()"',
    ("q",): 'lua "AwtarchyYaziConfirmQuit(false)"',
    ("Q",): 'lua "AwtarchyYaziConfirmQuit(true)"',
    ("<C-w>",): 'lua "AwtarchyYaziCloseTab()"',
    ("<Space>",): 'lua "AwtarchyYaziToggleOrCommitSelection()"',
    ("<C-Space>",): "toggle",
    ("<S-Up>",): ['lua "AwtarchyYaziEnsureRangeSelect()"', "arrow prev"],
    ("<S-Down>",): ['lua "AwtarchyYaziEnsureRangeSelect()"', "arrow next"],
    ("<C-x>",): "yank --cut",
    ("<C-v>",): "paste",
    ("c", "z"): 'lua "AwtarchyYaziCompressSelection()"',
    ("e", "h"): 'lua "AwtarchyYaziExtractZipHere()"',
    ("e", "f"): 'lua "AwtarchyYaziExtractZipFolder()"',
    ("t", "e"): 'shell --orphan -- "$HOME/.config/hypr/scripts/default_terminal.sh" -- bash',
    ("m", "t"): 'lua "AwtarchyYaziToggleTimeFormat()"',
    ("?",): "help",
}
for keys, run in expected.items():
    if by_keys.get(keys, {}).get("run") != run:
        raise SystemExit(1)

ctrl_copy = by_keys.get(("<C-c>",), {}).get("run")
if (
    not isinstance(ctrl_copy, list)
    or "yank" not in ctrl_copy
    or not any("wl-copy -t text/uri-list" in action for action in ctrl_copy if isinstance(action, str))
):
    raise SystemExit(1)

if by_keys.get(("m", "t"), {}).get("desc") != "Toggle modified time 24h/12h":
    raise SystemExit(1)

if by_keys.get(("t", "e"), {}).get("desc") != "Open terminal here":
    raise SystemExit(1)
PY_KEYMAP

if grep -Fq 'dragon-drop' "$KEYMAP"; then
  fail 'Yazi keymap still contains the retired DragonDrop workflow'
fi
grep -Fq 'desc = "Copy files + system clipboard"' "$KEYMAP" \
  || fail 'Yazi Ctrl+C system-clipboard copy binding is not documented'
grep -Fq 'on = ["<C-Space>"]' "$KEYMAP" \
  || fail 'Yazi Ctrl+Space individual-selection binding is missing'
grep -Fq 'on = ["<S-Up>"]' "$KEYMAP" \
  || fail 'Yazi Shift+Up range-selection binding is missing'
grep -Fq 'on = ["<S-Down>"]' "$KEYMAP" \
  || fail 'Yazi Shift+Down range-selection binding is missing'
grep -Fq 'AwtarchyYaziConfirmQuit(false)' "$KEYMAP" \
  || fail 'Yazi q quit confirmation binding is missing'
grep -Fq 'AwtarchyYaziConfirmQuit(true)' "$KEYMAP" \
  || fail 'Yazi Q quit-without-cwd confirmation binding is missing'
grep -Fq 'AwtarchyYaziCloseTab()' "$KEYMAP" \
  || fail 'Yazi Ctrl+W tab-close replacement is missing'
if ! grep -Fq '[confirm]' "$KEYMAP" \
  || ! grep -Fq '{ on = ["<Space>"], run = "close --submit", desc = "Confirm" }' "$KEYMAP"; then
  fail 'Yazi quit confirmation does not accept Space'
fi
grep -Fq 'desc = "Cut selected files"' "$KEYMAP" \
  || fail 'Yazi Ctrl+X cut binding is not documented'
grep -Fq 'desc = "Paste copied/cut files"' "$KEYMAP" \
  || fail 'Yazi Ctrl+V paste binding is not documented'
if grep -Fq 'XYenon/clipboard' "$PACKAGE"; then
  fail 'Yazi package lock still installs the deprecated clipboard plugin'
fi

if grep -Eq '^[[:space:]]*#' "$YAZI_INIT"; then
  fail 'Yazi init.lua contains shell-style hash comments instead of Lua comments'
fi
if command -v luac >/dev/null 2>&1; then
  luac -p "$YAZI_INIT" || fail 'Yazi init.lua does not parse as Lua'
elif command -v luac5.4 >/dev/null 2>&1; then
  luac5.4 -p "$YAZI_INIT" || fail 'Yazi init.lua does not parse as Lua'
else
  fail 'No Lua compiler is available to validate Yazi init.lua'
fi
grep -Fq 'function Linemode:size_and_mtime()' "$YAZI_INIT" \
  || fail 'Yazi combined size/date linemode is not defined'
grep -Fq 'function AwtarchyYaziSmartEnter()' "$YAZI_INIT" \
  || fail 'Yazi smart Enter helper is missing'
grep -Fq 'hovered and hovered.cha.is_dir and "enter" or "open"' "$YAZI_INIT" \
  || fail 'Yazi smart Enter helper does not distinguish directories from files'
grep -Fq 'function AwtarchyYaziEnsureRangeSelect()' "$YAZI_INIT" \
  || fail 'Yazi Shift+Arrow range-selection helper is missing'
grep -Fq 'function AwtarchyYaziToggleOrCommitSelection()' "$YAZI_INIT" \
  || fail 'Yazi Space toggle/commit helper is missing'
grep -Fq 'ya.emit("escape", { visual = true })' "$YAZI_INIT" \
  || fail 'Yazi Space does not commit an active range selection'
grep -Fq 'cx.active.mode.is_normal' "$YAZI_INIT" \
  || fail 'Yazi range selection does not preserve an existing visual selection'
grep -Fq 'function AwtarchyYaziConfirmQuit(no_cwd_file)' "$YAZI_INIT" \
  || fail 'Yazi quit confirmation helper is missing'
grep -Fq 'function AwtarchyYaziCloseTab()' "$YAZI_INIT" \
  || fail 'Yazi tab-close helper is missing'
grep -Fq 'if #cx.tabs > 1 then' "$YAZI_INIT" \
  || fail 'Yazi Ctrl+W does not distinguish tab close from last-tab quit'
grep -Fq 'title = "Quit Yazi?"' "$YAZI_INIT" \
  || fail 'Yazi quit confirmation prompt is missing'
grep -Fq 'Yes: Y / Enter / Space' "$YAZI_INIT" \
  || fail 'Yazi quit confirmation does not document affirmative keys'
grep -Fq 'No:  N / Esc' "$YAZI_INIT" \
  || fail 'Yazi quit confirmation does not document cancel keys'
grep -Fq 'ya.emit("quit", { no_cwd_file = no_cwd_file == true })' "$YAZI_INIT" \
  || fail 'Yazi quit confirmation does not preserve q/Q cwd-file semantics'
grep -Fq 'AwtarchyYaziContextMenu = {' "$YAZI_INIT" \
  || fail 'Yazi mouse context-menu component is missing'
grep -Fq 'Modal:children_add(AwtarchyYaziContextMenu, 20)' "$YAZI_INIT" \
  || fail 'Yazi mouse context menu is not registered as a clickable modal child'
grep -Fq 'function Current:click(event, up)' "$YAZI_INIT" \
  || fail 'Yazi current-pane click handler does not support blank-space actions'
grep -Fq 'AwtarchyYaziContextMenu:show("background", event.x, event.y)' "$YAZI_INIT" \
  || fail 'Yazi blank-space right-click does not open folder actions'
grep -Fq 'AwtarchyYaziContextMenu:show("item", event.x, event.y, selected_count)' "$YAZI_INIT" \
  || fail 'Yazi item right-click does not open selection-aware item actions'
grep -Fq 'function Header:click(event, up)' "$YAZI_INIT" \
  || fail 'Yazi header path mouse clipboard behavior is missing'
grep -Fq 'ya.emit("copy", { "dirpath" })' "$YAZI_INIT" \
  || fail 'Yazi header click does not use native current-directory path copying'
grep -Fq 'Copied to clipboard: ' "$YAZI_INIT" \
  || fail 'Yazi header click does not report clipboard success'
grep -Fq '{ label = "New file", shortcut = "a", action = "new_file" }' "$YAZI_INIT" \
  || fail 'Yazi folder context menu lacks New file with keyboard hint'
grep -Fq '{ label = "New folder", shortcut = "a /", action = "new_folder" }' "$YAZI_INIT" \
  || fail 'Yazi folder context menu lacks New folder with create convention hint'
grep -Fq '{ label = "Terminal here", shortcut = "t e", action = "terminal" }' "$YAZI_INIT" \
  || fail 'Yazi folder context menu lacks Terminal here with keyboard parity'
grep -Fq '{ label = "Rename", shortcut = "r", action = "rename" }' "$YAZI_INIT" \
  || fail 'Yazi item context menu lacks Rename shortcut hint'
grep -Fq '{ label = "Trash", shortcut = "dd", action = "trash" }' "$YAZI_INIT" \
  || fail 'Yazi item context menu lacks Trash shortcut hint'
grep -Fq 'Keys: Enter open | r rename | Ctrl+C/X copy/cut | c z ZIP' "$YAZI_INIT" \
  || fail 'Yazi item context footer does not teach keyboard equivalents'
grep -Fq 'Keys: a create | Ctrl+V/p paste | t e terminal' "$YAZI_INIT" \
  || fail 'Yazi blank-space context footer does not teach keyboard equivalents'
grep -Fq 'ya.emit("create", { dir = true })' "$YAZI_INIT" \
  || fail 'Yazi New folder does not use the stable native create dir flag'
grep -Fq 'function AwtarchyYaziCompressSelection()' "$YAZI_INIT" \
  || fail 'Yazi ZIP compression helper is missing'
grep -Fq 'function AwtarchyYaziExtractZipHere()' "$YAZI_INIT" \
  || fail 'Yazi extract-here helper is missing'
grep -Fq 'function AwtarchyYaziExtractZipFolder()' "$YAZI_INIT" \
  || fail 'Yazi extract-to-folder helper is missing'
grep -Fq 'Compress to ZIP...' "$YAZI_INIT" \
  || fail 'Yazi context menu does not expose ZIP compression'
grep -Fq 'Extract here' "$YAZI_INIT" \
  || fail 'Yazi context menu does not expose extract-here'
grep -Fq 'Extract to folder' "$YAZI_INIT" \
  || fail 'Yazi context menu does not expose extract-to-folder'
grep -Fq '7zz' "$YAZI_INIT" \
  || fail 'Yazi archive helper does not support the upstream 7zz command name'
grep -Fq '7z' "$YAZI_INIT" \
  || fail 'Yazi archive helper does not support the Arch 7z command name'
grep -Fq 'string.format("%s (%d).zip", stem, index)' "$YAZI_INIT" \
  || fail 'Yazi ZIP creation does not protect existing archive names'
grep -Fq '"-aou"' "$YAZI_INIT" \
  || fail 'Yazi extract-here does not auto-rename colliding files'
if ! grep -Fq '"Terminal Apps:' "$RUNTIME" \
  || ! grep -Fq ' 7zip ' "$RUNTIME"; then
  fail 'Awtarchy does not install 7zip for Yazi archive actions'
fi
# This assertion intentionally searches for the literal managed $HOME path.
# shellcheck disable=SC2016
grep -Fq '"$HOME/.config/hypr/scripts/default_terminal.sh" -- bash' "$YAZI_INIT" \
  || fail 'Yazi Terminal here does not use Awtarchy default terminal resolution'
grep -Fq 'function Entity:click(event, up)' "$YAZI_INIT" \
  || fail 'Yazi custom entity click handler is missing'
grep -Fq 'local was_hovered = self._file.is_hovered' "$YAZI_INIT" \
  || fail 'Yazi click handler does not preserve pre-click highlighted state'
grep -Fq 'ya.emit("reveal", { self._file.url })' "$YAZI_INIT" \
  || fail 'Yazi click handler no longer selects newly clicked rows'
grep -Fq 'elseif was_hovered then' "$YAZI_INIT" \
  || fail 'Yazi second-click action guard is missing'
grep -Fq 'ya.emit("open", { hovered = true })' "$YAZI_INIT" \
  || fail 'Yazi second-click file opening is missing'
grep -Fq 'event.is_middle' "$YAZI_INIT" \
  || fail 'Yazi middle-click directory handling is missing'
grep -Fq 'ya.emit("tab_create", { tostring(self._file.url) })' "$YAZI_INIT" \
  || fail 'Yazi middle-click does not open directories in a new tab'
grep -Fq 'self._selection_count > 1' "$YAZI_INIT" \
  || fail 'Yazi context menu does not expose multi-selection count'
grep -Fq 'function AwtarchyYaziContextMenu:move(event)' "$YAZI_INIT" \
  || fail 'Yazi context menu hover handling is missing'
grep -Fq 'row:style(th.help.hovered)' "$YAZI_INIT" \
  || fail 'Yazi context menu does not highlight the hovered action'
grep -Fq 'function Entity:drag(event)' "$YAZI_INIT" \
  || fail 'Yazi internal drag gesture handling is missing'
grep -Fq 'AwtarchyYaziContextMenu:show_drop' "$YAZI_INIT" \
  || fail 'Yazi drag release over a directory does not open Copy/Move choices'
grep -Fq 'AwtarchyYaziDropInto("copy"' "$YAZI_INIT" \
  || fail 'Yazi internal drag cannot copy selected items into a folder'
grep -Fq 'AwtarchyYaziDropInto("move"' "$YAZI_INIT" \
  || fail 'Yazi internal drag cannot move selected items into a folder'
if grep -Fq 'wgdotw.exe' "$YAZI_INIT" || grep -Fq 'dragon-drop' "$YAZI_INIT"; then
  fail 'Awtarchy Yazi internal drag depends on an external Windows/DragonDrop helper'
fi
grep -Fq 'ya.readable_size(size)' "$YAZI_INIT" \
  || fail 'Yazi combined linemode does not use native readable file sizes'
grep -Fq 'self._file.cha.mtime' "$YAZI_INIT" \
  || fail 'Yazi combined linemode does not use the current stable Yazi mtime API'
if grep -Fq 'self._file.stat.mtime' "$YAZI_INIT"; then
  fail 'Yazi combined linemode uses the incompatible nightly stat.mtime API'
fi
grep -Fq '"%d/%d/%02d"' "$YAZI_INIT" \
  || fail 'Yazi combined linemode does not use compact M/D/YY dates'
grep -Fq '"%9s  %8s"' "$YAZI_INIT" \
  || fail 'Yazi combined linemode lost size/date alignment'
grep -Fq 'function Status:selected_count()' "$YAZI_INIT" \
  || fail 'Yazi multi-selection count status is missing'
grep -Fq 'local count = #cx.active.selected' "$YAZI_INIT" \
  || fail 'Yazi multi-selection status does not use the cheap selected-item count'
grep -Fq 'if count < 2 then' "$YAZI_INIT" \
  || fail 'Yazi selection count should stay hidden for zero/one selected item'
grep -Fq '" %d selected "' "$YAZI_INIT" \
  || fail 'Yazi multi-selection status text changed'
grep -Fq 'function Status:modified_time()' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item modified timestamp is not defined'
grep -Fq 'hovered.cha.mtime' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item timestamp does not use stable hovered cha.mtime metadata'
if grep -Fq '.stat.mtime' "$YAZI_INIT"; then
  fail 'Yazi modified timestamp uses the incompatible development stat.mtime API'
fi
grep -Fq 'AwtarchyYaziTimeFormat = "24h"' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item time does not default to 24-hour format'
grep -Fq 'ps.sub("@awtarchy-yazi-time-format"' "$YAZI_INIT" \
  || fail 'Yazi time-format preference is not restored through retained DDS state'
grep -Fq 'ps.pub("@awtarchy-yazi-time-format", next_format)' "$YAZI_INIT" \
  || fail 'Yazi time-format toggle is not persisted through retained DDS state'
grep -Fq 'function AwtarchyYaziToggleTimeFormat()' "$YAZI_INIT" \
  || fail 'Yazi time-format toggle function is missing'
grep -Fq 'Modified: %d/%d/%02d %02d:%02d' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item timestamp lacks 24-hour modified time'
grep -Fq 'Modified: %d/%d/%02d %d:%02d %s' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item timestamp lacks 12-hour modified time'
grep -Fq 'parts.hour % 12' "$YAZI_INIT" \
  || fail 'Yazi 12-hour mode does not convert midnight/noon correctly'
grep -Fq '"AM" or "PM"' "$YAZI_INIT" \
  || fail 'Yazi 12-hour mode does not label AM/PM'
grep -Fq 'Status:children_add(function(self)' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item timestamp is not attached to the status component'
grep -Fq '500, Status.RIGHT' "$YAZI_INIT" \
  || fail 'Yazi highlighted-item timestamp is not placed on the right side of status'

python3 - "$YAZI_CONFIG" <<'PY' || fail 'Yazi edit opener or combined metadata linemode is not configured correctly'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

if config.get("mgr", {}).get("linemode") != "size_and_mtime":
    raise SystemExit(1)

rules = config.get("opener", {}).get("edit", [])
if not isinstance(rules, list):
    raise SystemExit(1)

if not any(
    isinstance(rule, dict)
    and rule.get("run") == "/usr/bin/xdg-open %s"
    and rule.get("for") == "unix"
    for rule in rules
):
    raise SystemExit(1)

for rule in rules:
    if not isinstance(rule, dict):
        continue
    run = str(rule.get("run", ""))
    if "micro" in run.lower() or "$EDITOR" in run or "${EDITOR" in run:
        raise SystemExit(1)
PY

grep -Fq 'text/plain=micro.desktop' "$MIMEAPPS" \
  || fail 'Awtarchy default text/plain association is no longer Micro'
grep -Fq 'repair_v373_yazi_default_editor_target()' "$RUNTIME" \
  || fail 'runtime has no v3.7.3 Yazi default-editor delivery repair'
# These assertions intentionally search for literal shell variables in runtime source.
# shellcheck disable=SC2016
grep -Fq '[[ "$tag" == "v3.7.3" ]] || return 0' "$RUNTIME" \
  || fail 'v3.7.3 Yazi default-editor repair is not tag scoped'
# shellcheck disable=SC2016
grep -Fq 'repair_v373_yazi_default_editor_target "$target_home" "$tag"' "$RUNTIME" \
  || fail 'stable update path does not apply the v3.7.3 Yazi default-editor repair'
grep -Fq '{ run = "/usr/bin/xdg-open %s", for = "unix", desc = "Open with default editor" }' "$RUNTIME" \
  || fail 'v3.7.3 stable repair does not install the default-editor Yazi opener'
# shellcheck disable=SC2016
build_line="$(grep -nF 'build_target_home "$repo_dir" "$target_home"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
# shellcheck disable=SC2016
repair_line="$(grep -nF 'repair_v373_yazi_default_editor_target "$target_home" "$tag"' "$RUNTIME" | tail -n1 | cut -d: -f1)"
[[ "$build_line" =~ ^[0-9]+$ && "$repair_line" =~ ^[0-9]+$ && "$repair_line" -gt "$build_line" ]] \
  || fail 'v3.7.3 Yazi default-editor repair does not run after the stable target is built'
grep -Fq ' xdg-utils ' "$RUNTIME" \
  || fail 'xdg-utils is no longer part of the managed package catalog'
grep -Fq '"Window Management:hyprland hyprpaper hypridle hyprpicker hyprsunset quickshell qt6-multimedia qt6-multimedia-ffmpeg grim satty slurp wl-clipboard ' "$RUNTIME" \
  || fail 'wl-clipboard is no longer part of the managed Window Management package set'
grep -Fq 'is_legacy_yazi_clipboard_plugin()' "$RUNTIME" \
  || fail 'runtime has no guarded migration for the old Awtarchy clipboard plugin'
grep -Fq -- '---@class ClipboardJobArgs' "$RUNTIME" \
  || fail 'legacy plugin migration does not identify the old plugin specifically'
grep -Fq -- 'function M:path_to_file_uri' "$RUNTIME" \
  || fail 'legacy plugin migration lacks a second upstream identity marker'
grep -Fq 'A custom Yazi clipboard.yazi plugin remains' "$RUNTIME" \
  || fail 'runtime does not preserve unrelated user clipboard.yazi plugins'

# These assertions intentionally search for literal shell variables in runtime source.
# shellcheck disable=SC2016
install_count="$(grep -Fc 'run_as_target rm -rf -- "$legacy_yazi_clipboard"' "$RUNTIME" || true)"
# shellcheck disable=SC2016
update_count="$(grep -Fc 'run_target rm -rf -- "$legacy_yazi_clipboard"' "$RUNTIME" || true)"
(( install_count == 1 )) || fail 'installer does not remove exactly one recognized legacy clipboard plugin'
(( update_count == 1 )) || fail 'updater does not remove exactly one recognized legacy clipboard plugin'

printf '%s\n' 'PASS: Yazi preserves compact size/date rows and native create/find/navigation, supports mouse context menus with keyboard hints plus smart directory entry, shows highlighted modified time with a persistent 24h/12h toggle in Help, keeps clipboard behavior without DragonDrop, delegates text opening to the desktop default application, and migrates only the deprecated Awtarchy plugin.'
