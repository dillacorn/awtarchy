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
grep -Fq 'Rollback last NVIDIA driver update' "$LAUNCHER" \
  || fail 'maintenance menu does not expose NVIDIA rollback'

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

rollback="$TMP/rollback"
cache="$TMP/cache"
fakebin="$TMP/bin"
state="$TMP/pacman-state"
runtime="$TMP/runtime.sh"
mkdir -p "$rollback/packages" "$cache" "$fakebin" "$TMP/home"
: >"$runtime"

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

if ! PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  AWTARCHY_NVIDIA_ROLLBACK_DIR="$rollback" \
  FAKE_PACMAN_STATE="$state" \
  "$RECONCILER" --nvidia-rollback >/dev/null
then
  fail 'saved NVIDIA rollback command failed'
fi

grep -Fxq 'nvidia-utils 610.57.04-1' "$state" \
  || fail 'NVIDIA rollback did not restore the saved driver version'
grep -Fxq 'linux 6.18.1.arch1-1' "$state" \
  || fail 'NVIDIA rollback did not restore the kernel version captured with the driver'

cat >"$state" <<'EOF'
nvidia-utils 620.12.01-1
linux 6.18.3.arch1-1
EOF

if PATH="$fakebin:/usr/bin:/bin" \
  HOME="$TMP/home" \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_TEST_MODE=1 \
  AWTARCHY_NVIDIA_ROLLBACK_ASSUME_YES=1 \
  AWTARCHY_NVIDIA_ROLLBACK_DIR="$rollback" \
  FAKE_PACMAN_STATE="$state" \
  "$RECONCILER" --nvidia-rollback >/dev/null 2>&1
then
  fail 'stale NVIDIA rollback point was accepted after later package changes'
fi

grep -Fxq 'nvidia-utils 620.12.01-1' "$state" \
  || fail 'stale rollback mutated the newer NVIDIA package before refusing'
grep -Fxq 'linux 6.18.3.arch1-1' "$state" \
  || fail 'stale rollback mutated the newer kernel package before refusing'

printf '%s\n' 'PASS: NVIDIA upgrades require consent, rollback state is recoverable, and stale rollback points fail closed.'
