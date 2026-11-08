#!/usr/bin/env bash
# Mango-specific persisted Bibata cursor preference, without modifying Hyprland Lua.
set -Eeuo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
state="$cache/awtarchy/quickshell-state.json"
writer="$config/hypr/scripts/quickshell_application_state.sh"
mango="$config/mango/config.conf"
gtk3="$config/gtk-3.0/settings.ini"
nwg="$data/nwg-look/gsettings"
xresources="$HOME/.Xresources"

variant_to_theme() {
  case "$1" in
    amber) printf '%s\n' Bibata-Modern-Amber ;;
    classic) printf '%s\n' Bibata-Modern-Classic ;;
    ice) printf '%s\n' Bibata-Modern-Ice ;;
    amber-sharp) printf '%s\n' Bibata-Original-Amber ;;
    classic-sharp) printf '%s\n' Bibata-Original-Classic ;;
    ice-sharp) printf '%s\n' Bibata-Original-Ice ;;
    amber-right) printf '%s\n' Bibata-Modern-Amber-Right ;;
    classic-right) printf '%s\n' Bibata-Modern-Classic-Right ;;
    ice-right) printf '%s\n' Bibata-Modern-Ice-Right ;;
    amber-sharp-right) printf '%s\n' Bibata-Original-Amber-Right ;;
    classic-sharp-right) printf '%s\n' Bibata-Original-Classic-Right ;;
    ice-sharp-right) printf '%s\n' Bibata-Original-Ice-Right ;;
    *) return 2 ;;
  esac
}

saved_variant() {
  local variant=ice
  if [[ -f "$state" ]]; then
    variant="$(jq -er '.cursor_variant // "ice"' "$state" 2>/dev/null || printf ice)"
  fi
  variant_to_theme "$variant" >/dev/null || variant=ice
  printf '%s\n' "$variant"
}

apply_variant() {
  local variant="$1" theme
  theme="$(variant_to_theme "$variant")" || return 2
  [[ -d "/usr/share/icons/$theme" || -d "$data/icons/$theme" ]] || {
    printf 'Mango cursor theme missing: %s\n' "$theme" >&2
    return 1
  }
  python3 - "$theme" "$mango" "$gtk3" "$nwg" "$xresources" <<'PY'
import os
from pathlib import Path
import re
import sys
import tempfile

theme = sys.argv[1]
paths = [Path(s) for s in sys.argv[2:]]
patterns = [
    [(r'^cursor_theme=[^\n]*$', 'cursor_theme=' + theme),
     (r'^env=XCURSOR_THEME,[^\n]*$', 'env=XCURSOR_THEME,' + theme)],
    [(r'^gtk-cursor-theme-name=[^\n]*$', 'gtk-cursor-theme-name=' + theme)],
    [(r'^cursor-theme=[^\n]*$', 'cursor-theme=' + theme)],
    [(r'^Xcursor\.theme:[^\n]*$', 'Xcursor.theme: ' + theme)],
]
planned = []
for path, rules in zip(paths, patterns):
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"Unsafe or absent cursor config: {path}")
    old = path.read_text(encoding='utf-8')
    new = old
    for pattern, replacement in rules:
        new, count = re.subn(pattern, lambda _m: replacement, new,
                             count=1, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit(f"Missing managed cursor setting {pattern}: {path}")
    planned.append((path, new))
for path, content in planned:
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
    try:
        os.fchmod(fd, path.stat().st_mode & 0o777)
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write(content)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
PY

  if command -v mmsg >/dev/null 2>&1 && [[ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]]; then
    mmsg dispatch "setoption,cursor_theme,$theme" >/dev/null
    mmsg dispatch "setoption,cursor_size,24" >/dev/null
  fi
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface cursor-theme "$theme" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface cursor-size 24 >/dev/null 2>&1 || true
  fi
  if command -v flatpak >/dev/null 2>&1; then
    flatpak override --user --env="GTK_CURSOR_THEME=$theme" >/dev/null 2>&1 || true
  fi
  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    XCURSOR_THEME="$theme" XCURSOR_SIZE=24 \
      dbus-update-activation-environment --systemd XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true
  fi
}

case "${1:-status}" in
  status) saved_variant ;;
  reapply) apply_variant "$(saved_variant)" ;;
  set)
    [[ -n "${2:-}" ]] || { printf 'Usage: %s set <variant>\n' "$0" >&2; exit 2; }
    variant_to_theme "$2" >/dev/null
    [[ -f "$writer" && ! -L "$writer" ]] || { printf 'Missing state writer\n' >&2; exit 1; }
    bash "$writer" set-cursor-theme "$2"
    apply_variant "$2"
    ;;
  *) printf 'Usage: %s status|reapply|set <variant>\n' "$0" >&2; exit 2 ;;
esac
