#!/usr/bin/env bash
# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/sunshine_awtarchy_setup.sh
#
# Adds Awtarchy's Sunshine connect helper to Sunshine's global preparation
# commands without replacing user-defined preparation commands.
#
# This script never enables, starts, stops, or restarts Sunshine.

set -euo pipefail

# The literal $HOME must expand later in Sunshine's shell, not while this file is parsed.
# shellcheck disable=SC2016
HOOK='/usr/bin/env bash -lc "$HOME/.config/hypr/scripts/sunshine-moonlight-fix.sh"'

log() {
  printf 'sunshine-awtarchy: %s\n' "$*"
}

warn() {
  printf 'sunshine-awtarchy: WARN: %s\n' "$*" >&2
}

sunshine_present() {
  [[ "${AWTARCHY_SUNSHINE_FORCE:-0}" == "1" ]] && return 0

  command -v sunshine >/dev/null 2>&1 && return 0

  if command -v pacman >/dev/null 2>&1; then
    pacman -Qq sunshine >/dev/null 2>&1 && return 0
    pacman -Qq sunshine-bin >/dev/null 2>&1 && return 0
  fi

  return 1
}

sunshine_present || exit 0
command -v python3 >/dev/null 2>&1 || {
  warn "python3 is required to preserve Sunshine configuration safely."
  exit 1
}

config_home="${XDG_CONFIG_HOME:-${HOME:?HOME is required}/.config}"
config_dir="${AWTARCHY_SUNSHINE_CONFIG_DIR:-${config_home}/sunshine}"
config_file="${AWTARCHY_SUNSHINE_CONFIG_FILE:-${config_dir}/sunshine.conf}"

if [[ -L "$config_file" ]]; then
  warn "refusing symbolic-link Sunshine config: $config_file"
  exit 1
fi

if [[ ! -d "$config_dir" ]]; then
  install -d -m 0700 -- "$config_dir"
fi

result="$(
  python3 - "$config_file" "$HOOK" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from datetime import datetime

path = Path(sys.argv[1])
hook = sys.argv[2]
old = path.read_text(encoding="utf-8") if path.exists() else ""

assignment = re.compile(
    r"^(?P<prefix>[ \t]*global_prep_cmd[ \t]*=[ \t]*)(?P<value>.*?)(?P<ending>\r?\n?)$",
    re.MULTILINE,
)
matches = list(assignment.finditer(old))
if len(matches) > 1:
    print("error:multiple-global-prep")
    raise SystemExit(3)

commands = []
if matches:
    raw = matches[0].group("value").strip()
    try:
        commands = json.loads(raw)
    except json.JSONDecodeError:
        print("error:invalid-global-prep")
        raise SystemExit(4)
    if not isinstance(commands, list) or not all(isinstance(item, dict) for item in commands):
        print("error:invalid-global-prep")
        raise SystemExit(4)

hook_entries = [item for item in commands if item.get("do") == hook]
if hook_entries:
    # Collapse only exact Awtarchy duplicates. Never rewrite unrelated user commands.
    seen = False
    deduped = []
    for item in commands:
        if item.get("do") == hook:
            if seen:
                continue
            seen = True
        deduped.append(item)
    commands = deduped
else:
    commands.append({"do": hook, "undo": ""})

encoded = json.dumps(commands, ensure_ascii=False, separators=(",", ":"))

if matches:
    match = matches[0]
    replacement = f"{match.group('prefix')}{encoded}{match.group('ending')}"
    new = old[:match.start()] + replacement + old[match.end():]
else:
    separator = "" if not old or old.endswith(("\n", "\r")) else "\n"
    new = f"{old}{separator}global_prep_cmd = {encoded}\n"

if new == old:
    print("unchanged")
    raise SystemExit(0)

backup = ""
if path.exists():
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = path.with_name(f"{path.name}.awtarchy-backup.{stamp}")
    counter = 1
    while backup_path.exists():
        backup_path = path.with_name(f"{path.name}.awtarchy-backup.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, backup_path)
    backup = str(backup_path)

mode = (path.stat().st_mode & 0o777) if path.exists() else 0o600
fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        handle.write(new)
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp_name, mode)
    os.replace(tmp_name, path)
finally:
    if os.path.exists(tmp_name):
        os.unlink(tmp_name)

print(f"changed:{backup}")
PY
)" || {
  rc=$?
  case "$result" in
    error:multiple-global-prep)
      warn "multiple active global_prep_cmd assignments found; Sunshine config was left unchanged."
      ;;
    error:invalid-global-prep)
      warn "global_prep_cmd is not valid JSON; Sunshine config was left unchanged."
      ;;
    *)
      warn "could not update Sunshine configuration."
      ;;
  esac
  exit "$rc"
}

case "$result" in
  unchanged)
    log "Awtarchy Sunshine connect hook is already configured."
    ;;
  changed:*)
    backup="${result#changed:}"
    log "Configured Awtarchy Sunshine connect hook."
    [[ -n "$backup" ]] && log "Backup: $backup"
    log "Sunshine service/autostart state was not changed."
    ;;
  *)
    warn "unexpected configuration result: $result"
    exit 1
    ;;
esac
