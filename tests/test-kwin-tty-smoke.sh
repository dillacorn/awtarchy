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
# The actual Arch /usr/bin/python3 is a link to a versioned binary.
# Verify regular binaries and linked binaries both pass, while broken
# links and non-executables fail closed.
source <(sed -n '/^valid_system_executable() {/,/^}/p' "$target")
printf '#!/usr/bin/env bash\ntrue\n' > "$tmp/real"
chmod 0755 "$tmp/real"
ln -s -- real "$tmp/linked"
ln -s -- does-not-exist "$tmp/broken"
printf '#!/usr/bin/env bash\ntrue\n' > "$tmp/nonexec"
chmod 0644 "$tmp/nonexec"
valid_system_executable "$tmp/real"
valid_system_executable "$tmp/linked"
if valid_system_executable "$tmp/broken"; then
    printf 'ERROR: accepted broken executable link\n' >&2; false
fi
if valid_system_executable "$tmp/nonexec"; then
    printf 'ERROR: accepted non-executable file\n' >&2; false
fi
if valid_system_executable "$tmp"; then
    printf 'ERROR: accepted a directory as an executable\n' >&2; false
fi
printf 'PASS: KWin guard allows official binary symlinks and refuses unsafe targets\n'
# A premature startup failure must not produce an unbound-variable error.
# The global cleanup trap must reap only the exact process launched here,
# even after the invoking main() function's local scope disappears.
sed -n '/^stop_bridge() {/,/^}/p' "$target" > "$tmp/stop-bridge.sh"
[[ -s "$tmp/stop-bridge.sh" ]]
if (
    set -euo pipefail
    source "$tmp/stop-bridge.sh"
    bridge_pid=''
    trap stop_bridge EXIT
    false
); then
    printf 'ERROR: expected simulated startup failure\n' >&2
    false
fi
(
    set -euo pipefail
    source "$tmp/stop-bridge.sh"
    bridge_pid=''
    trap stop_bridge EXIT
    sleep 20 &
    bridge_pid=$!
    printf '%s\n' "$bridge_pid" > "$tmp/bridge.pid"
)
child_pid="$(< "$tmp/bridge.pid")"
if kill -0 "$child_pid" 2>/dev/null; then
    printf 'ERROR: orphaned KWin test bridge PID %s\n' "$child_pid" >&2
    kill -TERM "$child_pid" 2>/dev/null || :
    false
fi
grep -Fq 'export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"' "$target"
printf 'PASS: KWin bridge cleanup survives main scope and reaps its child\n'
printf 'PASS: KWin smoke rejects non-TTY, missing opt-in and nested Ly starts\n'
