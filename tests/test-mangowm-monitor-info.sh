#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/mmsg" <<'MOCK'
#!/usr/bin/env bash
[[ "$*" == 'get all-monitors' ]] || return 1
printf '%s\n' '{"monitors":[{"name":"DP-3","active":false},{"name":"DP-1","active":true}]}'
MOCK
# A synthetic snapshot matching the real WLR text format. No output changes.
cat >"$tmp/bin/wlr-randr" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' \
    'DP-3 "ViewSonic Corporation XG2431 DEVICE-3 (DP-3)"' \
    '  Make: ViewSonic Corporation' \
    '  Model: XG2431' \
    '  Serial: DEVICE-3' \
    '  Enabled: yes' \
    'DP-1 "BNQ XL2566X+ DEVICE-1 (DP-1)"' \
    '  Make: BNQ' \
    '  Model: XL2566X+' \
    '  Serial: DEVICE-1' \
    '  Enabled: yes'
MOCK
chmod +x "$tmp/bin/mmsg" "$tmp/bin/wlr-randr"
export PATH="$tmp/bin:$PATH" XDG_CURRENT_DESKTOP=mango MANGO_INSTANCE_SIGNATURE=mock
script="config/mango/scripts/monitor-info.sh"
bash -n "$script"

result="$(bash "$script" DP-3)"
[[ "$result" == $'DP-3\tViewSonic Corporation\tXG2431\tDEVICE-3\t'* ]]
[[ "$(bash "$script")" == $'DP-1\tBNQ\tXL2566X+\tDEVICE-1\t'* ]]
if bash "$script" not-an-output >/dev/null 2>&1; then
    printf 'ERROR: unknown output accepted\n' >&2
    false
fi
if XDG_CURRENT_DESKTOP=Hyprland bash "$script" DP-3 >/dev/null 2>&1; then
    printf 'ERROR: wrong session accepted\n' >&2
    false
fi
if bash "$script" 'DP-3;echo unexpected' >/dev/null 2>&1; then
    printf 'ERROR: invalid monitor identifier accepted\n' >&2
    false
fi
grep -Fq 'need_cmd mmsg' config/hypr/scripts/hypr-ddc-brightness.sh
grep -Fq 'bash "$helper" "${TARGET_CONN:-}"' config/hypr/scripts/hypr-ddc-brightness.sh
printf 'PASS: Mango monitor identity lookup and DDC integration isolation\n'
