#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
for script in trials/mangowm/setup.sh trials/mangowm/session.sh \
    trials/mangowm/power.sh trials/mangowm/capture.sh \
    trials/mangowm/status-tags.sh; do
    bash -n "$script"
done
python3 -m json.tool trials/mangowm/waybar.json >/dev/null
grep -Fxq 'allow_tearing=2' trials/mangowm/config.conf
grep -Fxq 'tag_num=9' trials/mangowm/config.conf
grep -Fq 'custom/mango-tags' trials/mangowm/waybar.json
if grep -Fq 'mango/workspaces' trials/mangowm/waybar.json; then
    printf 'Trial must run on stock Waybar, without git-only Mango modules\n' >&2
    exit 1
fi
grep -Fq 'org.freedesktop.impl.portal.ScreenCast=wlr' trials/mangowm/mango-portals.conf
grep -Fq 'mango -c "$src/config.conf" -p' trials/mangowm/setup.sh
if grep -En 'hyprctl|Quickshell.Hyprland|xdg-desktop-portal-hyprland' \
    trials/mangowm/config.conf trials/mangowm/session.sh trials/mangowm/power.sh \
    trials/mangowm/capture.sh trials/mangowm/waybar.json; then
    printf 'FAIL: Hyprland runtime dependency in Mango session\n' >&2
    exit 1
fi
printf 'PASS: Mango trial static checks; runtime Mango -p still required\n'
