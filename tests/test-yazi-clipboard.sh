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
    ("?",): "help",
}
for keys, run in expected.items():
    if by_keys.get(keys, {}).get("run") != run:
        raise SystemExit(1)
PY_KEYMAP
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

printf '%s\n' 'PASS: Yazi shows combined size/date metadata, inherits native create/find keys, uses native wraparound arrow/j/k navigation, preserves lowercase g/gg/G behavior, delegates text opening to the desktop default application, uses wl-clipboard for file copy, and migrates only the deprecated Awtarchy plugin.'
