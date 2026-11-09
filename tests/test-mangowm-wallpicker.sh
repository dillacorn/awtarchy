#!/usr/bin/env bash
# Do not launch real AwtWall; assert Mango wrapper selects supported backend.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p -- "$tmp/bin"
cat >"$tmp/bin/awtwall" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWTARCHY_MOCK_AWTWALL"
MOCK
cat >"$tmp/bin/awww" <<'MOCK'
#!/usr/bin/env bash
:
MOCK
cat >"$tmp/bin/awww-daemon" <<'MOCK'
#!/usr/bin/env bash
:
MOCK
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" XDG_CURRENT_DESKTOP=mango MANGO_INSTANCE_SIGNATURE=mock
export AWTARCHY_MOCK_AWTWALL="$tmp/awtwall.log"
helper="config/mango/scripts/wallpicker.sh"
bash -n "$helper"
bash "$helper"
grep -Fxq -- '--backend swww --resume' "$AWTARCHY_MOCK_AWTWALL"

if XDG_CURRENT_DESKTOP=Hyprland bash "$helper" >/dev/null 2>&1; then
    printf 'ERROR: Mango wallpicker acted outside Mango\n' >&2
    false
fi
[[ $(wc -l <"$AWTARCHY_MOCK_AWTWALL") == 1 ]]
python3 - <<'PY'
from pathlib import Path
cfg = Path("config/mango/config.conf").read_text()
assert cfg.count("wallpicker 'foot --app-id wallpicker bash ~/.config/mango/scripts/wallpicker.sh'") == 2
assert "awtwall --resume" not in cfg
PY
printf 'PASS: Mango AwtWall launcher selects independent backend and preserves Hyprland path\n'
