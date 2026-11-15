#!/usr/bin/env bash
# Fake-pacman transaction: read-only preview and full-Plasma rejection.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source="$root/trials/kwin/package-plan.sh"
bash -n "$source"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pacman" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -Si) [[ "${3:-}" == kwin || "${3:-}" == xorg-xwayland ||
       "${3:-}" == python-dbus-next || "${3:-}" == quickshell ||
       "${3:-}" == foot || "${3:-}" == fuzzel ]] ;;
  -Sp)
    printf 'kwin\nxorg-xwayland\nkglobalacceld\npython-dbus-next\nquickshell\nfoot\nfuzzel\n'
    if [[ ${INJECT_PLASMA:-} == yes ]]; then printf 'plasma-workspace\n'; fi ;;
  *) printf 'Unexpected operation: %s\n' "$*" >&2; return 65 ;;
esac
SH
chmod +x "$tmp/bin/pacman"
# No root bypass in production; CI-only test copy for runners that use root.
sed 's/\[\[ ${EUID} -ne 0 \]\]/[[ 1000 -ne 0 ]]/' "$source" > "$tmp/plan.sh"
PATH="$tmp/bin:$PATH" bash "$tmp/plan.sh" > "$tmp/good"
grep -Fq 'Number of package targets: 7' "$tmp/good"
grep -Fq 'Nothing was installed or removed' "$tmp/good"
if INJECT_PLASMA=yes PATH="$tmp/bin:$PATH" bash "$tmp/plan.sh" > "$tmp/bad" 2>&1; then
    printf 'ERROR: full Plasma transaction accepted\n' >&2
    false
fi
grep -Fq 'Full Plasma package unexpectedly required' "$tmp/bad"
printf 'PASS: KWin package plan read-only and full Plasma refused\n'
