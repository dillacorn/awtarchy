#!/usr/bin/env bash
# Refuse non-KWin sessions without spawning either Quickshell or Foot.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
target="$root/trials/kwin/probe-session.sh"
bash -n "$target"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/qs" <<'EOF'
#!/usr/bin/env bash
printf 'qs should not have started\n' > "$PROBE_EVIDENCE"
EOF
cat > "$tmp/bin/foot" <<'EOF'
#!/usr/bin/env bash
printf 'foot should not have started\n' > "$PROBE_EVIDENCE"
EOF
chmod +x "$tmp/bin/qs" "$tmp/bin/foot"
if PROBE_EVIDENCE="$tmp/evidence" XDG_CURRENT_DESKTOP=Hyprland \
   XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=wayland-0 \
   PATH="$tmp/bin:$PATH" bash "$target" >"$tmp/out" 2>&1; then
    printf 'ERROR: accepted a non-KWin session\n' >&2
    false
fi
grep -Fq 'not an isolated Wayland test session' "$tmp/out"
[[ ! -e "$tmp/evidence" ]]
printf 'PASS: KWin probe refuses non-KWin sessions\n'
