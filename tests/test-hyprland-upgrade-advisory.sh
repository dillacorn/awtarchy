#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="$ROOT/local/share/awtarchy/awtarchy-package-reconcile.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
bash -n "$RUNTIME"
bash -n "$RECONCILER"

# Load exactly the production functions, without sourcing the live updater.
for name in hyprland_pending_upgrade hyprland_installed_version \
  maybe_upgrade_hyprland_before_config hyprland_running_version \
  hyprland_session_needs_restart warn_hyprland_session_restart; do
  sed -n "/^${name}() {/,/^}/p" "$RUNTIME" >>"$TMP/helpers.sh"
done
# shellcheck source=/dev/null
source "$TMP/helpers.sh"

PACKAGE_VERSION=0.56.0-1
SESSION_VERSION=0.56.0
CHECK_STATUS=update
CACHED_UPGRADE=1
ABSENT=0
CHOICE=n
UPGRADE_RC=0
UPGRADE_CALLS=0
HYPRLAND_INSTANCE_SIGNATURE=test-hyprland-instance

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 8; }
ask_optional_yes_no() { [[ $CHOICE == y ]]; }

pacman() {
  case "$1" in
    -Q|-Qq)
      [[ "$2" == hyprland && "$ABSENT" == 0 ]] || return 1
      if [[ "$1" == -Q ]]; then
        printf 'hyprland %s\n' "$PACKAGE_VERSION"
      else
        printf 'hyprland\n'
      fi
      ;;
    -Qu)
      [[ "$2" == hyprland ]] || fail "unexpected upgrade lookup"
      (( CACHED_UPGRADE == 1 )) || return 1
      printf 'hyprland %s -> 0.57.0-1\n' "$PACKAGE_VERSION"
      ;;
    *) fail "unexpected pacman call: $*" ;;
  esac
}
checkupdates() {
  case "$CHECK_STATUS" in
    update) printf 'hyprland %s -> 0.57.0-1\n' "$PACKAGE_VERSION" ;;
    none) return 2 ;;
    fail) return 1 ;;
    *) fail "invalid check status" ;;
  esac
}
hyprctl() {
  [[ "$1" == -j && "$2" == version ]] || fail "unexpected hyprctl call"
  printf '{"tag":"v%s"}\n' "$SESSION_VERSION"
}

# Mock only this subprocess. The production reconciler is checked statically
# below and CI never invokes real pacman, sudo, or a package transaction.
bash() {
  if [[ "$1" == -n ]]; then
    return 0
  fi
  [[ "$1" == "$HOME_DIR/.local/share/awtarchy/awtarchy-package-reconcile.sh" ]] ||
    fail "unexpected executable: $1"
  [[ "$2" == --hyprland-upgrade ]] || fail "unexpected reconciler mode"
  UPGRADE_CALLS=$((UPGRADE_CALLS + 1))
  (( UPGRADE_RC == 0 )) || return "$UPGRADE_RC"
  PACKAGE_VERSION=0.57.0-1
}

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.local/share/awtarchy"
touch "$HOME_DIR/.local/share/awtarchy/awtarchy-package-reconcile.sh"
mkdir -p "$TMP/repo/local/share/awtarchy"
touch "$TMP/repo/local/share/awtarchy/awtarchy-package-reconcile.sh"
found="$(hyprland_pending_upgrade)" || fail "fresh check missed pending Hyprland"
[[ $found == 'hyprland 0.56.0-1 -> 0.57.0-1' ]] || fail "unexpected fresh check result"
[[ "$(hyprland_installed_version)" == 0.56.0-1 ]] || fail "installed package parse broke under runtime IFS"

CHECK_STATUS=none
if hyprland_pending_upgrade >/dev/null; then
  fail "checkupdates returned no upgrades but stale local cache triggered an upgrade"
fi

CHECK_STATUS=fail
found="$(hyprland_pending_upgrade 2>/dev/null)" || fail "failed fresh check did not fall back"
[[ $found == 'hyprland 0.56.0-1 -> 0.57.0-1' ]] || fail "cached fallback did not match"
CHECK_STATUS=update

CHOICE=n
maybe_upgrade_hyprland_before_config "$TMP/repo" >/dev/null 2>&1
(( UPGRADE_CALLS == 0 && HYPRLAND_PACKAGE_UPGRADED == 0 )) || fail "declined upgrade ran a transaction"

CHOICE=y
maybe_upgrade_hyprland_before_config "$TMP/repo" >/dev/null 2>&1
(( UPGRADE_CALLS == 1 && HYPRLAND_PACKAGE_UPGRADED == 1 )) || fail "approved upgrade did not use reconciler"
[[ $PACKAGE_VERSION == 0.57.0-1 ]] || fail "upgrade mock did not advance installed package"

message="$(warn_hyprland_session_restart 2>&1)"
[[ $message == *"Log out of Hyprland and log back in"* ]] || fail "missing restart advisory"
HYPRLAND_PACKAGE_UPGRADED=0
[[ "$(hyprland_running_version)" == 0.56.0 ]] || fail "running compositor version parse failed"
hyprland_session_needs_restart || fail "installed/running version mismatch ignored"

SESSION_VERSION=0.57.0
if hyprland_session_needs_restart; then
  fail "matching installed/running versions incorrectly require restart"
fi
HYPRLAND_INSTANCE_SIGNATURE=""
HYPRLAND_PACKAGE_UPGRADED=1
if hyprland_session_needs_restart; then
  fail "headless update incorrectly requests a Hyprland session restart"
fi

# Approved upgrade failure must stop *before* managed config apply.
HYPRLAND_INSTANCE_SIGNATURE=test-hyprland-instance
PACKAGE_VERSION=0.56.0-1
UPGRADE_RC=7
if (maybe_upgrade_hyprland_before_config "$TMP/repo" >/dev/null 2>&1); then
  fail "failed system upgrade incorrectly allowed configuration changes"
fi
UPGRADE_RC=0
ABSENT=1
maybe_upgrade_hyprland_before_config "$TMP/repo" >/dev/null 2>&1 ||
  fail "custom Hyprland installation was treated as a forced replacement"

# Production integration and ordering guarantees.
python3 - "$RUNTIME" "$RECONCILER" <<'PY'
from pathlib import Path
import sys

runtime = Path(sys.argv[1]).read_text(encoding="utf-8")
reconciler = Path(sys.argv[2]).read_text(encoding="utf-8")

approve = runtime.index('if ! review_plan "$plan_file" update; then')
check = runtime.index('  maybe_upgrade_hyprland_before_config "$repo_dir"', approve)
apply = runtime.index('  apply_plan "$plan_file"', approve)
assert approve < check < apply, "Hyprland package update must follow review approval and precede config writes"
assert runtime.index('  warn_hyprland_session_restart\n  log "Done."') > apply
assert '  if ! validate_live; then\n    rollback_quickshell_update' in runtime
assert '    warn_hyprland_session_restart\n    die "Live validation failed.' in runtime
assert 'bash "$reconciler" --hyprland-upgrade' in runtime
assert 'local reconciler="${data_home}/awtarchy/awtarchy-package-reconcile.sh"' in runtime
mode = reconciler[reconciler.index('if (( HYPRLAND_UPGRADE_ONLY == 1 )); then'):]
stop = mode.index('\nif (( NVIDIA_ROLLBACK_ONLY == 1 )); then')
mode = mode[:stop]
for required in (
    'confirm_nvidia_system_upgrade',
    'recover_package_disk_headroom',
    'pacman_install_with_recovery -Syu --noconfirm',
    'offer_nvidia_post_upgrade_choice',
    'cleanup_nvidia_pending_snapshot',
):
    assert required in mode, f"unsafe Hyprland system upgrade: {required} missing"
assert mode.index('confirm_nvidia_system_upgrade') < mode.index('pacman_install_with_recovery -Syu')
assert '-Sy --noconfirm hyprland' not in mode, "partial upgrade is prohibited"
PY

printf '%s\n' 'PASS: Hyprland update discovery, consent, full-upgrade handoff, failure isolation, session advisory, and NVIDIA policy.'
