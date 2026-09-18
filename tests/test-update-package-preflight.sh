#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${ROOT}/local/bin/awtarchy"
RECONCILER="${ROOT}/local/share/awtarchy/awtarchy-package-reconcile.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n "$LAUNCHER"
bash -n "$RECONCILER"

grep -Fq -- '--needs-action' "$RECONCILER" \
    || fail 'package reconciler does not expose the non-mutating --needs-action status mode'
if grep -Fq -- 'offer_package_reconciliation_before_update' "$LAUNCHER"; then
    fail 'awtarchy update still invokes package reconciliation implicitly'
fi
grep -Fq -- '"Reconcile packages (install current / remove replaced)"' "$LAUNCHER" \
    || fail 'explicit package reconciliation menu entry disappeared'

update_case="$(python3 - "$LAUNCHER" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
start_marker = '    update)\n      reject_stable_testing_overrides "$@"\n'
start = text.find(start_marker)
if start < 0:
    raise SystemExit(1)
end = text.find('\n      ;;', start)
if end < 0:
    raise SystemExit(1)
print(text[start:end + len('\n      ;;')])
PY
)" || fail 'could not locate the main awtarchy update dispatcher'

ensure_line="$(grep -n -m1 -F 'ensure_latest_updater "$@"' <<<"$update_case" | cut -d: -f1 || true)"
release_line="$(grep -n -m1 -F 'config_release_ready_or_noop "$@"' <<<"$update_case" | cut -d: -f1 || true)"
[[ $ensure_line =~ ^[0-9]+$ && $release_line =~ ^[0-9]+$ ]] \
    || fail 'could not locate update readiness ordering'
(( ensure_line < release_line )) \
    || fail 'updater refresh must happen before config update readiness/apply'
if grep -Fq -- 'run_package_reconciler' <<<"$update_case" \
    || grep -Fq -- 'PACKAGE_RECONCILER' <<<"$update_case"; then
    fail 'awtarchy update must not launch the full package reconciler'
fi

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/runtime.sh" <<'RUNTIME'
declare -a PKG_GROUPS=(
  "Test:snapshot"
)
declare -a OPTIONAL_ARCH_PACKAGES=(
  moonlight-qt
)
declare -a PACKAGES_AUR=()
declare -a OPTIONAL_AUR_PACKAGES=(
  vesktop-bin
)
declare -a FLATPAK_CATALOG=(
  "0|Flatseal|com.github.tchx84.Flatseal"
)
RUNTIME

cat >"$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == -Q && -n ${2:-} ]]; then
    grep -Fxq -- "$2" "${FAKE_INSTALLED:?}"
    exit $?
fi
exit 1
PACMAN
chmod +x "$tmp/bin/pacman"

cat >"$tmp/bin/flatpak" <<'FLATPAK'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
FLATPAK
chmod +x "$tmp/bin/flatpak"

cat >"$tmp/hardware-state" <<'STATE'
is_laptop=true
STATE
: >"$tmp/managed-packages"

cat >"$tmp/installed" <<'PKGS'
quickshell
wl-clipboard
cliphist
upower
playerctl
hyprland-qt-support
polkit
python-gobject
jq
PKGS

review_output="$(
AWTARCHY_RUNTIME="$tmp/runtime.sh" \
AWTARCHY_HARDWARE_FILE="$tmp/hardware-state" \
AWTARCHY_MANAGED_PACKAGES_FILE="$tmp/managed-packages" \
FAKE_INSTALLED="$tmp/installed" \
PATH="$tmp/bin:$PATH" \
bash "$RECONCILER" --review
)"
if ! grep -Fq -- '  - snapshot' <<<"$review_output"; then
    printf '%s\n' "$review_output" >&2
    fail 'fixture does not expose snapshot as a missing current Arch catalog package'
fi
if ! grep -Fq -- '  - moonlight-qt' <<<"$review_output"; then
    printf '%s\n' "$review_output" >&2
    fail 'fixture does not expose moonlight-qt as an available optional Arch package'
fi
if ! grep -Fq -- '  - vesktop-bin' <<<"$review_output"; then
    printf '%s\n' "$review_output" >&2
    fail 'fixture does not expose vesktop-bin as an available optional AUR package'
fi
if ! grep -Fq -- 'Flatseal (com.github.tchx84.Flatseal)' <<<"$review_output"; then
    printf '%s\n' "$review_output" >&2
    fail 'fixture does not expose Flatseal as an available optional Flatpak app'
fi

set +e
AWTARCHY_RUNTIME="$tmp/runtime.sh" \
AWTARCHY_HARDWARE_FILE="$tmp/hardware-state" \
AWTARCHY_MANAGED_PACKAGES_FILE="$tmp/managed-packages" \
FAKE_INSTALLED="$tmp/installed" \
PATH="$tmp/bin:$PATH" \
bash "$RECONCILER" --needs-action >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 10 ]] || fail "--needs-action should return 10 for missing current packages, got ${rc}"

printf '%s\n' snapshot >>"$tmp/installed"

# Only optional apps remain missing now. That is still a valid clean state for
# the explicit reconciler status check.
set +e
AWTARCHY_RUNTIME="$tmp/runtime.sh" \
AWTARCHY_HARDWARE_FILE="$tmp/hardware-state" \
AWTARCHY_MANAGED_PACKAGES_FILE="$tmp/managed-packages" \
FAKE_INSTALLED="$tmp/installed" \
PATH="$tmp/bin:$PATH" \
bash "$RECONCILER" --needs-action >/dev/null 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    clean_review="$(
    AWTARCHY_RUNTIME="$tmp/runtime.sh" \
    AWTARCHY_HARDWARE_FILE="$tmp/hardware-state" \
    AWTARCHY_MANAGED_PACKAGES_FILE="$tmp/managed-packages" \
    FAKE_INSTALLED="$tmp/installed" \
    PATH="$tmp/bin:$PATH" \
    bash "$RECONCILER" --review
    )"
    printf '%s\n' "$clean_review" >&2
    fail "--needs-action should ignore missing optional apps, got ${rc}"
fi

printf '%s\n' 'PASS: awtarchy update never launches package reconciliation implicitly; explicit drift detection remains available.'
