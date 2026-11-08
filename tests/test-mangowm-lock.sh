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
printf 'PASS: Mango secure-lock before power transitions and fail-closed fallback\n'
