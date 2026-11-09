#!/usr/bin/env bash
# Never touch the desktop during this test: all compositor and wallpaper
# commands are synthetic and the HOME points to a temporary directory.
set -euo pipefail
trap 'printf "FAIL: Mango wallpaper restore test line %s: %s\\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home/.config/awtwall" "$tmp/home/Pictures/wallpapers" "$tmp/bin"
touch "$tmp/home/Pictures/wallpapers/awtarchy_geology.png"
touch "$tmp/home/Pictures/wallpapers/a.png" "$tmp/home/Pictures/wallpapers/b.jpg"
cat >"$tmp/bin/mmsg" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == 'get all-monitors' ]] || return 1
printf '%s\n' '{"monitors":[{"name":"DP-3"},{"name":"DP-1"}]}'
MOCK
cat >"$tmp/bin/awww" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == query ]]; then exit 0; fi
printf '%s\n' "$*" >>"$AWTARCHY_MOCK_WALLPAPER_ACTIONS"
MOCK
cat >"$tmp/bin/awww-daemon" <<'MOCK'
#!/usr/bin/env bash
printf 'daemon-started\n' >>"$AWTARCHY_MOCK_WALLPAPER_ACTIONS"
MOCK
cat >"$tmp/bin/hyprpaper" <<'MOCK'
#!/usr/bin/env bash
printf 'WRONG-COMPOSITOR\n' >>"$AWTARCHY_MOCK_WALLPAPER_ACTIONS"
MOCK
chmod +x "$tmp/bin/"*

export PATH="$tmp/bin:$PATH" HOME="$tmp/home"
export XDG_CURRENT_DESKTOP=mango MANGO_INSTANCE_SIGNATURE=mock
export WAYLAND_DISPLAY=wayland-test
export AWTARCHY_MOCK_WALLPAPER_ACTIONS="$tmp/actions"
script=config/mango/scripts/wallpaper.sh
bash -n "$script"

# Saved backend is intentionally Hyprpaper: Mango must never invoke it.
printf 'backend\thyprpaper\nDP-3\thyprpaper\t%s\nDP-1\thyprpaper\t%s\n' \
    "$HOME/Pictures/wallpapers/a.png" "$HOME/Pictures/wallpapers/b.jpg" \
    >"$HOME/.config/awtwall/backend_state.tsv"
cp "$HOME/.config/awtwall/backend_state.tsv" "$tmp/backup"
bash "$script"
cmp "$HOME/.config/awtwall/backend_state.tsv" "$tmp/backup"
grep -Fxq "img --outputs DP-3 --resize crop --transition-type none $HOME/Pictures/wallpapers/a.png" "$tmp/actions"
grep -Fxq "img --outputs DP-1 --resize crop --transition-type none $HOME/Pictures/wallpapers/b.jpg" "$tmp/actions"
if grep -q 'WRONG-COMPOSITOR' "$tmp/actions"; then
    printf 'ERROR: Hyprpaper was launched in Mango\n' >&2
    false
fi

# A stale output is skipped rather than redirected to an unrelated screen.
: >"$tmp/actions"
printf 'DP-99\thyprpaper\t%s\nDP-1\thyprpaper\t%s\n' \
    "$HOME/Pictures/wallpapers/a.png" "$HOME/Pictures/wallpapers/b.jpg" \
    >"$HOME/.config/awtwall/backend_state.tsv"
bash "$script"
if [[ "$(wc -l <"$tmp/actions")" != 1 ]]; then
    printf 'Unexpected saved-output restore actions:\\n' >&2
    sed -n '1,8p' "$tmp/actions" >&2
    false
fi
grep -Fq 'DP-1' "$tmp/actions"

# A linked state file is not trusted; seed wallpaper is used only in Mango.
rm "$HOME/.config/awtwall/backend_state.tsv"
ln -s "$tmp/backup" "$HOME/.config/awtwall/backend_state.tsv"
: >"$tmp/actions"
bash "$script"
[[ "$(wc -l <"$tmp/actions")" == 2 ]]
grep -Fxq "img --outputs DP-3 --resize crop --transition-type none $HOME/Pictures/wallpapers/awtarchy_geology.png" "$tmp/actions"
grep -Fxq "img --outputs DP-1 --resize crop --transition-type none $HOME/Pictures/wallpapers/awtarchy_geology.png" "$tmp/actions"

before="$(wc -l <"$tmp/actions")"
if XDG_CURRENT_DESKTOP=Hyprland bash "$script" >/dev/null 2>&1; then
    printf 'ERROR: Mango wallpaper helper accepted Hyprland\n' >&2
    false
fi
[[ "$(wc -l <"$tmp/actions")" == "$before" ]]
printf 'PASS: Mango wallpaper restore, user-state preservation and compositor isolation\n'
