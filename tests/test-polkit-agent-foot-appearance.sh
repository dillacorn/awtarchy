#!/usr/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AUTH_CONFIG="$ROOT/config/hypr/scripts/awtarchy-polkit-agent/foot.ini"
FOOT_CONFIG="$ROOT/config/foot/foot.ini"
LAUNCHER="$ROOT/config/hypr/scripts/awtarchy-polkit-agent/launcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

[[ -f $AUTH_CONFIG && -f $FOOT_CONFIG && -f $LAUNCHER ]]
grep -Fxq 'pad=22x22' "$AUTH_CONFIG"
grep -Fxq 'font=NotoSansM Nerd Font Mono:size=12' "$AUTH_CONFIG"
grep -Fxq 'alpha=0.85' "$AUTH_CONFIG"
! grep -Eq '(shell=|include=|import=|/home/)' "$AUTH_CONFIG"

if command -v foot >/dev/null 2>&1; then
    foot --check-config --config="$AUTH_CONFIG"
    foot --check-config --config="$FOOT_CONFIG"
fi

awk '
  /^# AWTARCHY_POLKIT_APPEARANCE_PY_BEGIN$/ { capture=1; next }
  /^# AWTARCHY_POLKIT_APPEARANCE_PY_END$/   { capture=0; next }
  capture { print }
' "$LAUNCHER" >"$TMP/appearance.py"
[[ -s $TMP/appearance.py ]]

HOME_FIXTURE="$TMP/home"
mkdir -p -- "$HOME_FIXTURE/.config/foot"
cat >"$HOME_FIXTURE/.config/foot/foot.ini" <<'EOF'
font=Fixture Mono:size=13.5
pad=17x19
shell=/tmp/never-run-me
[key-bindings]
clipboard-copy=[/tmp/never-run-me]
[colors]
alpha=0.73
background=123456
foreground=abcdef
regular1=ff0000
regular2=00ff00
bright4=0000ff
urls=/tmp/untrusted
EOF

OPTIONS="$(/usr/bin/python3 -I "$TMP/appearance.py" "$HOME_FIXTURE/.config/foot/foot.ini" "$HOME_FIXTURE")"
grep -Fqx 'font=Fixture Mono:size=13.5' <<<"$OPTIONS"
grep -Fqx 'pad=17x19' <<<"$OPTIONS"
grep -Fqx 'colors.alpha=0.73' <<<"$OPTIONS"
grep -Fqx 'colors.background=123456' <<<"$OPTIONS"
grep -Fqx 'colors.foreground=abcdef' <<<"$OPTIONS"
grep -Fqx 'colors.regular1=ff0000' <<<"$OPTIONS"
if grep -Eq 'never-run-me|shell=|key-bindings|clipboard|urls=' <<<"$OPTIONS"; then
    printf '%s\n' 'FAIL: the trusted appearance parser copied executable configuration' >&2
    exit 1
fi
grep -Fq 'AWTARCHY_POLKIT_FOOT_OPTIONS="$appearance_text"' "$LAUNCHER"
grep -Fq 'AWTARCHY_POLKIT_APPEARANCE_PY_BEGIN' "$LAUNCHER"
printf '%s\n' 'PASS: trusted Foot PolicyKit appearance sanitizer'
