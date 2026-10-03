#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INHIBITOR="$ROOT/config/hypr/scripts/idle_inhibitor_global.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap '[[ ! -s "$TMP/inhibitor.pid" ]] || kill "$(<"$TMP/inhibitor.pid")" 2>/dev/null || true; rm -rf -- "$TMP"' EXIT
home="$TMP/home"
state_home="$TMP/state"
fake="$TMP/systemd-inhibit"
inhibitor_state="$TMP/inhibitor.pid"
mkdir -p "$home" "$state_home"

cat >"$fake" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${AWTARCHY_IDLE_TEST_INHIBITOR_STATE:?}"
if [[ ${1:-} == --list ]]; then
  if [[ -s "$state" ]]; then
    pid="$(<"$state")"
    if kill -0 "$pid" 2>/dev/null; then
      printf 'awtarchy test test %s idle Awtarchy global idle inhibitor block\n' "$pid"
    fi
  fi
  exit 0
fi
printf '%s\n' "$$" >"$state"
cleanup() { rm -f -- "$state"; }
trap 'cleanup; exit 0' TERM INT HUP
trap cleanup EXIT
while :; do /bin/sleep 1; done
EOF
chmod 0755 "$fake"

run_idle() {
  local runtime="$1"
  shift
  mkdir -p "$runtime"
  HOME="$home" \
  XDG_RUNTIME_DIR="$runtime" \
  XDG_STATE_HOME="$state_home" \
  AWTARCHY_IDLE_STATE_DIR="$state_home/awtarchy" \
  AWTARCHY_IDLE_SYSTEMD_INHIBIT_BIN="$fake" \
  AWTARCHY_IDLE_TEST_INHIBITOR_STATE="$inhibitor_state" \
    "$INHIBITOR" "$@"
}

wait_gone() {
  local pid="$1"
  for _ in {1..50}; do kill -0 "$pid" 2>/dev/null || return 0; /bin/sleep 0.02; done
  return 1
}

run1="$TMP/run1"
run_idle "$run1" set-mode always-awake
[[ "$(run_idle "$run1" mode)" == always-awake ]] || fail "Always Awake did not activate"
run_idle "$run1" lock-always-awake
marker="$state_home/awtarchy/always-awake.locked"
grep -Fxq locked "$marker" || fail "persistent lock marker was not written"
status="$(run_idle "$run1" status)"
grep -Fq '"mode":"always-awake"' <<<"$status" || fail "status lost Always Awake mode"
grep -Fq '"persistent":true' <<<"$status" || fail "status does not expose the persistent lock"

# Simulate logout/reboot: runtime files/process disappear, persistent state survives.
pid1="$(<"$inhibitor_state")"
kill "$pid1"
wait_gone "$pid1" || fail "first inhibitor did not exit"
rm -rf -- "$run1"
run2="$TMP/run2"
[[ "$(run_idle "$run2" mode)" == always-awake ]] || fail "persistent Always Awake did not restore in a fresh runtime directory"
[[ -s "$inhibitor_state" ]] || fail "persistent restore did not reacquire an idle inhibitor"

# Unlocking keeps Always Awake active for this session but stops future restoration.
run_idle "$run2" unlock-always-awake
[[ "$(run_idle "$run2" mode)" == always-awake ]] || fail "unlocking persistence unexpectedly disabled current Always Awake"
[[ ! -e "$marker" ]] || fail "unlock did not clear persistent marker"
pid2="$(<"$inhibitor_state")"
kill "$pid2"
wait_gone "$pid2" || fail "second inhibitor did not exit"
rm -rf -- "$run2"
run3="$TMP/run3"
[[ "$(run_idle "$run3" mode)" == off ]] || fail "unlocked Always Awake restored after simulated reboot"

# Explicitly turning Always Awake off also clears persistence.
run_idle "$run3" set-mode always-awake
run_idle "$run3" lock-always-awake
run_idle "$run3" set-mode off
[[ ! -e "$marker" ]] || fail "disabling Always Awake did not clear persistence"
[[ "$(run_idle "$run3" mode)" == off ]] || fail "Always Awake did not turn off"

printf '%s\n' 'PASS: Always Awake persistence locks, restores, unlocks to session-only, and clears on disable.'
