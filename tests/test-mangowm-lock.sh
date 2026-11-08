#!/usr/bin/env bash
# Prove failing Mango locks cannot trigger an unsafe suspend or hibernate.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p -- "$tmp/bin"
cat >"$tmp/bin/swaylock" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWTARCHY_TEST_LOCK_LOG"
if [[ ${AWTARCHY_TEST_SWAYLOCK_FAIL:-0} == 1 ]]; then
    false
fi
MOCK
cat >"$tmp/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWTARCHY_TEST_POWER_LOG"
MOCK
cat >"$tmp/bin/loginctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "loginctl $*" >>"$AWTARCHY_TEST_POWER_LOG"
MOCK
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
export AWTARCHY_TEST_LOCK_LOG="$tmp/lock.log"
export AWTARCHY_TEST_POWER_LOG="$tmp/power.log"
target="config/mango/scripts/lock.sh"

bash -n "$target"
bash "$target" lock
grep -Fxq -- '-f -c 10151c' "$AWTARCHY_TEST_LOCK_LOG"
[[ ! -e "$AWTARCHY_TEST_POWER_LOG" ]]

if AWTARCHY_TEST_SWAYLOCK_FAIL=1 bash "$target" suspend; then
    printf 'ERROR: unsafe Mango suspend despite failed lock\n' >&2
    false
fi
[[ ! -e "$AWTARCHY_TEST_POWER_LOG" ]]

bash "$target" suspend
grep -Fxq 'suspend -i' "$AWTARCHY_TEST_POWER_LOG"
bash "$target" hibernate
grep -Fxq 'hibernate' "$AWTARCHY_TEST_POWER_LOG"

if bash "$target" wait-secure 5 >/dev/null 2>&1; then
    printf 'ERROR: unverified lock status was accepted\n' >&2
    false
fi
# Native Quickshell provides the same ext-session-lock proof as in Hyprland.
# The fallback must not start if the compositor may already be securing a
# pending native lock, and suspend is forbidden until readiness is confirmed.
mkdir -p -- "$tmp/config/hypr/scripts" "$tmp/config/quickshell/awtarchy-lock"
touch "$tmp/config/quickshell/awtarchy-lock/shell.qml"
cat >"$tmp/bin/qs" <<'MOCK'
#!/usr/bin/env bash
:
MOCK
cat >"$tmp/config/hypr/scripts/awtarchy_lock.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    lock)
        printf 'native-lock:%s\n' "${AWTARCHY_LOCK_NO_CAPTURE:-0}" >>"$AWTARCHY_TEST_NATIVE_LOG"
        [[ "${AWTARCHY_TEST_NATIVE_LOCK_FAIL:-0}" != 1 ]]
        ;;
    wait-secure)
        printf '%s\n' native-ready-wait >>"$AWTARCHY_TEST_NATIVE_LOG"
        [[ "${AWTARCHY_TEST_NATIVE_WAIT_FAIL:-0}" != 1 ]]
        ;;
    status)
        printf '%s\n' "${AWTARCHY_TEST_NATIVE_STATUS:-unlocked}"
        ;;
    *)
        false
        ;;
esac
MOCK
chmod +x "$tmp/bin/qs" "$tmp/config/hypr/scripts/awtarchy_lock.sh"
export XDG_CONFIG_HOME="$tmp/config"
export MANGO_INSTANCE_SIGNATURE="test-session"
export AWTARCHY_TEST_NATIVE_LOG="$tmp/native.log"
: >"$AWTARCHY_TEST_LOCK_LOG"
: >"$AWTARCHY_TEST_POWER_LOG"

bash "$target" suspend
grep -Fxq 'native-lock:1' "$AWTARCHY_TEST_NATIVE_LOG"
grep -Fxq native-ready-wait "$AWTARCHY_TEST_NATIVE_LOG"
grep -Fxq 'suspend -i' "$AWTARCHY_TEST_POWER_LOG"
[[ ! -s "$AWTARCHY_TEST_LOCK_LOG" ]]

: >"$AWTARCHY_TEST_NATIVE_LOG"
: >"$AWTARCHY_TEST_POWER_LOG"
if AWTARCHY_TEST_NATIVE_WAIT_FAIL=1 AWTARCHY_TEST_NATIVE_STATUS=starting \
        bash "$target" suspend; then
    printf 'ERROR: unsafe suspend despite uncertain native lock readiness\n' >&2
    false
fi
[[ ! -s "$AWTARCHY_TEST_POWER_LOG" ]]
[[ ! -s "$AWTARCHY_TEST_LOCK_LOG" ]]

# A native startup failure with an explicitly unlocked state permits the
# independent Swaylock fallback, which must itself still complete.
AWTARCHY_TEST_NATIVE_LOCK_FAIL=1 bash "$target" suspend
grep -Fxq -- '-f -c 10151c' "$AWTARCHY_TEST_LOCK_LOG"
grep -Fxq 'suspend -i' "$AWTARCHY_TEST_POWER_LOG"

# The Hyprland-only capture suppression must be explicitly scoped to Mango.
grep -Fq 'AWTARCHY_LOCK_NO_CAPTURE:-0' config/hypr/scripts/awtarchy_lock.sh
grep -Fq 'MANGO_INSTANCE_SIGNATURE:-' config/hypr/scripts/awtarchy_lock.sh

printf 'PASS: Mango native secure lock, independent fallback, and fail-closed suspend\n'
