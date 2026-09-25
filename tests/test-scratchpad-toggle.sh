#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/config/hypr/scripts/scratchpad_toggle_window.sh"
HYPR="${ROOT}/config/hypr/hyprland.lua"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$SCRIPT"

grep -Fq 'hide_special_on_workspace_change = true' "$HYPR" \
  || fail 'normal workspace changes do not hide the visible special workspace'
grep -Fq 'hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd(scratchpad_toggle_window), {})' "$HYPR" \
  || fail 'SUPER+CTRL+X is not bound to the scratchpad helper'
grep -Fq 'scratchpad_toggle_window .. " move-to " .. workspace' "$HYPR" \
  || fail 'normal numbered move binds are not scratchpad-aware'
grep -Fq 'scratchpad_toggle_window .. " move-to " .. bind[2]' "$HYPR" \
  || fail 'submap numbered move binds are not scratchpad-aware'

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"

cat >"$tmp/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  -j:activewindow)
    case "${MOCK_MODE:-}" in
      restore|move-last|move-remaining)
        printf '%s\n' '{"address":"0xabc","pid":4242,"workspace":{"id":-99,"name":"special:magic"},"floating":true,"at":[100,200],"size":[800,600]}'
        ;;
      *)
        printf '%s\n' '{"address":"0xabc","pid":4242,"workspace":{"id":3,"name":"3"},"floating":true,"at":[111,222],"size":[900,700]}'
        ;;
    esac
    ;;
  -j:monitors)
    printf '%s\n' '[{"focused":true,"activeWorkspace":{"id":7},"specialWorkspace":{"id":-99,"name":"special:magic"}}]'
    ;;
  -j:clients)
    if [[ "${MOCK_MODE:-}" == "move-remaining" ]]; then
      printf '%s\n' '[{"address":"0xdef","workspace":{"id":-99,"name":"special:magic"}}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  dispatch:*)
    printf '%s\t%s\n' "${2:-}" "${3:-}" >>"${MOCK_LOG:?}"
    ;;
  *)
    printf 'unexpected hyprctl call: %s\n' "$*" >&2
    exit 1
    ;;
esac
MOCK
chmod +x "$tmp/bin/hyprctl"

MOCK_LOG="$tmp/dispatch.log" MOCK_MODE=send XDG_RUNTIME_DIR="$tmp/runtime" PATH="$tmp/bin:$PATH" "$SCRIPT"

grep -Fq $'movetoworkspace\tspecial:magic,address:0xabc' "$tmp/dispatch.log" \
  || fail 'sending a window does not move it to special:magic'
state_file="$tmp/runtime/awtarchy/scratchpad/0xabc.state"
[[ "$(cat "$state_file")" == $'v2\t4242\t3\ttrue\t111\t222\t900\t700' ]] \
  || fail 'scratchpad state does not retain workspace and floating geometry'

MOCK_LOG="$tmp/dispatch.log" MOCK_MODE=restore XDG_RUNTIME_DIR="$tmp/runtime" PATH="$tmp/bin:$PATH" "$SCRIPT"

grep -Fq $'movetoworkspacesilent\t3,address:0xabc' "$tmp/dispatch.log" \
  || fail 'restore does not target the recorded workspace'
grep -Fq $'resizewindowpixel\texact 900 700,address:0xabc' "$tmp/dispatch.log" \
  || fail 'restore does not restore floating size'
grep -Fq $'movewindowpixel\texact 111 222,address:0xabc' "$tmp/dispatch.log" \
  || fail 'restore does not restore floating position'
grep -Fq $'workspace\t3' "$tmp/dispatch.log" \
  || fail 'restore does not follow the app back to its previous workspace'
grep -Fq $'focuswindow\taddress:0xabc' "$tmp/dispatch.log" \
  || fail 'restore does not refocus the restored app'
[[ ! -e "$state_file" ]] || fail 'restored scratchpad state was not cleared'

printf '%s\n' $'v2\t4242\t3\ttrue\t111\t222\t900\t700' >"$state_file"
: >"$tmp/dispatch.log"
MOCK_LOG="$tmp/dispatch.log" MOCK_MODE=move-last XDG_RUNTIME_DIR="$tmp/runtime" PATH="$tmp/bin:$PATH" "$SCRIPT" move-to 4

grep -Fq $'movetoworkspacesilent\t4,address:0xabc' "$tmp/dispatch.log" \
  || fail 'numbered move does not target requested workspace'
grep -Fq $'togglespecialworkspace\tmagic' "$tmp/dispatch.log" \
  || fail 'moving the final scratchpad app does not close the empty scratchpad'
[[ ! -e "$state_file" ]] || fail 'explicit numbered move did not clear stale origin state'

: >"$tmp/dispatch.log"
MOCK_LOG="$tmp/dispatch.log" MOCK_MODE=move-remaining XDG_RUNTIME_DIR="$tmp/runtime" PATH="$tmp/bin:$PATH" "$SCRIPT" move-to 5
if grep -Fq $'togglespecialworkspace\tmagic' "$tmp/dispatch.log"; then
  fail 'scratchpad closed even though another app remained'
fi

printf '%s\n' 'PASS: scratchpad remembers origin geometry and closes only when an explicit move empties it.'
