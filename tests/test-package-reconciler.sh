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

[[ -f $RECONCILER ]] || fail "package reconciler source is missing"
[[ -x $RECONCILER ]] || fail "package reconciler source is not executable"
bash -n "$RECONCILER"

python3 - "$RECONCILER" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.find("multi_select() {")
if start < 0:
    raise SystemExit("missing multi_select")
search_from = start + len("multi_select() {")
next_function = re.search(
    r"(?m)^[A-Za-z_][A-Za-z0-9_]*\(\) \{$",
    text[search_from:],
)
end = len(text) if next_function is None else search_from + next_function.start()
body = text[start:end]
if "else\n          current=$((${#labels[@]} - 1))" not in body:
    raise SystemExit("multi_select does not wrap Up to the final entry")
if "else\n          current=0" not in body:
    raise SystemExit("multi_select does not wrap Down to the first entry")
PY

grep -Fq 'awtarchy packages' "$LAUNCHER" \
  || fail "launcher help does not expose awtarchy packages"
grep -Fq 'Reconcile packages (install current / remove replaced)' "$LAUNCHER" \
  || fail "maintenance menu does not expose package reconciliation"
grep -Fq 'new_package_reconciler=' "$LAUNCHER" \
  || fail "self-update does not install the package reconciler"

home="${TMP}/home"
fakebin="${TMP}/fakebin"
managed="${TMP}/managed-packages"
runtime="${TMP}/awtarchy-runtime.sh"
mkdir -p "$home/.local/state/awtarchy" "$fakebin"
printf '%s\n' 'is_laptop=true' >"$home/.local/state/awtarchy/hardware-state"
printf '%s\n' waybar >"$managed"

cat >"$runtime" <<'EOF_RUNTIME'
declare -a PKG_GROUPS=(
  "Window Management:quickshell wl-clipboard cliphist optional-window-tool"
  "Utilities:upower polkit python-gobject jq"
)
declare -a PACKAGES_AUR=(
  smtty
)
declare -a FLATPAK_CATALOG=(
  "1|Flatseal|com.github.tchx84.Flatseal"
  "0|Moonlight|com.moonlight_stream.Moonlight"
)
EOF_RUNTIME

cat >"$fakebin/pacman" <<'EOF_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
installed=(quickshell wl-clipboard upower playerctl hyprland-qt-support polkit python-gobject jq waybar mako)
case "${1:-}" in
  -Qq)
    printf '%s\n' "${installed[@]}"
    ;;
  -Q)
    needle="${2:-}"
    for pkg in "${installed[@]}"; do
      [[ $pkg == "$needle" ]] && exit 0
    done
    exit 1
    ;;
  *)
    printf 'unexpected pacman invocation: %q' "$@" >&2
    printf '\n' >&2
    exit 90
    ;;
esac
EOF_PACMAN
chmod +x "$fakebin/pacman"

cat >"$fakebin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  is-enabled|is-active) exit 1 ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "$fakebin/systemctl"

cat >"$fakebin/flatpak" <<'EOF_FLATPAK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'list --app --columns=application'* ]]; then
  exit 0
fi
exit 0
EOF_FLATPAK
chmod +x "$fakebin/flatpak"

output="$({
  PATH="$fakebin:/usr/bin:/bin" \
  HOME="$home" \
  USER=tester \
  AWTARCHY_RUNTIME="$runtime" \
  AWTARCHY_MANAGED_PACKAGES_FILE="$managed" \
  "$RECONCILER" --review
} 2>&1)"

printf '%s\n' "$output" | grep -Fq 'System type: laptop' \
  || fail "review did not reuse saved laptop state"
printf '%s\n' "$output" | grep -Fq 'cliphist' \
  || fail "review did not identify missing cliphist"
printf '%s\n' "$output" | grep -Fq 'waybar' \
  || fail "review did not identify managed retired waybar"
printf '%s\n' "$output" | grep -Fq 'mako' \
  || fail "review did not report installed unowned retired mako"
printf '%s\n' "$output" | grep -Fq 'Ly TTY login manager: not installed' \
  || fail "review did not report Ly state"
printf '%s\n' "$output" | grep -Fq 'Arch catalog packages:' \
  || fail "review did not load the current runtime package catalog"
printf '%s\n' "$output" | grep -Fq 'AUR catalog packages:' \
  || fail "review did not load the current runtime AUR catalog"
printf '%s\n' "$output" | grep -Fq 'Flatpak catalog apps:' \
  || fail "review did not load the current runtime Flatpak catalog"

# Recovery lives in the package reconciler so the existing self-updater ships it
# without adding another installed maintenance component. The normal update path
# already invokes --needs-action before changing configs, so that mode must run
# the pacman sync-database preflight as well.
grep -Fq 'pacman_sync_db_preflight' "$RECONCILER" \
  || fail "package reconciler has no pacman sync database preflight"
grep -Fq 'pacman_install_with_recovery' "$RECONCILER" \
  || fail "package reconciler does not route repository installs through recovery"
grep -Fq 'pacman_sync_db_preflight || true' "$RECONCILER" \
  || fail "--needs-action does not invoke the pacman recovery preflight"

recovery_root="${TMP}/pacman-recovery"
recovery_bin="${recovery_root}/bin"
recovery_sync="${recovery_root}/sync"
recovery_state="${recovery_root}/state"
recovery_log="${recovery_root}/calls.log"
recovery_conf="${recovery_root}/pacman.conf"
mkdir -p "$recovery_bin" "$recovery_sync" "$recovery_state"

cat >"$recovery_conf" <<'EOF_RECOVERY_CONF'
[options]
Architecture = auto

[cachyos-extra-znver4]
Server = https://example.invalid/cachyos/$arch/$repo

[cachyos]
Server = https://example.invalid/cachyos/$arch/$repo

[core]
Server = https://example.invalid/arch/$repo/os/$arch

[extra]
Server = https://example.invalid/arch/$repo/os/$arch

[multilib]
Server = https://example.invalid/arch/$repo/os/$arch
EOF_RECOVERY_CONF

cat >"$recovery_bin/pacman" <<'EOF_RECOVERY_PACMAN'
#!/usr/bin/env bash
set -euo pipefail
: "${RECOVERY_STATE:?}"
: "${RECOVERY_LOG:?}"
: "${RECOVERY_CACHY_RATE_PATH:?}"
repo="$(cat "${RECOVERY_STATE}/repo")"
mode="$(cat "${RECOVERY_STATE}/mode")"
printf 'pacman' >>"$RECOVERY_LOG"
printf '\t%q' "$@" >>"$RECOVERY_LOG"
printf '\n' >>"$RECOVERY_LOG"

config=''
args=("$@")
for (( i=0; i<${#args[@]}; i++ )); do
  if [[ ${args[$i]} == --config && $((i + 1)) -lt ${#args[@]} ]]; then
    config="${args[$((i + 1))]}"
  fi
done

if [[ " $* " == *' -Slq '* ]]; then
  if [[ -f "${RECOVERY_STATE}/repaired" ]]; then
    exit 0
  fi
  printf "error: %s: signature from \"Example Signer <signer@example.invalid>\" is invalid\n" "$repo" >&2
  printf "error: database '%s' is not valid (invalid or corrupted database (PGP signature))\n" "$repo" >&2
  printf '%s\n' 'error: failed to synchronize all databases (unexpected error)' >&2
  exit 42
fi

if [[ " $* " == *' cachyos-rate-mirrors '* ]]; then
  [[ -n $config && -f $config ]] || exit 61
  if grep -Fq "[$repo]" "$config"; then
    printf 'bootstrap config still contains broken repo %s\n' "$repo" >&2
    exit 62
  fi
  grep -Fq '[core]' "$config" || exit 63
  cat >"$RECOVERY_CACHY_RATE_PATH" <<'EOF_RATE'
#!/usr/bin/env bash
set -euo pipefail
printf 'cachy-rate\t%s\n' "$*" >>"${RECOVERY_LOG:?}"
EOF_RATE
  chmod 0755 "$RECOVERY_CACHY_RATE_PATH"
  exit 0
fi

if [[ " $* " == *' reflector '* ]]; then
  exit 64
fi

if [[ " $* " == *' -Syy '* ]]; then
  : >"${RECOVERY_STATE}/repaired"
  exit 0
fi

if [[ " $* " == *' -Syu '* ]]; then
  if [[ -f "${RECOVERY_STATE}/repaired" ]]; then
    exit 0
  fi
  if [[ $mode == package-signature ]]; then
    printf '%s\n' 'error: /var/cache/pacman/pkg/example.pkg.tar.zst is corrupted (invalid or corrupted package (PGP signature))' >&2
    exit 41
  fi
  printf "error: %s: signature from \"Example Signer <signer@example.invalid>\" is invalid\n" "$repo" >&2
  printf "error: database '%s' is not valid (invalid or corrupted database (PGP signature))\n" "$repo" >&2
  printf '%s\n' 'error: failed to synchronize all databases (unexpected error)' >&2
  exit 43
fi

printf 'unexpected recovery pacman invocation: %q' "$@" >&2
printf '\n' >&2
exit 90
EOF_RECOVERY_PACMAN
chmod 0755 "$recovery_bin/pacman"

cat >"$recovery_bin/reflector" <<'EOF_REFLECTOR'
#!/usr/bin/env bash
set -euo pipefail
printf 'reflector\t%s\n' "$*" >>"${RECOVERY_LOG:?}"
EOF_REFLECTOR
chmod 0755 "$recovery_bin/reflector"

run_recovery_check() {
  RECOVERY_STATE="$recovery_state" \
  RECOVERY_LOG="$recovery_log" \
  RECOVERY_CACHY_RATE_PATH="$recovery_bin/cachyos-rate-mirrors" \
  AWTARCHY_PACMAN_RECOVERY_TEST_MODE=1 \
  AWTARCHY_PACMAN_BIN="$recovery_bin/pacman" \
  AWTARCHY_PACMAN_SYNC_DIR="$recovery_sync" \
  AWTARCHY_PACMAN_CONF="$recovery_conf" \
  AWTARCHY_CACHY_RATE_BIN="$recovery_bin/cachyos-rate-mirrors" \
  AWTARCHY_REFLECTOR_BIN="$recovery_bin/reflector" \
  "$RECONCILER" --pacman-recovery-check
}

run_recovery_pacman() {
  RECOVERY_STATE="$recovery_state" \
  RECOVERY_LOG="$recovery_log" \
  RECOVERY_CACHY_RATE_PATH="$recovery_bin/cachyos-rate-mirrors" \
  AWTARCHY_PACMAN_RECOVERY_TEST_MODE=1 \
  AWTARCHY_PACMAN_BIN="$recovery_bin/pacman" \
  AWTARCHY_PACMAN_SYNC_DIR="$recovery_sync" \
  AWTARCHY_PACMAN_CONF="$recovery_conf" \
  AWTARCHY_CACHY_RATE_BIN="$recovery_bin/cachyos-rate-mirrors" \
  AWTARCHY_REFLECTOR_BIN="$recovery_bin/reflector" \
  "$RECONCILER" --pacman-recovery-run -- "$@"
}

reset_recovery_case() {
  local repo="$1" mode="${2:-database-signature}"
  rm -f -- "$recovery_state/repaired" "$recovery_log" \
    "$recovery_bin/cachyos-rate-mirrors"
  printf '%s\n' "$repo" >"$recovery_state/repo"
  printf '%s\n' "$mode" >"$recovery_state/mode"
  printf 'broken-db\n' >"$recovery_sync/${repo}.db"
  printf 'broken-sig\n' >"$recovery_sync/${repo}.db.sig"
}

reset_recovery_case cachyos-extra-znver4
AWTARCHY_ASSUME_PACMAN_REPAIR=yes run_recovery_check \
  || fail "CachyOS sync database recovery did not succeed"
[[ ! -e "$recovery_sync/cachyos-extra-znver4.db" ]] \
  || fail "CachyOS recovery did not clear only the broken database cache"
[[ ! -e "$recovery_sync/cachyos-extra-znver4.db.sig" ]] \
  || fail "CachyOS recovery did not clear the broken database signature cache"
grep -Fq $'cachy-rate\t' "$recovery_log" \
  || fail "CachyOS recovery did not rank CachyOS mirrors"
grep -Fq 'cachyos-rate-mirrors' "$recovery_log" \
  || fail "CachyOS recovery did not bootstrap the missing mirror tool"
grep -Fq -- '-Syy' "$recovery_log" \
  || fail "CachyOS recovery did not force a database resync"

reset_recovery_case extra
AWTARCHY_ASSUME_PACMAN_REPAIR=yes run_recovery_check \
  || fail "Arch sync database recovery did not succeed"
grep -Fq $'reflector\t--verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist' "$recovery_log" \
  || fail "Arch recovery did not refresh standard Arch mirrors with reflector"
grep -Fq -- '-Syy' "$recovery_log" \
  || fail "Arch recovery did not force a database resync"

reset_recovery_case core
if AWTARCHY_ASSUME_PACMAN_REPAIR=no run_recovery_check >/dev/null 2>&1; then
  fail "declined pacman recovery unexpectedly succeeded"
fi
[[ -e "$recovery_sync/core.db" && -e "$recovery_sync/core.db.sig" ]] \
  || fail "declining pacman recovery mutated the sync database cache"
[[ ! -s $recovery_log || $(grep -c -- '-Syy' "$recovery_log" || true) -eq 0 ]] \
  || fail "declining pacman recovery forced a database resync"

reset_recovery_case extra package-signature
if AWTARCHY_ASSUME_PACMAN_REPAIR=yes run_recovery_pacman -Syu --needed --noconfirm quickshell >/dev/null 2>&1; then
  fail "package-file signature failure was incorrectly treated as a sync database failure"
fi
[[ -e "$recovery_sync/extra.db" && -e "$recovery_sync/extra.db.sig" ]] \
  || fail "package-file signature failure mutated repository sync cache"
if [[ -s $recovery_log ]] && grep -Eq 'cachy-rate|reflector| -Syy ' "$recovery_log"; then
  fail "package-file signature failure triggered mirror/database repair"
fi

reset_recovery_case cachyos-extra-znver4
cat >"$recovery_bin/cachyos-rate-mirrors" <<'EOF_EXISTING_RATE'
#!/usr/bin/env bash
set -euo pipefail
printf 'cachy-rate\t%s\n' "$*" >>"${RECOVERY_LOG:?}"
EOF_EXISTING_RATE
chmod 0755 "$recovery_bin/cachyos-rate-mirrors"
AWTARCHY_ASSUME_PACMAN_REPAIR=yes run_recovery_pacman -Syu --needed --noconfirm quickshell \
  || fail "pacman command was not retried after successful sync database recovery"
[[ $(grep -c $'pacman\t-Syu' "$recovery_log" || true) -eq 2 ]] \
  || fail "pacman recovery did not retry the original command exactly once"

printf 'PASS: package reconciler review, launcher contracts, and pacman sync database recovery\n'