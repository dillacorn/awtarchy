#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="${ROOT}/config/hypr/scripts/awtarchy-tips-tui.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$SCRIPT"

lockscreen_text="$(article_text quickshell-lockscreen)"
maccel_text="$(article_text gaming-maccel)"

grep -Fq 'SUPER+ALT+E' <<<"$lockscreen_text"     || fail 'lockscreen tips are missing the direct editor shortcut'
grep -Fq 'Edit Layout' <<<"$lockscreen_text"     || fail 'lockscreen tips are missing the full editor path'
grep -Fq 'Ctrl+S' <<<"$lockscreen_text"     || fail 'lockscreen tips are missing the save shortcut'

grep -Fq 'ALT+SHIFT+M' <<<"$maccel_text"     || fail 'maccel tips are missing the ALT shortcut'
grep -Fq 'SUPER+SHIFT+M' <<<"$maccel_text"     || fail 'maccel tips are missing the SUPER shortcut'
grep -Fq 'https://github.com/Gnarus-G/maccel' <<<"$maccel_text"     || fail 'maccel tips are missing the upstream documentation link'

grep -Fq '"Lockscreen"' "$SCRIPT"     || fail 'Quickshell menu is missing the Lockscreen article'
grep -Fq 'quickshell-lockscreen' "$SCRIPT"     || fail 'Quickshell menu is missing the Lockscreen article id'
grep -Fq '"maccel Mouse Acceleration"' "$SCRIPT"     || fail 'Gaming menu is missing the maccel article'
grep -Fq 'gaming-maccel' "$SCRIPT"     || fail 'Gaming menu is missing the maccel article id'

printf 'PASS: Awtarchy Tips lockscreen and maccel content\n'
