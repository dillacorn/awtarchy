#!/usr/bin/env bash
# Offline fake-pacman contract: the KWin preflight performs no package writes.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
target="$root/trials/kwin/preflight.sh"
bash -n "$target"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.config/xdg-desktop-portal"
printf 'untouched\n' > "$tmp/home/.config/xdg-desktop-portal/sway-portals.conf"
cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
case "$1" in
    -Qq) [[ "${3:-}" == hyprland || "${3:-}" == sway ]] ;;
    -Si) [[ "${3:-}" == kwin || "${3:-}" == xorg-xwayland ]] ;;
    *) printf 'unexpected pacman operation: %s\n' "$*" >&2; return 71 ;;
esac
PACMAN
chmod +x "$tmp/bin/pacman"
# CI may run as root. Only this disposable source copy bypasses the root guard.
sed 's/if \[\[ ${EUID} -eq 0 \]\]; then/if [[ 1000 -eq 0 ]]; then/' \
    "$target" > "$tmp/preflight.sh"
out="$(HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" \
    PATH="$tmp/bin:$PATH" bash "$tmp/preflight.sh")"
[[ "$out" == *"Awtarchy KWin survey (read only)"* ]]
[[ "$out" == *"No writes performed"* ]]
[[ "$out" == *"hyprland"* && "$out" == *"sway"* ]]
[[ "$(cat "$tmp/home/.config/xdg-desktop-portal/sway-portals.conf")" == untouched ]]
[[ ! -e "$tmp/home/.config/kwin" ]]
printf 'PASS: KWin survey is read only with fake pacman\n'
