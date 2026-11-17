#!/usr/bin/env bash
# Static-only; do not test actual DRM/Ly in CI.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
src="$root/trials/kwin"
bash -n "$src/ly-session.sh"
bash -n "$src/setup-ly.sh"
grep -Fqx 'Exec=/usr/local/bin/awtarchy-kwin-trial-session' "$src/kwin.desktop"
grep -Fqx 'Name=KWin (Awtarchy Trial)' "$src/kwin.desktop"
grep -Fq 'bash "$source" --ly' "$src/ly-session.sh"
grep -Fq '[[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]' "$src/ly-session.sh"
printf 'PASS: KWin Ly source, guard, and static desktop entry\n'
