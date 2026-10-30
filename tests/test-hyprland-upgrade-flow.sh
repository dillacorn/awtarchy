#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RECONCILER="$ROOT/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
bash -n "$RECONCILER"
command -v script >/dev/null 2>&1 || fail "util-linux script is required for PTY isolation"

# Extract the production upgrade branch, never source the full package manager.
python3 - "$RECONCILER" "$TMP/upgrade.sh" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index('if (( HYPRLAND_UPGRADE_ONLY == 1 )); then')
end = source.index('\nif (( NVIDIA_ROLLBACK_ONLY == 1 )); then', start)
branch = source[start:end]
header = """#!/usr/bin/env bash
set -Eeuo pipefail
HYPRLAND_UPGRADE_ONLY=1
NVIDIA_ROLLBACK_ONLY=0
REVIEW_ONLY=0
NEEDS_ACTION_ONLY=0
MIGRATE_REPLACEMENTS_ONLY=0
MIGRATE_LOCKSCREEN_RETIREMENT_ONLY=0
PACMAN_RECOVERY_CHECK_ONLY=0
PACMAN_RECOVERY_RUN_ONLY=0
PACMAN_MIRROR_CHECK_ONLY=0
PACMAN_MIRROR_REPORT_ONLY=0
PACMAN_MIRROR_REPAIR_ONLY=0
NVIDIA_ROLLBACK_PENDING=previous
log() { printf 'LOG:%s\\n' "$*"; }
warn() { printf 'WARN:%s\\n' "$*"; }
die() { printf 'ERROR:%s\\n' "$*"; exit 11; }
pacman() {
  [[ "$1" == -Qq && "$2" == hyprland ]] || die "unexpected pacman: $*"
  [[ "${SCENARIO:-success}" != absent ]]
}
recover_package_disk_headroom() { printf '%s\\n' DISK; }
confirm_nvidia_system_upgrade() {
  printf '%s\\n' CONFIRM
  [[ "${SCENARIO:-success}" != declined ]]
}
pacman_install_with_recovery() {
  [[ "$*" == '-Syu --noconfirm' ]] || die "partial upgrade: $*"
  printf '%s\\n' TRANSACTION
  [[ "${SCENARIO:-success}" != failed ]]
}
cleanup_nvidia_pending_snapshot() { printf '%s\\n' CLEANUP; }
offer_nvidia_post_upgrade_choice() {
  printf '%s\\n' POST
  [[ "${SCENARIO:-success}" != rollback ]] || return 20
}
"""
Path(sys.argv[2]).write_text(header + branch + "\n", encoding="utf-8")
PY

bash -n "$TMP/upgrade.sh"
for scenario in success declined failed rollback absent; do
  status=0
  SCENARIO="$scenario" script -q -e -c "bash $TMP/upgrade.sh" /dev/null \
    >"$TMP/out-$scenario" 2>&1 || status=$?
  result="$(<"$TMP/out-$scenario")"
  case "$scenario" in
    success)
      (( status == 0 )) || fail "success status was $status"
      [[ $result == *DISK* && $result == *CONFIRM* &&
         $result == *TRANSACTION* && $result == *POST* ]] ||
        fail "missing a full-upgrade safeguard"
      ;;
    declined)
      (( status == 1 )) || fail "confirmation refusal status was $status"
      [[ $result == *CONFIRM* && $result != *TRANSACTION* ]] ||
        fail "refused confirmation still started pacman"
      ;;
    failed)
      (( status == 11 )) || fail "failed pacman status was $status"
      [[ $result == *TRANSACTION* && $result == *CLEANUP* && $result != *POST* ]] ||
        fail "failed pacman did not clean up"
      ;;
    rollback)
      (( status == 20 )) || fail "NVIDIA rollback status was $status"
      [[ $result == *TRANSACTION* && $result == *POST* ]] ||
        fail "missing NVIDIA recovery stage"
      ;;
    absent)
      (( status == 11 )) || fail "missing Hyprland status was $status"
      [[ $result != *TRANSACTION* ]] ||
        fail "missing compositor still ran pacman"
      ;;
  esac
done

printf '%s\n' 'PASS: isolated production Hyprland upgrade branch and failure paths.'
