#!/usr/bin/env bash
# Mango-native animation toggle. Defaults OFF like Awtarchy's trial config.
# State is scoped to one compositor instance, never shared with Hyprland.
set -euo pipefail

[[ "${XDG_CURRENT_DESKTOP:-}" == mango &&
   -n "${MANGO_INSTANCE_SIGNATURE:-}" &&
   -n "${WAYLAND_DISPLAY:-}" ]] || {
    printf 'Mango animations: active Mango session required\n' >&2
    exit 1
}
command -v mmsg >/dev/null 2>&1 || exit 1
command -v sha256sum >/dev/null 2>&1 || exit 1

runtime="${XDG_RUNTIME_DIR:-}"
[[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" &&
   -O "$runtime" ]] || {
    printf 'Mango animations: safe session runtime unavailable\n' >&2
    exit 1
}
key="$(printf '%s' "$MANGO_INSTANCE_SIGNATURE" | sha256sum)"
key="${key%% *}"
file="$runtime/awtarchy-mango-animations-${key:0:16}"
[[ ! -L "$file" ]] || {
    printf 'Mango animations: refusing linked state\n' >&2
    exit 1
}
state=0
if [[ -f "$file" && -O "$file" ]]; then
    IFS= read -r state <"$file" || state=0
fi
[[ "$state" == 0 || "$state" == 1 ]] || {
    printf 'Mango animations: invalid saved session state\n' >&2
    exit 1
}
if [[ "$state" == 0 ]]; then next=1; else next=0; fi
mmsg dispatch "setoption,animations,$next" >/dev/null || exit 1
# Never record a successful toggle when Mango declined the IPC call.
printf '%s\n' "$next" >"$file"
chmod 0600 "$file"
if command -v notify-send >/dev/null 2>&1; then
    if [[ "$next" == 1 ]]; then label=ON; else label=OFF; fi
    notify-send -a Mango -t 1000 "Animations: $label" >/dev/null 2>&1 || true
fi
