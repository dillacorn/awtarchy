#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KEYMAP="$ROOT/config/yazi/keymap.toml"
PACKAGE="$ROOT/config/yazi/package.toml"
YAZI_CONFIG="$ROOT/config/yazi/yazi.toml"
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
if grep -Fq 'XYenon/clipboard' "$PACKAGE"; then
  fail 'Yazi package lock still installs the deprecated clipboard plugin'
fi

python3 - "$YAZI_CONFIG" <<'PY' || fail 'Yazi text opener is not pinned to blocking Micro'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)

rules = config.get("opener", {}).get("edit", [])
if not isinstance(rules, list):
    raise SystemExit(1)

if not any(
    isinstance(rule, dict)
    and rule.get("run") == "/usr/bin/micro %s"
    and rule.get("block") is True
    and rule.get("for") == "unix"
    for rule in rules
):
    raise SystemExit(1)

if any(
    isinstance(rule, dict)
    and ("$EDITOR" in str(rule.get("run", "")) or "${EDITOR" in str(rule.get("run", "")))
    for rule in rules
):
    raise SystemExit(1)
PY

grep -Fq '"Terminal Apps:nano micro ' "$RUNTIME" \
  || fail 'Micro is no longer part of the managed Terminal Apps package set'
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

printf '%s\n' 'PASS: Yazi uses Micro for text editing, wl-clipboard for file copy, and migrates only the deprecated Awtarchy plugin.'
