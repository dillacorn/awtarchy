#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p -- "$tmp/bin" "$tmp/config/xdg-desktop-portal" "$tmp/conflict/mango"
chmod 0755 -- "$tmp/config/xdg-desktop-portal"

# Fake compositor executables. The real parser runs in a separate Arch CI step.
for binary in mango mmsg waybar fuzzel mako swaybg swayidle swaylock grim slurp; do
    printf '#!/usr/bin/env bash\n:\n' >"$tmp/bin/$binary"
    chmod +x -- "$tmp/bin/$binary"
done

# Real Mango 0.18.5 mmsg JSON schema from src/ipc/ipc.c.
cat >"$tmp/bin/mmsg" <<'MOCK_MMSG'
#!/usr/bin/env bash
case "$*" in
    "get all-tags")
        printf '%s\n' '{"all_tags":[{"monitor":"DP-1","tags":[{"index":1,"is_active":true,"client_count":2},{"index":2,"is_active":false,"client_count":1},{"index":3,"is_active":false,"client_count":0}]}]}'
        ;;
    "get cursorpos")
        printf '%s\n' '{"monitor":"DP-1","x":40,"y":90}'
        ;;
    *)
        printf '{}\n'
        ;;
esac
MOCK_MMSG
chmod +x -- "$tmp/bin/mmsg"

# Verify executable behavior, not just JSON/parser syntax.
tags="$(PATH="$tmp/bin:$PATH" bash trials/mangowm/status-tags.sh)"
jq -e '.text == "[1] 2 ·" and .class == "mango-tags"' <<< "$tags" >/dev/null

# Dry run must be read-only. Install must preserve existing directory modes.
XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" \
    bash trials/mangowm/setup.sh --check >/dev/null
[[ ! -e "$tmp/config/mango/config.conf" ]]
XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" \
    bash trials/mangowm/setup.sh --install >/dev/null
cmp -s -- trials/mangowm/config.conf "$tmp/config/mango/config.conf"
cmp -s -- trials/mangowm/status-tags.sh "$tmp/config/mango/awtarchy-trial/status-tags.sh"
[[ "$(stat -c '%a' "$tmp/config/xdg-desktop-portal")" == 755 ]]

# An existing user's Mango config must stop all writes before they begin.
printf 'user=preserve\n' >"$tmp/conflict/mango/config.conf"
if XDG_CONFIG_HOME="$tmp/conflict" PATH="$tmp/bin:$PATH" \
    bash trials/mangowm/setup.sh --install >"$tmp/refusal.stdout" 2>"$tmp/refusal.stderr"; then
    printf 'FAIL: trial overwrote or accepted a conflicting Mango config\n' >&2
    exit 1
fi
grep -Fxq 'user=preserve' "$tmp/conflict/mango/config.conf"
[[ ! -e "$tmp/conflict/mango/awtarchy-trial/session.sh" ]]
[[ ! -e "$tmp/conflict/xdg-desktop-portal/mango-portals.conf" ]]
printf 'PASS: mock Mango IPC, no-write check, mode preservation, conflict refusal\n'
