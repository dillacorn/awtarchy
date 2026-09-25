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

grep -Fq 'local scratchpad_toggle_window = "~/.config/hypr/scripts/scratchpad_toggle_window.sh"' "$HYPR" \
  || fail 'Hyprland config does not define the scratchpad toggle helper'
grep -Fq 'hl.bind("SUPER + CTRL + X", hl.dsp.exec_cmd(scratchpad_toggle_window), {})' "$HYPR" \
  || fail 'SUPER+CTRL+X is not bound to the scratchpad toggle helper'

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"

cat >"$tmp/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  -j:activewindow)
    if [[ "${MOCK_MODE:-}" == "restore" ]]; then
      printf '%s\n' '{"address":"0xabc","pid":4242,"workspace":{"id":-99,"name":"special:magic"}}'
    else
      printf '%s\n' '{"address":"0xabc","pid":4242,"workspace":{"id":3,"name":"3"}}'
    fi
    ;;
  -j:monitors)
    printf '%s\n' '[{"focused":true,"activeWorkspace":{"id":7}}]'
    ;;
  dispatch:movetoworkspace)
    printf '%s\n' "${3:-}" >>"${MOCK_LOG:?}"
    ;;
  *)
    printf 'unexpected hyprctl call: %s\n' "$*" >&2
    exit 1
    ;;
esac
MOCK
chmod +x "$tmp/bin/hyprctl"

MOCK_LOG="$tmp/dispatch.log" \
MOCK_MODE=send \
XDG_RUNTIME_DIR="$tmp/runtime" \
PATH="$tmp/bin:$PATH" \
  "$SCRIPT"

[[ "$(sed -n '1p' "$tmp/dispatch.log")" == "special:magic" ]] \
  || fail 'sending a window does not move it to special:magic'

state_file="$tmp/runtime/awtarchy/scratchpad/0xabc.state"
[[ -f "$state_file" ]] || fail 'sending a window does not retain its previous workspace'
[[ "$(cat "$state_file")" == $'4242\t3' ]] \
  || fail 'scratchpad state does not retain the original workspace for the active window'

MOCK_LOG="$tmp/dispatch.log" \
MOCK_MODE=restore \
XDG_RUNTIME_DIR="$tmp/runtime" \
PATH="$tmp/bin:$PATH" \
  "$SCRIPT"

[[ "$(sed -n '2p' "$tmp/dispatch.log")" == "3" ]] \
  || fail 'restoring a scratchpad window does not return to its recorded workspace'
[[ ! -e "$state_file" ]] || fail 'restored scratchpad state was not cleared'

printf '%s\n' 'PASS: SUPER+CTRL+X scratchpad helper sends and restores the active window to its prior workspace.'
