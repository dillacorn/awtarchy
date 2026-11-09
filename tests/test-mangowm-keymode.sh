#!/usr/bin/env bash
# Runtime contracts for Mango key modes. No real compositor or user state.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p -- "$tmp/bin" "$tmp/state/awtarchy"
printf 'default\n' >"$tmp/current"
cat >"$tmp/bin/mmsg" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    'get keymode')
        jq -nc --arg keymode "$(cat "$AWTARCHY_TEST_MODE_FILE")" '{keymode:$keymode}'
        ;;
    'dispatch setkeymode,'*)
        printf '%s\n' "$*" >>"$AWTARCHY_TEST_IPC_LOG"
        printf '%s\n' "${2#setkeymode,}" >"$AWTARCHY_TEST_MODE_FILE"
        ;;
    *) printf 'Unexpected Mango IPC: %s\n' "$*" >&2; false ;;
esac
MOCK
chmod +x "$tmp/bin/mmsg"
export PATH="$tmp/bin:$PATH" XDG_STATE_HOME="$tmp/state"
export MANGO_INSTANCE_SIGNATURE=mock-session WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=mango
export AWTARCHY_TEST_MODE_FILE="$tmp/current" AWTARCHY_TEST_IPC_LOG="$tmp/ipc"
script="config/mango/scripts/keymode.sh"
bash -n "$script"

# First Mango login borrows only the selected Hyprland submap. The original
# state must remain untouched across every Mango action.
printf 'vm\n' >"$tmp/state/awtarchy/hypr-submap"
bash "$script" restore
[[ "$(cat "$tmp/current")" == vm ]]
[[ "$(cat "$tmp/state/awtarchy/hypr-submap")" == vm ]]
[[ "$(cat "$tmp/state/awtarchy/mango-keymode")" == vm ]]
[[ "$(bash "$script" current)" == vm ]]
bash "$script" toggle noalt
[[ "$(cat "$tmp/current")" == noalt ]]
bash "$script" toggle noalt
[[ "$(cat "$tmp/current")" == default ]]
bash "$script" set mouse
[[ "$(cat "$tmp/current")" == mouse ]]
bash "$script" restore
[[ "$(cat "$tmp/current")" == mouse ]]

# Neither malformed modes nor a non-Mango environment may issue IPC.
before="$(wc -l <"$AWTARCHY_TEST_IPC_LOG")"
for mode in "" evil unsupported; do
    if bash "$script" set "$mode" >/dev/null 2>&1; then
        printf 'ERROR: invalid Mango mode accepted: %s\n' "$mode" >&2
        false
    fi
done
if XDG_CURRENT_DESKTOP=Hyprland bash "$script" set vm >/dev/null 2>&1; then
    printf 'ERROR: Mango mode helper acted inside a Hyprland session\n' >&2
    false
fi
[[ "$(wc -l <"$AWTARCHY_TEST_IPC_LOG")" == "$before" ]]
[[ "$(cat "$tmp/state/awtarchy/hypr-submap")" == vm ]]

# No alternate state directory or linked path may be silently overwritten.
mv -- "$tmp/state/awtarchy/mango-keymode" "$tmp/saved-mode"
ln -s -- "$tmp/saved-mode" "$tmp/state/awtarchy/mango-keymode"
if bash "$script" set default >/dev/null 2>&1; then
    printf 'ERROR: linked Mango state path was accepted\n' >&2
    false
fi
[[ "$(cat "$tmp/saved-mode")" == mouse ]]
printf 'PASS: Mango key modes, persistence, Hyprland isolation, invalid-session refusal\n'
