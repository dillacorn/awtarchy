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
grep -Fq 'Roll back to previous NVIDIA driver' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery submenu does not expose the driver rollback picker'
if grep -Fq '"List previous NVIDIA driver releases"' "$LAUNCHER"; then
  fail 'interactive NVIDIA recovery menu still exposes the confusing list-only action'
fi
grep -Fq 'run_current_nvidia_rollback --pick' "$LAUNCHER" \
  || fail 'maintenance NVIDIA recovery submenu does not route to the historical version picker'
grep -Fq 'run_current_nvidia_rollback' "$LAUNCHER" \
  || fail 'NVIDIA rollback is not pinned to the current updater reconciler'
grep -Fq 'awtarchy nvidia-rollback [--pick | --list | --version <driver-version>]' "$LAUNCHER" \
  || fail 'launcher does not expose historical NVIDIA version selection'
# shellcheck disable=SC2016
grep -Fq 'bash "$PACKAGE_RECONCILER" --nvidia-rollback "$@"' "$LAUNCHER" \
  || fail 'launcher does not forward NVIDIA rollback options to the current reconciler'
if grep -Fq 'run_package_reconciler --nvidia-rollback' "$LAUNCHER"; then
  fail 'NVIDIA emergency rollback still follows the active Git-testing package revision'
fi
grep -Fq 'NVIDIA_ROLLBACK_ROOT="/var/lib/awtarchy"' "$RECONCILER" \
  || fail 'production NVIDIA rollback state is not rooted under /var/lib/awtarchy'
grep -Fq 'available_nvidia_driver_releases' "$RECONCILER" \
  || fail 'NVIDIA rollback has no archived driver-release catalog'
grep -Fq 'build_nvidia_release_bundle' "$RECONCILER" \
  || fail 'NVIDIA rollback has no archived release bundle builder'
grep -Fq 'apply_nvidia_history_version' "$RECONCILER" \
  || fail 'NVIDIA rollback has no archived version application path'
grep -Fq 'nvidia-open-dkms' "$RECONCILER" \
  || fail 'modern NVIDIA rollback does not use the kernel-independent open DKMS module strategy'
grep -Fq 'ensure_nvidia_dkms_kernel_headers' "$RECONCILER" \
  || fail 'NVIDIA rollback does not guarantee matching kernel headers before DKMS'
grep -Fq 'restore_failed_nvidia_switch' "$RECONCILER" \
  || fail 'failed NVIDIA release switches have no automatic restore path'
grep -Fq 'ARCH_PACKAGE_ARCHIVE_BASE="https://archive.archlinux.org/packages"' "$RECONCILER" \
  || fail 'NVIDIA historical recovery is not pinned to the official Arch Linux Archive'
grep -Fq 'CACHY_PACKAGE_ARCHIVE_BASE="https://archive.cachyos.org/archive"' "$RECONCILER" \
  || fail 'NVIDIA historical recovery is not pinned to the official CachyOS archive'
grep -Fq 'find_cachyos_archive_package_url' "$RECONCILER" \
  || fail 'NVIDIA historical recovery has no CachyOS archive fallback'
grep -Fq 'find_archlinux_archive_package_url' "$RECONCILER" \
  || fail 'NVIDIA historical recovery has no Arch Linux Archive fallback'
grep -Fq 'trusted_nvidia_history_source' "$RECONCILER" \
  || fail 'NVIDIA historical recovery does not validate local/remote package sources before pacman -U'
grep -Fq 'stage_nvidia_rollback_archive' "$RECONCILER" \
  || fail 'NVIDIA return points cannot stage missing current packages from trusted archives'
grep -Fq 'pacman-key --verify' "$RECONCILER" \
  || fail 'archive-backed NVIDIA return points do not verify detached package signatures'
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
# shellcheck disable=SC2016
grep -Fq 'if ! as_root pacman -R --noconfirm -- "${removals[@]}"; then' "$RECONCILER" \
  || fail 'NVIDIA rollback cannot remove packages that were absent before a release switch'

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
verify_log="$TMP/pacman-key-verify.log"
mkdir -p "$rollback/packages" "$cache" "$fakebin" "$TMP/home"
: >"$runtime"
: >"$pacman_log"
: >"$verify_log"

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
source = source[:start] + """current_kernel_package_names() {
  printf '%s\\n' "${FAKE_KERNEL_PACKAGE:-linux}"
}""" + source[end + 2:]
out.write_text(source, encoding="utf-8")
PY
chmod +x "$test_reconciler"
bash -n "$test_reconciler"

set_pkg() {
  local pkg="$1" version="$2"
  awk -v p="$pkg" '$1 != p' "$state" >"${state}.tmp"
  printf '%s\n' "$pkg $version" >>"${state}.tmp"
  mv "${state}.tmp" "$state"
}

cat >"$fakebin/pacman" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${FAKE_PACMAN_STATE:?}"

set_pkg() {
  local pkg="$1" version="$2"
  awk -v p="$pkg" '$1 != p' "$state" >"${state}.tmp"
  printf '%s\n' "$pkg $version" >>"${state}.tmp"
  mv "${state}.tmp" "$state"
}

remove_pkg() {
  local pkg="$1"
  awk -v p="$pkg" '$1 != p' "$state" >"${state}.tmp"
  mv "${state}.tmp" "$state"
}

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
  -R)
    shift
    while (( $# )); do
      case "$1" in
        --noconfirm|--) shift ;;
        *)
          remove_pkg "$1"
          shift
          ;;
      esac
    done
    ;;
  -U)
    shift
    target_switch=0
    for arg in "$@"; do
      case "$(basename -- "$arg")" in
        nvidia-utils-610.57.04-1-*.pkg.tar.*|nvidia-open-dkms-610.57.04-1-*.pkg.tar.*)
          target_switch=1
          ;;
      esac
    done
    [[ ${FAKE_PACMAN_FAIL_U:-0} == 1 ]] && exit 42
    [[ ${FAKE_PACMAN_FAIL_TARGET:-0} == 1 && $target_switch == 1 ]] && exit 43

    while (( $# )); do
      case "$1" in
        --needed|--noconfirm) shift ;;
        *)
          base="$(basename -- "$1")"
          case "$base" in
            nvidia-utils-610.57.04-1-*.pkg.tar.*)
              set_pkg nvidia-utils 610.57.04-1
              ;;
            nvidia-open-dkms-610.57.04-1-*.pkg.tar.*)
              set_pkg nvidia-open-dkms 610.57.04-1
              ;;
            lib32-nvidia-utils-610.57.04-1-*.pkg.tar.*)
              set_pkg lib32-nvidia-utils 610.57.04-1
              ;;
            nvidia-utils-615.71.09-1-*.pkg.tar.*)
              set_pkg nvidia-utils 615.71.09-1
              ;;
            lib32-nvidia-utils-615.71.09-1-*.pkg.tar.*)
              set_pkg lib32-nvidia-utils 615.71.09-1
              ;;
            nvidia-open-615.71.09-3-*.pkg.tar.*)
              set_pkg nvidia-open 615.71.09-3
              ;;
            linux-6.18.1.arch1-1-*.pkg.tar.*)
              set_pkg linux 6.18.1.arch1-1
              ;;
            linux-6.18.2.arch1-1-*.pkg.tar.*)
              set_pkg linux 6.18.2.arch1-1
              ;;
            linux-cachyos-lts-7.2.5-1-*.pkg.tar.*)
              set_pkg linux-cachyos-lts 7.2.5-1
              ;;
            linux-cachyos-lts-headers-7.2.5-1-*.pkg.tar.*)
              set_pkg linux-cachyos-lts-headers 7.2.5-1
              ;;
            linux-cachyos-lts-nvidia-open-7.2.5-1-*.pkg.tar.*)
              set_pkg linux-cachyos-lts-nvidia-open 7.2.5-1
              ;;
            *)
              printf 'unexpected package in fake pacman -U: %s\n' "$base" >&2
              exit 91
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

cat >"$fakebin/pacman-key" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "--verify" ]] || exit 92
printf '%s\n' "$*" >>"${FAKE_VERIFY_LOG:?}"
EOF
chmod +x "$fakebin/pacman-key"

cat >"$fakebin/dkms" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${FAKE_PACMAN_STATE:?}"
case "${1:-}" in
  autoinstall)
    [[ ${FAKE_DKMS_FAIL:-0} == 1 ]] && exit 44
    exit 0
    ;;
  status)
    version=""
    while (( $# )); do
      case "$1" in
        -v)
          shift
          version="${1:-}"
          ;;
      esac
      shift || true
    done
    if awk -v v="$version" '$1 == "nvidia-open-dkms" && $2 ~ ("^" v "-") { found=1 } END { exit(found ? 0 : 1) }' "$state"; then
      printf 'nvidia/%s, fake-kernel, x86_64: installed\n' "$version"
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 93
    ;;
esac
EOF
chmod +x "$fakebin/dkms"

cat >"$fakebin/mkinitcpio" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == "-P" ]]
EOF
chmod +x "$fakebin/mkinitcpio"

cat >"$fakebin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
url="${!#}"
output=""
head_only=0
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    --output)
      ((i++))
      output="${args[i]}"
      ;;
    --head)
      head_only=1
      ;;
  esac
done

case "$url" in
  https://archive.archlinux.org/packages/n/nvidia-open-dkms/)
    cat <<'INDEX'
nvidia-open-dkms-595.71.05-1-x86_64.pkg.tar.zst
nvidia-open-dkms-610.9.01-1-x86_64.pkg.tar.zst
nvidia-open-dkms-610.10.01-1-x86_64.pkg.tar.zst
nvidia-open-dkms-610.43.03-1-x86_64.pkg.tar.zst
nvidia-open-dkms-610.57.04-1-x86_64.pkg.tar.zst
nvidia-open-dkms-615.71.09-1-x86_64.pkg.tar.zst
nvidia-open-dkms-620.12.01-1-x86_64.pkg.tar.zst
INDEX
    exit 0
    ;;
  https://archive.archlinux.org/packages/n/nvidia-utils/)
    cat <<'INDEX'
nvidia-utils-595.71.05-1-x86_64.pkg.tar.zst
nvidia-utils-610.9.01-1-x86_64.pkg.tar.zst
nvidia-utils-610.10.01-1-x86_64.pkg.tar.zst
nvidia-utils-610.43.03-1-x86_64.pkg.tar.zst
nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst
nvidia-utils-615.71.09-1-x86_64.pkg.tar.zst
nvidia-utils-620.12.01-1-x86_64.pkg.tar.zst
INDEX
    exit 0
    ;;
  https://archive.archlinux.org/packages/l/lib32-nvidia-utils/)
    cat <<'INDEX'
lib32-nvidia-utils-595.71.05-1-x86_64.pkg.tar.zst
lib32-nvidia-utils-610.43.03-1-x86_64.pkg.tar.zst
lib32-nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst
lib32-nvidia-utils-615.71.09-1-x86_64.pkg.tar.zst
INDEX
    exit 0
    ;;
esac

case "$url" in
  https://archive.archlinux.org/packages/n/nvidia-utils/nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst|\
  https://archive.archlinux.org/packages/n/nvidia-open-dkms/nvidia-open-dkms-610.57.04-1-x86_64.pkg.tar.zst|\
  https://archive.archlinux.org/packages/l/lib32-nvidia-utils/lib32-nvidia-utils-610.57.04-1-x86_64.pkg.tar.zst|\
  https://archive.archlinux.org/packages/n/nvidia-utils/nvidia-utils-615.71.09-1-x86_64.pkg.tar.zst|\
  https://archive.archlinux.org/packages/l/lib32-nvidia-utils/lib32-nvidia-utils-615.71.09-1-x86_64.pkg.tar.zst|\
  https://archive.archlinux.org/packages/n/nvidia-open/nvidia-open-615.71.09-3-x86_64.pkg.tar.zst|\
  https://archive.cachyos.org/archive/cachyos-v3/linux-cachyos-lts-7.2.5-1-x86_64_v3.pkg.tar.zst|\
  https://archive.cachyos.org/archive/cachyos-v3/linux-cachyos-lts-headers-7.2.5-1-x86_64_v3.pkg.tar.zst|\
  https://archive.cachyos.org/archive/cachyos-v3/linux-cachyos-lts-nvidia-open-7.2.5-1-x86_64_v3.pkg.tar.zst)
    ;;
  *.pkg.tar.zst.sig)
    ;;
  *)
    exit 22
    ;;
esac

if (( head_only == 1 )); then
  exit 0
fi
if [[ -n "$output" ]]; then
  printf 'fake archive payload for %s\n' "$url" >"$output"
fi
EOF
chmod +x "$fakebin/curl"

# Existing saved rollback remains fail-closed and transaction-checked.
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

if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_FAIL_U=1 \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback >/dev/null 2>&1
then
  fail 'saved NVIDIA rollback ignored a failed pacman -U transaction'
fi
grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'failed saved rollback unexpectedly changed the NVIDIA package state'

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback >/dev/null
then
  fail 'saved NVIDIA rollback command failed'
fi
grep -Fxq 'nvidia-utils 610.57.04-1' "$state" \
  || fail 'saved NVIDIA rollback did not restore the driver version'
grep -Fxq 'linux 6.18.1.arch1-1' "$state" \
  || fail 'saved NVIDIA rollback did not restore the captured kernel version'
grep -Fxq 'status=restored' "$rollback/metadata" \
  || fail 'successful saved NVIDIA rollback did not persist restored status'

# New release picker is archive-backed and independent from pacman history.
rm -rf -- "$rollback"
mkdir -p -- "$rollback/packages"
rm -f -- "$cache"/*
: >"$pacman_log"
: >"$verify_log"

cat >"$state" <<'EOF'
nvidia-utils 615.71.09-1
lib32-nvidia-utils 615.71.09-1
linux-cachyos-lts 7.2.5-1
linux-cachyos-lts-headers 7.2.5-1
linux-cachyos-lts-nvidia-open 7.2.5-1
EOF

list_output="$(
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback --list
)"
grep -Fq '610.57.04' <<<"$list_output" \
  || fail 'archived NVIDIA release picker does not list 610.57.04'
grep -Fq '610.43.03' <<<"$list_output" \
  || fail 'archived NVIDIA release picker does not list multiple previous releases'
grep -Fq '610.9.01' <<<"$list_output" \
  || fail 'release catalog lost a version when version-sort order differs from lexical order'
grep -Fq '610.10.01' <<<"$list_output" \
  || fail 'release catalog intersection still depends on comm-compatible lexical sorting'
if grep -Fq '620.12.01' <<<"$list_output"; then
  fail 'archived NVIDIA release picker exposes a release newer than the installed driver'
fi

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback --version 610.57.04 >/dev/null
then
  fail 'archive-backed NVIDIA 610 release switch failed'
fi

grep -Fxq 'nvidia-utils 610.57.04-1' "$state" \
  || fail 'NVIDIA release switch did not install nvidia-utils 610.57.04'
grep -Fxq 'lib32-nvidia-utils 610.57.04-1' "$state" \
  || fail 'NVIDIA release switch did not keep lib32 userspace aligned'
grep -Fxq 'nvidia-open-dkms 610.57.04-1' "$state" \
  || fail 'NVIDIA release switch did not install the matching open DKMS module source'
if grep -q '^linux-cachyos-lts-nvidia-open ' "$state"; then
  fail 'NVIDIA release switch left the conflicting CachyOS prebuilt module package installed'
fi
grep -Fxq 'linux-cachyos-lts 7.2.5-1' "$state" \
  || fail 'NVIDIA release switch unexpectedly downgraded the current CachyOS kernel'
grep -Fxq 'linux-cachyos-lts-headers 7.2.5-1' "$state" \
  || fail 'NVIDIA release switch disturbed matching current kernel headers'

grep -Fq $'nvidia-open-dkms\t(not installed)\t610.57.04-1' "$rollback/changes.tsv" \
  || fail 'return point does not record the temporary DKMS package as originally absent'
grep -Fq $'linux-cachyos-lts-nvidia-open\t7.2.5-1\t(not installed)' "$rollback/changes.tsv" \
  || fail 'return point does not record the original prebuilt module removal'
[[ -f "$rollback/packages/linux-cachyos-lts-nvidia-open-7.2.5-1-x86_64_v3.pkg.tar.zst" ]] \
  || fail 'return point did not stage the original CachyOS prebuilt module package from archive'
[[ -s "$verify_log" ]] \
  || fail 'archive-backed return point did not verify detached package signatures'

# A later package mutation must still invalidate the saved return point.
set_pkg nvidia-utils 620.12.01-1
if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback >/dev/null 2>&1
then
  fail 'saved return point was accepted after an unrelated later NVIDIA mutation'
fi
set_pkg nvidia-utils 610.57.04-1

# Normal rollback removes temporary DKMS and restores the original 615/prebuilt stack.
if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback >/dev/null
then
  fail 'saved return point could not restore the original NVIDIA stack'
fi

grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'return point did not restore NVIDIA 615.71.09'
grep -Fxq 'lib32-nvidia-utils 615.71.09-1' "$state" \
  || fail 'return point did not restore matching lib32 NVIDIA userspace'
grep -Fxq 'linux-cachyos-lts-nvidia-open 7.2.5-1' "$state" \
  || fail 'return point did not restore the original CachyOS prebuilt NVIDIA module'
if grep -q '^nvidia-open-dkms ' "$state"; then
  fail 'return point did not remove the temporary historical nvidia-open-dkms package'
fi
grep -Fxq 'linux-cachyos-lts 7.2.5-1' "$state" \
  || fail 'return point changed the kernel even though release switching is DKMS-based'

reset_current_stack() {
  rm -rf -- "$rollback"
  mkdir -p -- "$rollback/packages"
  rm -f -- "$cache"/*
  : >"$verify_log"
  cat >"$state" <<'EOF'
nvidia-utils 615.71.09-1
lib32-nvidia-utils 615.71.09-1
linux-cachyos-lts 7.2.5-1
linux-cachyos-lts-headers 7.2.5-1
linux-cachyos-lts-nvidia-open 7.2.5-1
EOF
}

# If the historical package transaction fails after module replacement, restore automatically.
reset_current_stack
if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_PACMAN_FAIL_TARGET=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback --version 610.57.04 >/dev/null 2>&1
then
  fail 'failed NVIDIA target transaction unexpectedly returned success'
fi
grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'failed target transaction did not preserve/restore NVIDIA 615'
grep -Fxq 'linux-cachyos-lts-nvidia-open 7.2.5-1' "$state" \
  || fail 'failed target transaction did not automatically restore the prebuilt NVIDIA module'
if grep -q '^nvidia-open-dkms ' "$state"; then
  fail 'failed target transaction left the temporary DKMS package installed'
fi

# If DKMS build/verification fails after package install, restore automatically too.
reset_current_stack
if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  FAKE_DKMS_FAIL=1 \
  FAKE_KERNEL_PACKAGE=linux-cachyos-lts \
  FAKE_PACMAN_STATE="$state" \
  FAKE_VERIFY_LOG="$verify_log" \
  "$test_reconciler" --nvidia-rollback --version 610.57.04 >/dev/null 2>&1
then
  fail 'failed NVIDIA DKMS build unexpectedly returned success'
fi
grep -Fxq 'nvidia-utils 615.71.09-1' "$state" \
  || fail 'failed DKMS build did not automatically restore NVIDIA 615'
grep -Fxq 'linux-cachyos-lts-nvidia-open 7.2.5-1' "$state" \
  || fail 'failed DKMS build did not automatically restore the original prebuilt module'
if grep -q '^nvidia-open-dkms ' "$state"; then
  fail 'failed DKMS build left the temporary historical DKMS package installed'
fi

printf '%s\n' 'PASS: NVIDIA release picker, DKMS rollback, trusted return-point staging, failure recovery, and saved rollback all pass.'
