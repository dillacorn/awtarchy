#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"
LAUNCHER="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$RECONCILER"
bash -n "$LAUNCHER"

grep -Fq 'confirm_nvidia_system_upgrade' "$RECONCILER" \
  || fail 'package reconciler has no NVIDIA upgrade consent gate'
grep -Fq 'prepare_nvidia_rollback_snapshot' "$RECONCILER" \
  || fail 'package reconciler does not prepare NVIDIA rollback state'
grep -Fq 'offer_nvidia_post_upgrade_choice' "$RECONCILER" \
  || fail 'package reconciler does not offer post-upgrade keep/rollback choice'
grep -Fq 'awtarchy nvidia-rollback' "$LAUNCHER" \
  || fail 'launcher does not expose the NVIDIA rollback command'
grep -Fq 'NVIDIA driver recovery / rollback' "$LAUNCHER" \
  || fail 'maintenance menu does not expose NVIDIA recovery'
grep -Fq 'nvidia_recovery_menu()' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery has no submenu'
grep -Fq 'nvidia_pci_hardware_present()' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery does not detect physical NVIDIA hardware'
grep -Fq "grep -qi '\\[10de:'" "$LAUNCHER" \
  || fail 'maintenance NVIDIA hardware detection is not pinned to the NVIDIA PCI vendor ID'
grep -Fq 'No NVIDIA GPU detected' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery does not warn systems without NVIDIA hardware'
grep -Fq 'Continue to NVIDIA recovery tools' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery cannot be inspected deliberately without NVIDIA hardware'
grep -Fq 'Choose cached historical driver version' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery submenu does not expose the cached version picker'
grep -Fq 'run_current_nvidia_rollback --pick' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery submenu does not route to the cached version picker'
grep -Fq 'run_current_nvidia_rollback' "$LAUNCHER" \
  || fail 'NVIDIA rollback is not pinned to the current updater reconciler'
grep -Fq 'awtarchy nvidia-rollback [--pick | --list | --version <driver-version>]' "$LAUNCHER" \
  || fail 'launcher does not expose cached NVIDIA version selection'
# shellcheck disable=SC2016
grep -Fq 'bash "$PACKAGE_RECONCILER" --nvidia-rollback "$@"' "$LAUNCHER" \
  || fail 'launcher does not forward NVIDIA rollback options to the current reconciler'
if grep -Fq 'run_package_reconciler --nvidia-rollback' "$LAUNCHER"; then
  fail 'NVIDIA emergency rollback still follows the active Git-testing package revision'
fi
grep -Fq 'NVIDIA_ROLLBACK_ROOT="/var/lib/awtarchy"' "$RECONCILER" \
  || fail 'production NVIDIA rollback state is not rooted under /var/lib/awtarchy'
grep -Fq 'PACMAN_LOG_FILE="/var/log/pacman.log"' "$RECONCILER" \
  || fail 'historical NVIDIA rollback is not pinned to the system pacman log'
grep -Fq 'build_nvidia_history_bundle' "$RECONCILER" \
  || fail 'NVIDIA rollback has no historical package-set reconstruction'
grep -Fq 'apply_nvidia_history_version' "$RECONCILER" \
  || fail 'NVIDIA rollback has no cached historical version application path'
grep -Fq 'validate_nvidia_rollback_storage' "$RECONCILER" \
  || fail 'NVIDIA rollback does not validate privileged restore state'
# shellcheck disable=SC2016
grep -Fq 'root_owned_nonwritable_path "$NVIDIA_ROLLBACK_DIR/packages/$archive_name"' "$RECONCILER" \
  || fail 'NVIDIA rollback archives are not revalidated before pacman -U'
# shellcheck disable=SC2016
grep -Fq 'trusted_nvidia_cache_archive "$candidate"' "$RECONCILER" \
  || fail 'NVIDIA rollback snapshot accepts untrusted cache archives'
if grep -Fq 'AWTARCHY_NVIDIA_ROLLBACK_DIR' "$RECONCILER" \
  || grep -Fq 'AWTARCHY_YAY_CACHE_HOME' "$RECONCILER" \
  || grep -Fq 'AWTARCHY_KERNEL_PKGBASES' "$RECONCILER"; then
  fail 'production rollback discovery still accepts user-controlled privileged package-source overrides'
fi

# shellcheck disable=SC2016
grep -Fq 'as_root install -m 0644 -- "$metadata_tmp" "$NVIDIA_ROLLBACK_DIR/metadata"' "$RECONCILER" \
  || fail 'restored rollback status is not persisted through a privileged root-owned write'
# shellcheck disable=SC2016
if grep -Fq '>>"$NVIDIA_ROLLBACK_DIR/metadata"' "$RECONCILER"; then
  fail 'rollback metadata still has a direct user-owned append path'
fi

# shellcheck disable=SC2016
grep -Fq 'if ! as_root pacman -U --needed --noconfirm "${archives[@]}"; then' "$RECONCILER" \
  || fail 'NVIDIA rollback package transaction is not explicitly failure-checked'

python3 - "$RECONCILER" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
tx = text.find('pacman_install_with_recovery -Syu --needed --noconfirm')
if tx < 0:
    raise SystemExit('FAIL: could not locate package reconciliation full-upgrade transaction')
before = text.rfind('confirm_nvidia_system_upgrade', 0, tx)
after = text.find('offer_nvidia_post_upgrade_choice', tx)
bookkeeping = text.find('record_managed_packages "${install_arch[@]}"', tx)
rollback_stop = text.find("NVIDIA/kernel rollback completed; stopping package reconciliation", bookkeeping)
if before < 0 or after < 0 or bookkeeping < 0 or rollback_stop < 0 or not (before < tx < after < bookkeeping < rollback_stop):
    raise SystemExit(
        'FAIL: NVIDIA consent/snapshot must wrap the full system upgrade and '
        'persist rollback before managed-package bookkeeping and stop after an immediate rollback'
    )
if "apply_nvidia_rollback 1\n      return 20" not in text:
    raise SystemExit('FAIL: immediate NVIDIA rollback does not signal the caller to stop')

print('NVIDIA upgrade gate ordering OK')
PY

rollback_root="$TMP/nvidia-root"
rollback="$rollback_root/nvidia-driver-rollback"
cache="$TMP/pacman-cache"
pacman_log="$TMP/pacman.log"
test_reconciler="$TMP/awtarchy-package-reconcile.test.sh"
fakebin="$TMP/bin"
state="$TMP/pacman-state"
runtime="$TMP/runtime.sh"
mkdir -p "$rollback/packages" "$cache" "$fakebin" "$TMP/home"
: >"$runtime"

python3 - "$RECONCILER" "$test_reconciler" "$rollback_root" "$cache" "$pacman_log" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])
rollback_root = sys.argv[3]
cache = sys.argv[4]
pacman_log = sys.argv[5]

source = source.replace(
    'NVIDIA_ROLLBACK_ROOT="/var/lib/awtarchy"',
    f'NVIDIA_ROLLBACK_ROOT="{rollback_root}"',
    1,
)
source = source.replace(
    'PACMAN_CACHE_DIR="/var/cache/pacman/pkg"',
    f'PACMAN_CACHE_DIR="{cache}"',
    1,
)
source = source.replace(
    'PACMAN_LOG_FILE="/var/log/pacman.log"',
    f'PACMAN_LOG_FILE="{pacman_log}"',
    1,
)
start = source.index("root_owned_nonwritable_path() {")
end = source.index("\n}\n\ntrusted_nvidia_cache_archive()", start)
source = source[:start] + "root_owned_nonwritable_path() {\n  return 0\n}" + source[end + 2:]
start = source.index("current_kernel_package_names() {")
end = source.index("\n}\n\nnvidia_rollback_candidate_packages()", start)
source = source[:start] + "current_kernel_package_names() {\n  printf '%s\\n' linux\n}" + source[end + 2:]
out.write_text(source, encoding="utf-8")
PY
chmod +x "$test_reconciler"
bash -n "$test_reconciler"

cat >"$rollback/metadata" <<'EOF'
status=available
rollback_complete=1
EOF
cat >"$rollback/changes.tsv" <<'EOF'
nvidia-utils	610.57.04-1	615.71.09-1	nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst
linux	6.18.1.arch1-1	6.18.2.arch1-1	linux-6.18.1.arch1-1-x86_64.pkg.tar.zst
EOF
: >"$rollback/packages/nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst"
: >"$rollback/packages/linux-6.18.1.arch1-1-x86_64.pkg.tar.zst"

cat >"$state" <<'EOF'
nvidia-utils 615.71.09-1
linux 6.18.2.arch1-1
EOF

cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${FAKE_PACMAN_STATE:?}"
case "${1:-}" in
  -Qq)
    awk '{print $1}' "$state"
    ;;
  -Q)
    shift
    if (( $# == 0 )); then
      cat "$state"
      exit 0
    fi
    rc=0
    for pkg in "$@"; do
      line="$(awk -v p="$pkg" '$1 == p { print; exit }' "$state")"
      if [[ -z "$line" ]]; then
        rc=1
      else
        printf '%s\n' "$line"
      fi
    done
    exit "$rc"
    ;;
  -U)
    [[ ${FAKE_PACMAN_FAIL_U:-0} == 1 ]] && exit 42
    shift
    while (( $# )); do
      case "$1" in
        --needed|--noconfirm) shift ;;
        *)
          base="$(basename -- "$1")"
          case "$base" in
            nvidia-utils-610.57.04-1-*.pkg.tar.*)
              awk '$1 != "nvidia-utils"' "$state" >"${state}.tmp"
              printf '%s\n' 'nvidia-utils 610.57.04-1' >>"${state}.tmp"
              mv "${state}.tmp" "$state"
              ;;
            linux-6.18.1.arch1-1-*.pkg.tar.*)
              awk '$1 != "linux"' "$state" >"${state}.tmp"
              printf '%s\n' 'linux 6.18.1.arch1-1' >>"${state}.tmp"
              mv "${state}.tmp" "$state"
              ;;
            nvidia-utils-615.71.09-1-*.pkg.tar.*)
              awk '$1 != "nvidia-utils"' "$state" >"${state}.tmp"
              printf '%s\n' 'nvidia-utils 615.71.09-1' >>"${state}.tmp"
              mv "${state}.tmp" "$state"
              ;;
            linux-6.18.2.arch1-1-*.pkg.tar.*)
              awk '$1 != "linux"' "$state" >"${state}.tmp"
              printf '%s\n' 'linux 6.18.2.arch1-1' >>"${state}.tmp"
              mv "${state}.tmp" "$state"
              ;;
          esac
          shift
          ;;
      esac
    done
    ;;
  *)
    printf 'unexpected pacman invocation: %q\n' "$*" >&2
    exit 90
    ;;
esac
EOF
chmod +x "$fakebin/pacman"

cat >"$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "--" ]] && shift
exec "$@"
EOF
chmod +x "$fakebin/sudo"

if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_FAIL_U=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback >/dev/null 2>&1
then
  fail 'NVIDIA rollback ignored a failed pacman -U transaction'
fi
grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'failed rollback transaction unexpectedly changed the NVIDIA package state'
grep -Fxq 'linux 6.18.2.arch1-1' "$state" \
  || fail 'failed rollback transaction unexpectedly changed the kernel package state'
if grep -Fxq 'status=restored' "$rollback/metadata"; then
  fail 'failed rollback transaction was incorrectly marked restored'
fi

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback >/dev/null
then
  fail 'saved NVIDIA rollback command failed'
fi

grep -Fxq 'nvidia-utils 610.57.04-1' "$state" \
  || fail 'NVIDIA rollback did not restore the saved driver version'
grep -Fxq 'linux 6.18.1.arch1-1' "$state" \
  || fail 'NVIDIA rollback did not restore the kernel version captured with the driver'

grep -Fxq 'status=restored' "$rollback/metadata" \
  || fail 'successful NVIDIA rollback did not persist restored metadata status'

cat >"$state" <<'EOF'
nvidia-utils 620.12.01-1
linux 6.18.3.arch1-1
EOF

if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback >/dev/null 2>&1
then
  fail 'stale NVIDIA rollback point was accepted after later package changes'
fi

grep -Fxq 'nvidia-utils 620.12.01-1' "$state" \
  || fail 'stale rollback mutated the newer NVIDIA package before refusing'
grep -Fxq 'linux 6.18.3.arch1-1' "$state" \
  || fail 'stale rollback mutated the newer kernel package before refusing'

cat >"$pacman_log" <<'EOF'
[2026-09-10T12:00:00-0400] [ALPM] transaction started
[2026-09-10T12:00:01-0400] [ALPM] upgraded linux (6.18.1.arch1-1 -> 6.18.2.arch1-1)
[2026-09-10T12:00:02-0400] [ALPM] upgraded nvidia-utils (610.57.04-1 -> 615.71.09-1)
[2026-09-10T12:00:03-0400] [ALPM] transaction completed
EOF

: >"$cache/nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst"
: >"$cache/linux-6.18.1.arch1-1-x86_64.pkg.tar.zst"
: >"$cache/nvidia-utils-615.71.09-1-x86_64.pkg.tar.zst"
: >"$cache/linux-6.18.2.arch1-1-x86_64.pkg.tar.zst"

cat >"$state" <<'EOF'
nvidia-utils 615.71.09-1
linux 6.18.2.arch1-1
EOF

list_output="$(
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback --list
)"
grep -Fq '610.57.04' <<<"$list_output" \
  || fail 'cached NVIDIA history does not list the recoverable 610.57.04 driver'

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback --version 610.57.04 >/dev/null
then
  fail 'cached NVIDIA historical version switch failed'
fi

grep -Fxq 'nvidia-utils 610.57.04-1' "$state" \
  || fail 'historical version switch did not select NVIDIA 610.57.04'
grep -Fxq 'linux 6.18.1.arch1-1' "$state" \
  || fail 'historical version switch did not reconstruct the matching kernel state'
grep -Fq $'nvidia-utils\t615.71.09-1\t610.57.04-1' "$rollback/changes.tsv" \
  || fail 'historical version switch did not preserve the pre-switch NVIDIA return point'

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_STATE="$state" \
  "$test_reconciler" --nvidia-rollback >/dev/null
then
  fail 'saved rollback could not restore the pre-switch NVIDIA version after historical testing'
fi

grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'saved rollback did not return from historical NVIDIA testing to 615.71.09'
grep -Fxq 'linux 6.18.2.arch1-1' "$state" \
  || fail 'saved rollback did not restore the matching pre-switch kernel'
printf '%s\n' 'PASS: NVIDIA upgrades require consent, saved rollback is recoverable, historical cached versions are selectable, and stale rollback points fail closed.'
