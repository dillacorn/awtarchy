#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/config/hypr/scripts/quickshell_launcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

CONFIG_HOME="$TMP/config"
BIN="$TMP/bin"
LOG="$TMP/calls.log"
COUNT="$TMP/qs-count"

mkdir -p "$CONFIG_HOME/hypr/scripts" "$BIN"

cat >"$BIN/qs" <<'EOF_QS'
#!/usr/bin/env bash
set -euo pipefail

count=0
if [[ -r "${AWTARCHY_TEST_QS_COUNT:?}" ]]; then
    read -r count <"${AWTARCHY_TEST_QS_COUNT}"
fi
count=$((count + 1))
printf '%s\n' "$count" >"${AWTARCHY_TEST_QS_COUNT}"

{
    printf 'qs'
    printf ' %s' "$@"
    printf '\n'
} >>"${AWTARCHY_TEST_LOG:?}"

if [[ ${AWTARCHY_TEST_QS_FAIL_FIRST:-0} == 1 && $count -eq 1 ]]; then
    exit 1
fi
EOF_QS

cat >"$CONFIG_HOME/hypr/scripts/quickshell_runtime_rules.sh" <<'EOF_RULES'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'runtime-rules' >>"${AWTARCHY_TEST_LOG:?}"
EOF_RULES

cat >"$CONFIG_HOME/hypr/scripts/quickshell.sh" <<'EOF_MANAGER'
#!/usr/bin/env bash
set -euo pipefail
printf 'manager' >>"${AWTARCHY_TEST_LOG:?}"
printf ' %s' "$@" >>"${AWTARCHY_TEST_LOG:?}"
printf '\n' >>"${AWTARCHY_TEST_LOG:?}"
EOF_MANAGER

chmod 0755     "$BIN/qs"     "$CONFIG_HOME/hypr/scripts/quickshell_runtime_rules.sh"     "$CONFIG_HOME/hypr/scripts/quickshell.sh"

run_launcher() {
    env         XDG_CONFIG_HOME="$CONFIG_HOME"         PATH="$BIN:$PATH"         AWTARCHY_TEST_LOG="$LOG"         AWTARCHY_TEST_QS_COUNT="$COUNT"         "$@"         bash "$LAUNCHER"
}

bash -n "$LAUNCHER"

: >"$LOG"
rm -f -- "$COUNT"
run_launcher

mapfile -t calls <"$LOG"
[[ ${#calls[@]} -eq 1 ]]     || fail "hot path invoked ${#calls[@]} commands instead of one"
[[ ${calls[0]} == 'qs -c awtarchy ipc call launcher toggle' ]]     || fail "hot path did not call launcher IPC directly: ${calls[0]}"

: >"$LOG"
rm -f -- "$COUNT"
run_launcher AWTARCHY_TEST_QS_FAIL_FIRST=1

mapfile -t calls <"$LOG"
expected=(
    'qs -c awtarchy ipc call launcher toggle'
    'runtime-rules'
    'manager start'
    'qs -c awtarchy ipc call launcher toggle'
)

[[ ${#calls[@]} -eq ${#expected[@]} ]]     || fail "fallback invoked ${#calls[@]} commands instead of ${#expected[@]}"
for i in "${!expected[@]}"; do
    [[ ${calls[$i]} == "${expected[$i]}" ]]         || fail "fallback call $i was '${calls[$i]}', expected '${expected[$i]}'"
done

printf '%s\n' 'PASS: launcher keyboard fast path preserves cold-start recovery'
