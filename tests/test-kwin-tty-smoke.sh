#!/usr/bin/env bash
# Offline negative-path contract: refuses unsafe/non-interactive starts.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
target="$root/trials/kwin/tty-smoke.sh"
bash -n "$target"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
# CI container may be root; bypass ONLY the guard in an isolated test copy.
sed 's/\[\[ ${EUID} -ne 0 \]\]/[[ 1000 -ne 0 ]]/' "$target" > "$tmp/tty-smoke.sh"
mkdir -p "$tmp/home"
if HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" \
    bash "$tmp/tty-smoke.sh" >"$tmp/out" 2>&1; then
    printf 'ERROR: accepted no-opt-in invocation\n' >&2
    false
fi
grep -Fq 'Explicit opt-in required' "$tmp/out"
if HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" \
    AWTARCHY_KWIN_SMOKE=yes bash "$tmp/tty-smoke.sh" >"$tmp/out" 2>&1; then
    printf 'ERROR: accepted non-TTY invocation\n' >&2
    false
fi
grep -Fq 'Use an interactive local TTY' "$tmp/out"
if HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" XDG_SESSION_TYPE=wayland \
    WAYLAND_DISPLAY=wayland-1 AWTARCHY_KWIN_SMOKE=yes \
    bash "$tmp/tty-smoke.sh" --ly >"$tmp/out" 2>&1; then
    printf 'ERROR: Ly mode accepted a nested display\n' >&2
    false
fi
grep -Fq 'Existing graphical display detected' "$tmp/out"
if HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" XDG_SESSION_TYPE=tty \
    AWTARCHY_KWIN_SMOKE=yes \
    bash "$tmp/tty-smoke.sh" --ly >"$tmp/out" 2>&1; then
    printf 'ERROR: Ly mode accepted a plain TTY\n' >&2
    false
fi
grep -Fq 'Ly mode expects one Wayland login session' "$tmp/out"
[[ ! -e "$tmp/state" ]]
printf 'PASS: KWin smoke rejects non-TTY, missing opt-in and nested Ly starts\n'
