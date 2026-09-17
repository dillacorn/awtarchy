#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
RESOLVER="$ROOT/config/quickshell/awtarchy/LockscreenPresentationState.js"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME" "$XDG_CACHE_HOME/awtarchy" "$XDG_CONFIG_HOME"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{}}' >"$XDG_CACHE_HOME/awtarchy/quickshell-state.json"

media="$TMP/media.png"
: >"$media"

profile="$(node - "$RESOLVER" "$media" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const file = process.argv[2];
const media = process.argv[3];
const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma library\s*/m, '');
const context = {};
vm.createContext(context);
vm.runInContext(source, context, { filename: file });
const profile = context.sharedProfile({
  lockscreen_layout: {
    password: {
      x: 0.94,
      y: 0.91,
      scale: 1,
      stretch_x: 1,
      stretch_y: 1,
      opacity: 5,
      rotation: 0,
      color: 'auto'
    }
  },
  lockscreen_custom_images: [{
    id: 'image-roundtrip',
    path: media,
    x: 0.5,
    y: 0.5,
    scale: 1,
    stretch_x: 1,
    stretch_y: 1,
    opacity: 100,
    rotation: 0,
    spawn_animation: 'none',
    spawn_timing: 'during-logo',
    visible: true
  }],
  lockscreen_background_opacity: 50.4,
  lockscreen_background_opacity_previous: 70.7,
  lockscreen_overlay_strength: 12.6,
  lockscreen_wallpaper_blur: 19.7,
  lockscreen_entry_transition_duration: 1799.6
});
process.stdout.write(JSON.stringify(profile));
NODE
)"

if ! bash "$BACKEND" save-lockscreen-editor-profiles "$profile" '{}' 2>"$TMP/profile-error"; then
    cat "$TMP/profile-error" >&2
    jq '.' <<<"$profile" >&2
    exit 2
fi

saved="$XDG_CACHE_HOME/awtarchy/quickshell-state.json"
jq -e '
  .lockscreen_layout.password.x == 0.85
  and .lockscreen_layout.password.y == 0.86
  and .lockscreen_layout.password.opacity == 20
  and .lockscreen_background_opacity == 50
  and .lockscreen_background_opacity_previous == 71
  and .lockscreen_overlay_strength == 13
  and .lockscreen_wallpaper_blur == 20
  and .lockscreen_entry_transition_duration == 1800
  and (.lockscreen_custom_images | length) == 1
  and .lockscreen_custom_images[0].id == "image-roundtrip"
  and (.lockscreen_custom_images[0] | has("color") | not)
' "$saved" >/dev/null

invalid_layout="$(jq -c '.lockscreen_layout.password.opacity = 0' <<<"$profile")"
if bash "$BACKEND" save-lockscreen-editor-profiles "$invalid_layout" '{}' 2>"$TMP/error"; then
    printf '%s\n' 'FAIL: invalid layout profile unexpectedly saved' >&2
    exit 1
fi
grep -Fq 'invalid lockscreen profile: layout' "$TMP/error" || {
    printf '%s\n' 'FAIL: invalid layout did not identify the failing profile section' >&2
    cat "$TMP/error" >&2
    exit 1
}

printf '%s\n' 'PASS: resolver-normalized lockscreen profiles are backend-saveable'
