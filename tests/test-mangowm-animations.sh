#!/usr/bin/env bash
# Synthetic Mango IPC and isolated per-session runtime; never change live WM.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"
cat >"$tmp/bin/mmsg" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWTARCHY_TEST_IPC_LOG"
MOCK
chmod +x "$tmp/bin/mmsg"
export PATH="$tmp/bin:$PATH"
export XDG_CURRENT_DESKTOP=mango MANGO_INSTANCE_SIGNATURE=mock-one
export WAYLAND_DISPLAY=wayland-test XDG_RUNTIME_DIR="$tmp/runtime"
export AWTARCHY_TEST_IPC_LOG="$tmp/ipc"
script=config/mango/scripts/animations.sh
bash -n "$script"

bash "$script"
bash "$script"
[[ "$(wc -l <"$tmp/ipc")" == 2 ]]
[[ "$(sed -n '1p' "$tmp/ipc")" == "dispatch setoption,animations,1" ]]
[[ "$(sed -n '2p' "$tmp/ipc")" == "dispatch setoption,animations,0" ]]

# Another Mango compositor instance starts from config default OFF.
MANGO_INSTANCE_SIGNATURE=mock-two bash "$script"
[[ "$(tail -n 1 "$tmp/ipc")" == "dispatch setoption,animations,1" ]]
before="$(wc -l <"$tmp/ipc")"
if XDG_CURRENT_DESKTOP=Hyprland bash "$script" >/dev/null 2>&1; then
    printf 'ERROR: Mango animations modified another compositor session\n' >&2
    false
fi
[[ "$(wc -l <"$tmp/ipc")" == "$before" ]]

# No symlink/hardlink target may be silently overwritten.
state="$tmp/runtime/awtarchy-mango-animations-$(printf mock-two | sha256sum | cut -c 1-16)"
if [[ -f "$state" ]]; then
    mv "$state" "$tmp/saved"
    ln -s "$tmp/saved" "$state"
    if MANGO_INSTANCE_SIGNATURE=mock-two bash "$script" >/dev/null 2>&1; then
        printf 'ERROR: linked animation state was accepted\n' >&2
        false
    fi
    [[ "$(wc -l <"$tmp/ipc")" == "$before" ]]
    [[ "$(cat "$tmp/saved")" == 1 ]]
else
    printf 'ERROR: expected instance-scoped animation state missing\n' >&2
    false
fi
python3 - <<'PY'
from pathlib import Path
config = Path("config/mango/config.conf").read_text()
assert config.count("bind=SUPER,A,spawn_shell,bash ~/.config/mango/scripts/animations.sh") == 2
assert "animations=0" in config
PY
printf 'PASS: Mango animation toggle, session isolation and unsafe-state refusal\n'
