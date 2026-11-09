#!/usr/bin/env bash
# Refuse wrong sessions, revisions, state, and unsafe checkouts before restore.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p -- "$tmp/bin" "$tmp/state/awtarchy"

cat >"$tmp/bin/id" <<'MOCK'
#!/usr/bin/bash
if [[ "${1:-}" == -u ]]; then printf '1000\n'; else /usr/bin/id "$@"; fi
MOCK
cat >"$tmp/bin/hyprctl" <<'MOCK'
#!/usr/bin/bash
[[ "$*" == '-j version' ]] || /usr/bin/false
printf '{"tag":"v1.0.0"}\n'
MOCK
cat >"$tmp/bin/git" <<'MOCK'
#!/usr/bin/bash
case "$*" in
    *'rev-parse --show-toplevel') printf '%s\n' "$AWTARCHY_TEST_ROOT" ;;
    *'remote get-url origin') printf '%s\n' "${AWTARCHY_TEST_REMOTE:-https://github.com/dillacorn/awtarchy.git}" ;;
    *'rev-parse HEAD') printf '%s\n' "${AWTARCHY_TEST_HEAD:-$AWTARCHY_TEST_SHA}" ;;
    *'status --porcelain --untracked-files=all') printf '%s' "${AWTARCHY_TEST_DIRTY:-}" ;;
    *) printf 'Unexpected git operation: %s\n' "$*" >&2; /usr/bin/false ;;
esac
MOCK
cat >"$tmp/bin/bash" <<'MOCK'
#!/usr/bin/bash
if [[ "${1:-}" == -n ]]; then
    /usr/bin/bash "$@"
else
    printf '%s\n' "$*" >>"$AWTARCHY_TEST_CALLS"
fi
MOCK
chmod +x "$tmp/bin/"*

export PATH="$tmp/bin:$PATH"
export AWTARCHY_TEST_ROOT="$PWD"
export AWTARCHY_TEST_SHA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
export AWTARCHY_TEST_CALLS="$tmp/calls"
export XDG_STATE_HOME="$tmp/state"
export HYPRLAND_INSTANCE_SIGNATURE=live-hyprland
export WAYLAND_DISPLAY=wayland-1
unset MANGO_INSTANCE_SIGNATURE || true

printf 'branch=MangoWM_Migration_Trial_Investigation\nrevision=%s\nstable_release=v4.1.5\n' \
    "$AWTARCHY_TEST_SHA" >"$tmp/state/awtarchy/git-testing"
printf 'tag=MangoWM_Migration_Trial_Investigation@%s\n' \
    "$AWTARCHY_TEST_SHA" >"$tmp/state/awtarchy/config-version"

/usr/bin/bash trials/mangowm/restore-stable.sh --review >/dev/null
grep -Fxq "$PWD/local/share/awtarchy/awtarchy-runtime.sh update-reset-backup --tag v4.1.5 --mode preserve --review-only" "$AWTARCHY_TEST_CALLS" || {
    printf 'FAIL: did not select recorded stable release and exact trial runtime\n' >&2
    false
}

refuse() {
    : >"$AWTARCHY_TEST_CALLS"
    if /usr/bin/bash trials/mangowm/restore-stable.sh "$1" >/dev/null 2>&1; then
        printf 'FAIL: restore accepted an unsafe %s invocation\n' "$1" >&2
        return 1
    fi
    [[ ! -s "$AWTARCHY_TEST_CALLS" ]]
}

MANGO_INSTANCE_SIGNATURE=active refuse --review
AWTARCHY_TEST_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb refuse --review
AWTARCHY_TEST_DIRTY=' M config/mango/config.conf' refuse --review
AWTARCHY_TEST_REMOTE=https://github.com/attacker/awtarchy.git refuse --review
printf 'stable_release=main\n' >>"$tmp/state/awtarchy/git-testing"
refuse --review
sed -i '$d' "$tmp/state/awtarchy/git-testing"
printf 'revision=cccccccccccccccccccccccccccccccccccccccc\n' >>"$tmp/state/awtarchy/git-testing"
refuse --review
sed -i '$d' "$tmp/state/awtarchy/git-testing"
refuse --restore  # CI must not apply a restore without an interactive terminal.

printf 'PASS: Mango stable recovery pins recorded release and rejects unsafe session/state/checkout\n'
