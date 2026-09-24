#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KEYMAP="$ROOT/config/yazi/keymap.toml"
PACKAGE="$ROOT/config/yazi/package.toml"
YAZI_CONFIG="$ROOT/config/yazi/yazi.toml"
YAZI_THEME="$ROOT/config/yazi/theme.toml"
YAZI_INIT="$ROOT/config/yazi/init.lua"
YAZI_RECENT="$ROOT/config/yazi/plugins/recent-files.yazi/main.lua"
YAZI_BOOKMARKS="$ROOT/config/yazi/plugins/bookmarks.yazi/main.lua"
YAZI_MOUNTS="$ROOT/config/yazi/plugins/mounts.yazi/main.lua"
YAZI_GIT="$ROOT/config/yazi/plugins/git.yazi/main.lua"
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
    ("<Right>",): 'lua "AwtarchyYaziRight()"',
    ("<Left>",): 'lua "AwtarchyYaziLeft()"',
    ("<Up>",): 'lua "AwtarchyYaziArrow(-1)"',
    ("<Down>",): 'lua "AwtarchyYaziArrow(1)"',
    ("k",): "arrow prev",
    ("j",): "arrow next",
    ("g", "g"): "arrow top",
    ("G",): "arrow bot",
    ("<Enter>",): 'lua "AwtarchyYaziSmartEnter()"',
    ("g", "r"): "plugin recent-files",
    ("g", "b"): "plugin bookmarks",
    ("g", "B"): 'lua "AwtarchyYaziToggleBookmark()"',
    ("g", "m"): "plugin mounts",
    ("<C-f>",): 'lua "AwtarchyYaziSearchMenu()"',
    ("<Esc>",): 'lua "AwtarchyYaziEscape()"',
    ("o",): 'lua "AwtarchyYaziOpen(false)"',
    ("O",): 'lua "AwtarchyYaziOpen(true)"',
    ("<S-Enter>",): 'lua "AwtarchyYaziOpen(true)"',
    ("q",): 'lua "AwtarchyYaziConfirmQuit(false)"',
    ("Q",): 'lua "AwtarchyYaziConfirmQuit(true)"',
    ("<C-w>",): 'lua "AwtarchyYaziCloseTab()"',
    ("<C-t>",): "tab_create --current",
    ("<C-1>",): "tab_switch 0",
    ("<C-2>",): "tab_switch 1",
    ("<C-3>",): "tab_switch 2",
    ("<C-4>",): "tab_switch 3",
    ("<C-5>",): "tab_switch 4",
    ("<C-6>",): "tab_switch 5",
    ("<C-7>",): "tab_switch 6",
    ("<C-8>",): "tab_switch 7",
    ("<C-9>",): "tab_switch 8",
    ("<Space>",): "toggle",
    ("<C-Space>",): "toggle",
    ("<S-Up>",): 'lua "AwtarchyYaziShiftArrow(-1)"',
    ("<S-Down>",): 'lua "AwtarchyYaziShiftArrow(1)"',
    ("<Delete>",): "remove",
    ("<C-x>",): "yank --cut",
    ("<C-v>",): "paste",
    ("c", "z"): 'lua "AwtarchyYaziCompressSelection()"',
    ("e", "h"): 'lua "AwtarchyYaziExtractZipHere()"',
    ("e", "f"): 'lua "AwtarchyYaziExtractZipFolder()"',
    ("t", "e"): 'shell --orphan -- "$HOME/.config/hypr/scripts/default_terminal.sh" -- bash',
    ("t", "n"): 'lua "AwtarchyYaziOpenHoveredTab()"',
    ("m", "t"): 'lua "AwtarchyYaziToggleTimeFormat()"',
    ("m", "v"): 'lua "AwtarchyYaziTogglePreview()"',
    ("m", "x"): 'lua "AwtarchyYaziTogglePreviewMax()"',
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
if by_keys.get(("g", "B"), {}).get("desc") != "Bookmark current directory":
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
  luac -p "$YAZI_RECENT" || fail 'Yazi recent-files plugin does not parse as Lua'
  luac -p "$YAZI_BOOKMARKS" || fail 'Yazi bookmarks plugin does not parse as Lua'
  luac -p "$YAZI_MOUNTS" || fail 'Yazi mounts plugin does not parse as Lua'
  luac -p "$YAZI_GIT" || fail 'Yazi git plugin does not parse as Lua'
elif command -v luac5.4 >/dev/null 2>&1; then
  luac5.4 -p "$YAZI_INIT" || fail 'Yazi init.lua does not parse as Lua'
  luac5.4 -p "$YAZI_RECENT" || fail 'Yazi recent-files plugin does not parse as Lua'
  luac5.4 -p "$YAZI_BOOKMARKS" || fail 'Yazi bookmarks plugin does not parse as Lua'
  luac5.4 -p "$YAZI_MOUNTS" || fail 'Yazi mounts plugin does not parse as Lua'
  luac5.4 -p "$YAZI_GIT" || fail 'Yazi git plugin does not parse as Lua'
else
  fail 'No Lua compiler is available to validate Yazi Lua'
fi
grep -Fq 'function Linemode:size_and_mtime()' "$YAZI_INIT" \
  || fail 'Yazi combined size/date linemode is not defined'
grep -Fq 'require("recent-files")' "$YAZI_INIT" \
  || fail 'Yazi init does not load the managed recent-files plugin'
grep -Fq 'require("recent-files"):setup()' "$YAZI_INIT" \
  || fail 'Yazi recent-files DDS state is not initialized at startup'
grep -Fq 'tostring(file.url)' "$YAZI_INIT" \
  || fail 'Yazi recents are not recorded from the File.url API'
grep -Fq 'require("bookmarks"):setup()' "$YAZI_INIT" \
  || fail 'Yazi bookmarks DDS state is not initialized at startup'
grep -Fq 'require("git"):setup { order = 1500 }' "$YAZI_INIT" \
  || fail 'Yazi git status signs are not attached to the linemode'
grep -Fq 'function AwtarchyYaziSearchMenu()' "$YAZI_INIT" \
  || fail 'Yazi recursive search menu is missing'
grep -Fq 'ya.emit("search", { via = "fd" })' "$YAZI_INIT" \
  || fail 'Yazi recursive filename search does not use native fd search'
grep -Fq 'ya.emit("search", { via = "rg" })' "$YAZI_INIT" \
  || fail 'Yazi recursive content search does not use native rg search'
grep -Fq '{ on = "n", desc = "Name search" }' "$YAZI_INIT" \
  || fail 'Yazi recursive search chooser label is too verbose or changed'
grep -Fq '{ on = "c", desc = "Content search" }' "$YAZI_INIT" \
  || fail 'Yazi content search chooser label is too verbose or changed'
grep -Fq 'function AwtarchyYaziToggleBookmark()' "$YAZI_INIT" \
  || fail 'Yazi bookmark toggle helper is missing'
grep -Fq 'AwtarchyYaziBookmarkTarget(tostring(cx.active.current.cwd))' "$YAZI_INIT" \
  || fail 'Yazi g B does not bookmark the current directory'
grep -Fq 'AwtarchyYaziBookmarkTarget(tostring(hovered.url))' "$YAZI_INIT" \
  || fail 'Yazi item context menu cannot bookmark the actual hovered file or folder'
grep -Fq 'content = "No bookmarked items."' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks picker is not an item list'
grep -Fq 'ya.emit("reveal", { Url(item.path), raw = true })' "$YAZI_BOOKMARKS" \
  || fail 'Yazi file bookmarks do not reveal the bookmarked file'
grep -Fq 'function AwtarchyYaziOpenHoveredTab()' "$YAZI_INIT" \
  || fail 'Yazi keyboard open-folder-in-new-tab helper is missing'
grep -Fq '{ label = "Open in new tab", shortcut = "t n", action = "open_new_tab" }' "$YAZI_INIT" \
  || fail 'Yazi directory context menu lacks keyboard parity for new-tab opening'
grep -Fq 'function AwtarchyYaziTogglePreview()' "$YAZI_INIT" \
  || fail 'Yazi preview pane toggle is missing'
grep -Fq 'function AwtarchyYaziTogglePreviewMax()' "$YAZI_INIT" \
  || fail 'Yazi preview maximize toggle is missing'
grep -Fq 'AwtarchyYaziPreviewButton = {' "$YAZI_INIT" \
  || fail 'Yazi preview pane lacks the clickable maximize/restore button'
grep -Fq 'AwtarchyYaziPreviewToggleButton = {' "$YAZI_INIT" \
  || fail 'Yazi current pane lacks the clickable preview visibility toggle'
grep -Fq 'local label = visible and " 󰞔 " or " 󰞓 "' "$YAZI_INIT" \
  || fail 'Yazi preview visibility toggle glyphs changed'
grep -Fq 'x = area.x + area.w - 3' "$YAZI_INIT" \
  || fail 'Yazi preview visibility toggle is not at the current-pane right edge'
grep -Fq 'and " 󰘕 " or " 󰹶 "' "$YAZI_INIT" \
  || fail 'Yazi preview button does not use the compact restore/maximize glyphs'
grep -Fq 'w = 3' "$YAZI_INIT" \
  || fail 'Yazi preview button is not kept to a compact three-cell click target'
grep -Fq 'h = area.h - 1' "$YAZI_INIT" \
  || fail 'Yazi preview control does not reserve a non-overlapping bottom row'
grep -Fq 'AwtarchyYaziTogglePreviewMax()' "$YAZI_INIT" \
  || fail 'Yazi preview button is not wired to the maximize/restore action'
grep -Fq 'function AwtarchyYaziEscape()' "$YAZI_INIT" \
  || fail 'Yazi conditional Esc preview restore is missing'
grep -Fq 'ya.emit("escape", {})' "$YAZI_INIT" \
  || fail 'Yazi Esc no longer falls through to native manager escape'
grep -Fq 'function Header:cwd()' "$YAZI_INIT" \
  || fail 'Yazi clickable breadcrumb renderer is missing'
grep -Fq 'AwtarchyYaziBreadcrumbTarget' "$YAZI_INIT" \
  || fail 'Yazi breadcrumb forward trail state is missing'
grep -Fq 'local segments = AwtarchyYaziBreadcrumbSegments(cwd) or {}' "$YAZI_INIT" \
  || fail 'Yazi breadcrumb click handling does not recompute live hit regions'
grep -Fq ':type(ui.Border.PLAIN)' "$YAZI_INIT" \
  || fail 'Yazi custom context menu border is still rounded'
grep -Fq 'ui.Style():dim()' "$YAZI_INIT" \
  || fail 'Yazi breadcrumb forward trail is not visually dimmed'
grep -Fq 'function Status:task_summary()' "$YAZI_INIT" \
  || fail 'Yazi task summary status is missing'
grep -Fq 'ya.emit("tasks:show", {})' "$YAZI_INIT" \
  || fail 'Yazi active task status is not clickable'
grep -Fq 'action = "bulk_rename"' "$YAZI_INIT" \
  || fail 'Yazi multi-selection context menu lacks bulk rename'
grep -Fq 'local function AwtarchyYaziOpenFiles(interactive, hovered_only)' "$YAZI_INIT" \
  || fail 'Yazi central file-open recorder is missing'
grep -Fq 'if file and not file.cha.is_dir then' "$YAZI_INIT" \
  || fail 'Yazi recent history does not exclude hovered directories'
grep -Fq 'if not file.cha.is_dir then' "$YAZI_INIT" \
  || fail 'Yazi recent history does not exclude selected directories'
grep -Fq 'AwtarchyYaziPluginArgs("record", recent)' "$YAZI_INIT" \
  || fail 'Yazi opened files are not routed through the recent-files plugin argument payload'
grep -Fq 'function AwtarchyYaziSmartEnter()' "$YAZI_INIT" \
  || fail 'Yazi smart Enter helper is missing'
grep -Fq 'if hovered and hovered.cha.is_dir then' "$YAZI_INIT" \
  || fail 'Yazi smart Enter no longer distinguishes directories from files'
grep -Fq 'AwtarchyYaziOpenFiles(false, false)' "$YAZI_INIT" \
  || fail 'Yazi smart Enter does not record and open files'
grep -Fq 'function AwtarchyYaziShiftArrow(step)' "$YAZI_INIT" \
  || fail 'Yazi Shift+Arrow range-selection helper is missing'
grep -Fq 'AwtarchyYaziShiftRangeActive = true' "$YAZI_INIT" \
  || fail 'Yazi Shift+Arrow selection is not tracked separately from native visual mode'
grep -Fq 'function AwtarchyYaziArrow(step)' "$YAZI_INIT" \
  || fail 'Yazi plain-arrow range commit helper is missing'
grep -Fq 'ya.emit("escape", { visual = true })' "$YAZI_INIT" \
  || fail 'Yazi plain arrow does not commit an active Shift+Arrow range'
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
if grep -Fq 'ya.sync(' "$YAZI_INIT"; then
  fail 'Yazi init.lua still uses plugin-only ya.sync'
fi
grep -Fq 'local function AwtarchyYaziArchiveSnapshot()' "$YAZI_INIT" \
  || fail 'Yazi archive snapshot helper is not plain synchronous init.lua code'
python3 - "$YAZI_INIT" <<'PY_RUNTIME_BOUNDARY' || fail 'Yazi archive snapshot is not captured before async work'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start = text.index("function AwtarchyYaziCompressSelection()")
end = text.index("function AwtarchyYaziExtractZipHere()", start)
block = text[start:end]
if block.index("local snapshot = AwtarchyYaziArchiveSnapshot()") > block.index("ya.async(function()"):
    raise SystemExit(1)
PY_RUNTIME_BOUNDARY
grep -Fq 'local function AwtarchyYaziPluginHex(value)' "$YAZI_INIT" \
  || fail 'Yazi plugin argument encoder is missing'
grep -Fq 'AwtarchyYaziPluginArgs("record", recent)' "$YAZI_INIT" \
  || fail 'Yazi recents do not pass opened file paths through the plugin argument payload'
grep -Fq 'AwtarchyYaziBookmarkTarget(tostring(cx.active.current.cwd))' "$YAZI_INIT" \
  || fail 'Yazi g B does not bookmark the current directory'
grep -Fq 'AwtarchyYaziBookmarkTarget(tostring(hovered.url))' "$YAZI_INIT" \
  || fail 'Yazi context menu cannot bookmark a precise hovered file/folder'
grep -Fq 'local function decode_arg(value)' "$YAZI_RECENT" \
  || fail 'Yazi recents cannot decode managed path arguments'
grep -Fq 'paths[#paths + 1] = decode_arg(job.args[i])' "$YAZI_RECENT" \
  || fail 'Yazi recents do not decode recorded file paths'
grep -Fq 'local path = decode_arg(job.args[2])' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks do not decode bookmark paths'

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
grep -Fq 'AwtarchyYaziPendingClick = {' "$YAZI_INIT" \
  || fail 'Yazi second-click action is not deferred until Mouse1 release'
grep -Fq 'pending.was_hovered' "$YAZI_INIT" \
  || fail 'Yazi release-open does not require the item to have been highlighted on Mouse1 down'
grep -Fq 'function Current:drag(event)' "$YAZI_INIT" \
  || fail 'Yazi internal drag gesture handling is missing at the current-pane layer'
grep -Fq 'AwtarchyYaziPendingClick = nil' "$YAZI_INIT" \
  || fail 'Yazi drag does not cancel pending click-open'
grep -Fq 'AwtarchyYaziOpenFiles(false, true)' "$YAZI_INIT" \
  || fail 'Yazi second-click file opening no longer records recents'
grep -Fq 'event.is_middle' "$YAZI_INIT" \
  || fail 'Yazi middle-click directory handling is missing'
grep -Fq 'ya.emit("tab_create", { tostring(self._file.url), raw = true })' "$YAZI_INIT" \
  || fail 'Yazi middle-click does not open directories in a new tab'
grep -Fq 'self._selection_count > 1' "$YAZI_INIT" \
  || fail 'Yazi context menu does not expose multi-selection count'
grep -Fq 'function AwtarchyYaziContextMenu:move(event)' "$YAZI_INIT" \
  || fail 'Yazi context menu hover handling is missing'
grep -Fq 'function Root:move(event)' "$YAZI_INIT" \
  || fail 'Yazi root does not route mouse-move events to the context menu'
grep -Fq 'row:style(th.help.hovered)' "$YAZI_INIT" \
  || fail 'Yazi context menu does not highlight the hovered action'
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

python3 - "$YAZI_CONFIG" "$YAZI_THEME" <<'PY' || fail 'Yazi edit opener, metadata linemode, or theme override is not configured correctly'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)
with open(sys.argv[2], "rb") as handle:
    theme = tomllib.load(handle)

if config.get("mgr", {}).get("linemode") != "size_and_mtime":
    raise SystemExit(1)

if config.get("mgr", {}).get("mouse_events") != ["click", "scroll", "drag", "move"]:
    raise SystemExit(1)

if theme.get("tabs", {}).get("sep_inner") != {"open": "", "close": ""}:
    raise SystemExit(1)
if theme.get("status", {}).get("sep_left") != {"open": "", "close": ""}:
    raise SystemExit(1)
if theme.get("indicator", {}).get("padding") != {"open": " ", "close": " "}:
    raise SystemExit(1)

fetchers = config.get("plugin", {}).get("prepend_fetchers", [])
expected_fetchers = {
    ("*", "git", "git"),
    ("*/", "git", "git"),
}
actual_fetchers = {
    (entry.get("url"), entry.get("run"), entry.get("group"))
    for entry in fetchers
    if isinstance(entry, dict)
}
if not expected_fetchers.issubset(actual_fetchers):
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
grep -Fq ' git fd ripgrep ' "$RUNTIME" \
  || fail 'fd/ripgrep are not managed for Yazi recursive search'
grep -Fq ' udisks2 ' "$RUNTIME" \
  || fail 'udisks2 is not managed for Yazi mount actions'
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

[[ -f "$YAZI_RECENT" ]] || fail 'managed recent-files plugin is missing'
[[ -f "$YAZI_BOOKMARKS" ]] || fail 'managed bookmarks plugin is missing'
[[ -f "$YAZI_MOUNTS" ]] || fail 'managed mounts plugin is missing'
[[ -f "$YAZI_GIT" ]] || fail 'managed git status plugin is missing'
grep -Fq 'local KIND = "@awtarchy-yazi-bookmarks"' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks do not use retained DDS static state'
grep -Fq 'local MAX_BOOKMARKS = 35' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmark history is not bounded'
grep -Fq 'ps.sub_remote(KIND' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks are not shared across sessions'
grep -Fq 'content = "No bookmarked items."' "$YAZI_BOOKMARKS" \
  || fail 'Yazi empty bookmarks message changed'
grep -Fq 'Command("udisksctl")' "$YAZI_MOUNTS" \
  || fail 'Yazi mount manager does not use udisksctl'
if grep -Fq 'sudo' "$YAZI_MOUNTS"; then
  fail 'Yazi mount manager invokes sudo instead of system PolicyKit'
fi
grep -Fq 'Linemode:children_add' "$YAZI_GIT" \
  || fail 'Yazi git signs do not augment the existing linemode'
grep -Fq 'local KIND = "@dillacorn-yazi-recent-files"' "$YAZI_RECENT" \
  || fail 'Yazi recents do not use retained DDS static state'
grep -Fq 'local MAX_RECENTS = 35' "$YAZI_RECENT" \
  || fail 'Yazi recent history is not bounded'
grep -Fq 'local snapshot = ya.sync' "$YAZI_RECENT" \
  || fail 'Yazi recents do not keep state behind the plugin sync boundary'
grep -Fq 'local record = ya.sync' "$YAZI_RECENT" \
  || fail 'Yazi recents do not record through plugin sync context'
grep -Fq 'ps.sub_remote(KIND' "$YAZI_RECENT" \
  || fail 'Yazi recents are not subscribed across sessions'
grep -Fq 'ps.pub_to(0, KIND, self.recents)' "$YAZI_RECENT" \
  || fail 'Yazi recents are not published across sessions'
grep -Fq 'content = "No recently opened files."' "$YAZI_RECENT" \
  || fail 'Yazi empty recent-files message changed'
grep -Fq 'cha and not cha.is_dir' "$YAZI_RECENT" \
  || fail 'Yazi recents picker does not filter directories'
grep -Fq 'ya.which' "$YAZI_RECENT" \
  || fail 'Yazi recent files do not use the native Which picker'
grep -Fq 'ya.emit("reveal"' "$YAZI_RECENT" \
  || fail 'Yazi recent selection does not reveal the file'
grep -Fq 'awtarchy-recent-files.txt' "$YAZI_RECENT" \
  || fail 'Yazi recents lack deterministic restart-safe state'
grep -Fq 'awtarchy-bookmarks.txt' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks lack deterministic restart-safe state'
grep -Fq 'ensure_state_dir()' "$YAZI_RECENT" \
  || fail 'Yazi recents do not create their state directory before first write'
grep -Fq 'ensure_state_dir()' "$YAZI_BOOKMARKS" \
  || fail 'Yazi bookmarks do not create their state directory before first write'

grep -Fq 'elseif not AwtarchyYaziPreviewMaximized and rt.mgr.ratio[3] > 0 then' "$YAZI_INIT" \
  || fail 'Yazi Right Arrow does not use the live preview ratio without the late-local scoping bug'
grep -Fq 'ya.emit("peek", { force = true })' "$YAZI_INIT" \
  || fail 'Yazi preview ratio changes do not force a stable re-peek'
grep -Fq 'ui.render()' "$YAZI_INIT" \
  || fail 'Yazi time-format toggle does not request an immediate UI redraw'
grep -Fq 'Entity:children_add(function()' "$YAZI_INIT" \
  || fail 'Yazi rows do not include managed leading spacing'
python3 - "$YAZI_INIT" "$YAZI_CONFIG" <<'PY_PREVIEW' || fail 'Yazi preview layout usability contract is not configured correctly'
from pathlib import Path
import sys
import tomllib

init = Path(sys.argv[1]).read_text()
with open(sys.argv[2], "rb") as handle:
    config = tomllib.load(handle)

current_start = init.index("function Current:new(area, tab)")
current_end = init.index("function Current:reflow()", current_start)
current_block = init[current_start:current_end]
if "x = area.x + area.w - 3" not in current_block:
    raise SystemExit(1)

preview = config.get("preview", {})
if preview.get("max_width") != 2000 or preview.get("max_height") != 2000:
    raise SystemExit(1)
PY_PREVIEW

printf '%s\n' 'PASS: Yazi preserves compact size/date rows and native create/find/navigation, supports mouse context menus with keyboard hints plus smart directory entry, shows highlighted modified time with a persistent 24h/12h toggle in Help, keeps clipboard behavior without DragonDrop, delegates text opening to the desktop default application, and migrates only the deprecated Awtarchy plugin.'
