#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PICKER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"
QUICK_SETTINGS="${ROOT}/config/quickshell/awtarchy/QuickSettings.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

reject_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

[[ -x "$PICKER" ]] || fail 'lockscreen wallpaper picker helper is not executable'

# Stable picker identity and selection-only behavior are prerequisites for exact
# client targeting.
require_text "$PICKER" '--class awtarchy-lock-wallpaper --title Awtarchy-Lockscreen-Wallpaper' \
    'picker terminal identity is not exact and stable'
require_text "$PICKER" '--select-only --type images' \
    'picker no longer uses Awtwall selection-only mode'
require_text "$PICKER" '.address' \
    'picker does not resolve the mapped client address from hyprctl clients JSON'
require_text "$PICKER" 'address:' \
    'picker does not target the mapped client by exact address'
require_text "$PICKER" '.fullscreen' \
    'picker does not verify fullscreen state on the exact mapped client'
require_text "$PICKER" 'mode = "fullscreen"' \
    'picker does not request true fullscreen mode'
require_text "$PICKER" 'action = "set"' \
    'picker fullscreen request can still toggle out of fullscreen'

mkdir -p "$TMP/bin" "$TMP/cache" "$TMP/home"
selected_image="$TMP/selected image.png"
printf 'fixture\n' >"$selected_image"
: >"$TMP/hypr.log"
printf '0\n' >"$TMP/client-queries"
printf '0\n' >"$TMP/fullscreen-state"

cat >"$TMP/bin/awtwall" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
    printf '%s\n' '--select-only'
fi
EOF

cat >"$TMP/bin/alacritty" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$PICKER_TERMINAL_LOG"
while (( $# )); do
    if [[ "$1" == --select-result ]]; then
        printf '%s\n' "$PICKER_SELECTED_IMAGE" >"$2"
        break
    fi
    shift
done
EOF

cat >"$TMP/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == clients && "${2:-}" == -j ]]; then
    queries="$(cat "$PICKER_CLIENT_QUERIES")"
    queries=$((queries + 1))
    printf '%s\n' "$queries" >"$PICKER_CLIENT_QUERIES"
    # Deliberately appear after the rejected 20 x 50ms (~1 second) window.
    if (( queries < 26 )); then
        printf '%s\n' '[]'
        exit 0
    fi
    fullscreen="$(cat "$PICKER_FULLSCREEN_STATE")"
    printf '[{"address":"0xabc123","class":"awtarchy-lock-wallpaper","title":"Awtarchy-Lockscreen-Wallpaper","fullscreen":%s,"fullscreenClient":%s}]\n' \
        "$fullscreen" "$fullscreen"
    exit 0
fi

printf '%s\n' "$*" >>"$PICKER_HYPR_LOG"
if [[ "$*" == *'address:0xabc123'* \
        && "$*" == *'mode = "fullscreen"'* \
        && "$*" == *'action = "set"'* ]]; then
    printf '2\n' >"$PICKER_FULLSCREEN_STATE"
fi
EOF
chmod +x "$TMP/bin/awtwall" "$TMP/bin/alacritty" "$TMP/bin/hyprctl"

picker_output="$(
    PATH="$TMP/bin:$PATH" \
    HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" \
    AWTWALL_CMD="$TMP/bin/awtwall" \
    LOCKSCREEN_WALLPAPER_TERMINAL="$TMP/bin/alacritty" \
    PICKER_TERMINAL_LOG="$TMP/terminal.log" \
    PICKER_HYPR_LOG="$TMP/hypr.log" \
    PICKER_CLIENT_QUERIES="$TMP/client-queries" \
    PICKER_FULLSCREEN_STATE="$TMP/fullscreen-state" \
    PICKER_SELECTED_IMAGE="$selected_image" \
    bash "$PICKER"
)"

[[ "$picker_output" == "$selected_image" ]] \
    || fail 'picker did not preserve the selected absolute image path'
[[ "$(cat "$TMP/client-queries")" -ge 27 ]] \
    || fail 'picker did not wait beyond the rejected one-second map window and re-query fullscreen state'
[[ "$(cat "$TMP/fullscreen-state")" == 2 ]] \
    || fail 'picker never put the exact mapped client into true fullscreen state'
require_text "$TMP/hypr.log" 'address:0xabc123' \
    'picker dispatch did not target the mapped client address'
require_text "$TMP/hypr.log" 'mode = "fullscreen"' \
    'picker dispatch did not request true fullscreen mode'
reject_text "$TMP/hypr.log" 'class:^(awtarchy-lock-wallpaper)$' \
    'picker still targets a class match instead of the exact mapped client'

# Edit Layout is a persistent right-side action directly beneath the Lockscreen
# Expand/Collapse action, rather than being buried inside expanded precision UI.
require_text "$QUICK_SETTINGS" 'id: lockscreenHeaderActions' \
    'Lockscreen header has no right-side action column'
python3 - "$QUICK_SETTINGS" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
anchor = text.find("id: lockscreenHeaderActions")
if anchor < 0:
    raise SystemExit("missing lockscreenHeaderActions")
end = text.find("\n                                }", anchor)
if end < 0:
    raise SystemExit("could not bound lockscreenHeaderActions")
block = text[anchor:end]
collapse = block.find('label: root.lockscreenSectionExpanded ? "Collapse" : "Expand"')
edit = block.find('label: "Edit Layout"')
if collapse < 0 or edit < 0 or edit <= collapse:
    raise SystemExit("Edit Layout is not directly below Expand/Collapse in the right-side action column")
PY

printf '%s\n' 'PASS: exact mapped Awtwall fullscreen targeting and Lockscreen Edit Layout placement'
