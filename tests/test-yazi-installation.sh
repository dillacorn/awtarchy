#!/usr/bin/env bash
# Required Yazi package is installed on fresh Arch and repaired on Git/stable updates.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
RECONCILER="$ROOT/local/share/awtarchy/awtarchy-package-reconcile.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }

grep -Fq 'Terminal Apps:foot nano micro yazi ' "$RUNTIME" || fail 'Yazi is not selected by default'
grep -Fq 'pacman_install_one yazi || die' "$RUNTIME" || fail 'fresh install does not install Yazi before plugin setup'
grep -Eq '^[[:space:]]+yazi$' "$RECONCILER" || fail 'Yazi absent from package reconciliation requirements'
grep -Fq 'ensure_yazi_application_for_target "$target_home"' "$RUNTIME" || fail 'update preflight omits Yazi'

# Exercise the actual preflight functions using an isolated fake pacman.
awk '/^target_requires_yazi_application\(\) \{/ { show=1 } show { print } show && /^}$/ { show=0 }' "$RUNTIME" >"$tmp/functions.sh"
awk '/^ensure_yazi_application_for_target\(\) \{/ { show=1 } show { print } show && /^}$/ { show=0 }' "$RUNTIME" >>"$tmp/functions.sh"
bash -n "$tmp/functions.sh"
# shellcheck source=/dev/null
source "$tmp/functions.sh"
log() { :; }
die() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
record_managed_packages() { printf '%s\n' "$*" >>"$tmp/ledger"; }
update_pacman_install_with_404_recovery() {
  [[ $1 == root && $3 == yazi ]] || return 1
  "$2" -S --needed --noconfirm yazi
}
cat >"$tmp/pacman" <<'PACMAN'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == -Qq && ${2:-} == yazi ]]; then
  [[ -f $AWTARCHY_YAZI_TEST_INSTALLED ]]
elif [[ $1 == -S && $* == *yazi* ]]; then
  printf 'installed\n' >"$AWTARCHY_YAZI_TEST_INSTALLED"
  printf 'install\n' >>"$AWTARCHY_YAZI_TEST_CALLS"
else
  printf 'Unexpected pacman arguments: %s\n' "$*" >&2
  return 1
fi
PACMAN
chmod +x "$tmp/pacman"
export AWTARCHY_YAZI_TEST_INSTALLED="$tmp/installed"
export AWTARCHY_YAZI_TEST_CALLS="$tmp/calls"
export AWTARCHY_TEST_PACMAN_BIN="$tmp/pacman"
export AWTARCHY_TEST_TARGET_HOME="$tmp/home"
export AWTARCHY_TEST_ARCHIVE="$tmp/archive"
mkdir -p "$tmp/home/.config/yazi"
printf 'require("bookmarks"):setup()\n' >"$tmp/home/.config/yazi/init.lua"
ensure_yazi_application_for_target "$tmp/home" || fail 'missing Yazi could not be repaired'
[[ -f $tmp/installed ]] || fail 'Yazi missing after repair'
[[ $(wc -l <"$tmp/calls") == 1 ]] || fail 'expected one installation'
ensure_yazi_application_for_target "$tmp/home" || fail 'installed Yazi failed preflight'
[[ $(wc -l <"$tmp/calls") == 1 ]] || fail 'installed Yazi was installed twice'
rm -f "$tmp/installed"
mv "$tmp/home/.config/yazi/init.lua" "$tmp/home/.config/yazi/init.lua.disabled"
ensure_yazi_application_for_target "$tmp/home" || fail 'unmanaged target should skip'
[[ $(wc -l <"$tmp/calls") == 1 ]] || fail 'unmanaged target should not install Yazi'
printf '%s\n' 'PASS: fresh install/default catalog and existing Git/stable update Yazi repair.'
