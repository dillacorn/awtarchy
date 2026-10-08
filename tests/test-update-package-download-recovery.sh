#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ ! -s "${TMP}/output" ]] || cat -- "${TMP}/output" >&2
  return 1
}

bash -n "$RUNTIME"

# Load the real production helper, but never run pacman or sudo on the host.
source <(sed -n '/^update_pacman_install_with_404_recovery() {/,/^}$/p' "$RUNTIME")
declare -F update_pacman_install_with_404_recovery >/dev/null \
  || fail "update pacman 404 recovery helper not found"

log() { printf 'LOG: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

fake_pacman() {
  printf '%s\n' "$*" >>"${TMP}/calls"

  case "${1:-}" in
    -S)
      local n=0
      [[ ! -f "${TMP}/installs" ]] || n="$(<"${TMP}/installs")"
      n=$((n + 1))
      printf '%s\n' "$n" >"${TMP}/installs"

      case "$SCENARIO" in
        success) return 0 ;;
        non404)
          printf 'error: failed to commit transaction (conflicting files)\n' >&2
          return 1
          ;;
        dns)
          printf 'error: could not resolve host: mirror.example.org\n' >&2
          return 1
          ;;
        404|upgrade-fails|retry-fails|already-tried)
          if (( n == 1 )) || [[ $SCENARIO == retry-fails ]]; then
            printf "error: failed retrieving file '7zip-old.pkg.tar.zst': The requested URL returned error: 404\n" >&2
            return 1
          fi
          return 0
          ;;
      esac
      ;;
    -Syyu)
      if [[ "$SCENARIO" == upgrade-fails ]]; then
        printf 'error: full upgrade failed\n' >&2
        return 1
      fi
      return 0
      ;;
  esac
  printf 'Unexpected pacman arguments: %s\n' "$*" >&2
  return 2
}

run_update_root() {
  [[ "$1" == "/usr/bin/pacman" ]] || fail "unexpected pacman path: $1"
  shift
  fake_pacman "$@"
}

run_quickshell_update_pacman() { fake_pacman "$@"; }

check_case() {
  local scenario="$1" mode="$2" expected_rc="$3" expected_calls="$4"
  local rc=0
  shift 4

  SCENARIO="$scenario"
  AWTARCHY_PACMAN_404_RECOVERY_ATTEMPTED=0
  : >"${TMP}/calls"
  rm -f -- "${TMP}/installs"
  if update_pacman_install_with_404_recovery "$mode" "$@" >"${TMP}/output" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  [[ "$rc" -eq "$expected_rc" ]] \
    || fail "$scenario/$mode expected exit $expected_rc, got $rc"
  diff -u <(printf '%s' "$expected_calls") "${TMP}/calls" \
    || fail "$scenario/$mode made unexpected pacman calls"
  if grep -Eq '^-Sy( |$)' "${TMP}/calls"; then
    fail "$scenario/$mode performed an unsafe partial repository refresh"
  fi
}

check_case success root 0 \
  $'-S --needed --noconfirm 7zip\n' /usr/bin/pacman 7zip
[[ $AWTARCHY_PACMAN_404_RECOVERY_ATTEMPTED == 0 ]] \
  || fail "clean install incorrectly triggered recovery"

check_case 404 root 0 \
  $'-S --needed --noconfirm 7zip\n-Syyu --noconfirm\n-S --needed --noconfirm 7zip\n' \
  /usr/bin/pacman 7zip
[[ $AWTARCHY_PACMAN_404_RECOVERY_ATTEMPTED == 1 ]] \
  || fail "HTTP 404 recovery was not recorded"
grep -Fq 'full system upgrade' "${TMP}/output" \
  || fail "recovery did not describe the full-system upgrade"

check_case non404 root 1 \
  $'-S --needed --noconfirm 7zip\n' /usr/bin/pacman 7zip

check_case dns root 1 \
  $'-S --needed --noconfirm 7zip\n' /usr/bin/pacman 7zip

check_case upgrade-fails root 1 \
  $'-S --needed --noconfirm 7zip\n-Syyu --noconfirm\n' \
  /usr/bin/pacman 7zip

check_case retry-fails root 1 \
  $'-S --needed --noconfirm 7zip\n-Syyu --noconfirm\n-S --needed --noconfirm 7zip\n' \
  /usr/bin/pacman 7zip

# A second stale-mirror error during the same update must not cause another
# unattended full-system upgrade.
check_case already-tried root 1 \
  $'-S --needed --noconfirm 7zip\n' /usr/bin/pacman 7zip
# The check_case reset is deliberate: this test represents a previous attempt.
# Re-run explicitly with the global recovery guard set.
AWTARCHY_PACMAN_404_RECOVERY_ATTEMPTED=1
: >"${TMP}/calls"
rm -f -- "${TMP}/installs"
if update_pacman_install_with_404_recovery root /usr/bin/pacman 7zip \
    >"${TMP}/output" 2>&1; then
  fail "previously attempted recovery should reject a second HTTP 404"
fi
diff -u <(printf '%s\n' '-S --needed --noconfirm 7zip') "${TMP}/calls" \
  || fail "previously attempted recovery repeated the full system upgrade"

check_case 404 quickshell 0 \
  $'-S --needed --noconfirm quickshell upower\n-Syyu --noconfirm\n-S --needed --noconfirm quickshell upower\n' \
  quickshell upower

printf '%s\n' 'PASS: updater automatically repairs HTTP 404 via full pacman sync/upgrade and retries once; other failures remain fatal.'
