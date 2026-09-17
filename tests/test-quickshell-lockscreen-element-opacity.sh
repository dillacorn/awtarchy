#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/config/quickshell/awtarchy/LockscreenPresentationState.js"
BACKEND="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
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
const fs = require("fs");
const vm = require("vm");
const resolver = process.argv[2];
const media = process.argv[3];
const source = fs.readFileSync(resolver, "utf8").replace(/^\.pragma library\s*/m, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context, { filename: resolver });

const profile = context.cloneProfile({
  lockscreen_layout: {
    logo: { opacity: 0 },
    time: { opacity: 2 },
    password: { opacity: 1 },
  },
  lockscreen_show_logo: true,
  lockscreen_show_time: true,
  lockscreen_custom_images: [{
    id: "image-opacity",
    path: media,
    opacity: 0,
    visible: true,
  }],
  lockscreen_timezone_clocks: [{
    id: "timezone-opacity",
    timezone: "UTC",
    opacity: 0,
    visible: true,
  }],
  lockscreen_custom_texts: [{
    id: "text-opacity",
    text: "Opacity",
    opacity: 0,
    visible: true,
  }],
  lockscreen_visualizer: {
    enabled: true,
    opacity: 0,
  },
  lockscreen_background_opacity: 0,
});

const checks = [
  [profile.lockscreen_show_logo === false, "zero-opacity built-in was not migrated to hidden"],
  [profile.lockscreen_layout.logo.opacity >= 5, "hidden built-in retained opacity below 5"],
  [profile.lockscreen_show_time === true, "1-4% built-in was incorrectly hidden"],
  [profile.lockscreen_layout.time.opacity === 5, "1-4% built-in was not clamped to 5"],
  [profile.lockscreen_layout.password.opacity === 5, "password opacity minimum is not 5"],
  [profile.lockscreen_custom_images[0].visible === false, "zero-opacity media was not migrated to hidden"],
  [profile.lockscreen_custom_images[0].opacity >= 5, "media retained opacity below 5"],
  [profile.lockscreen_timezone_clocks[0].visible === false, "zero-opacity timezone clock was not hidden"],
  [profile.lockscreen_timezone_clocks[0].opacity >= 5, "timezone clock retained opacity below 5"],
  [profile.lockscreen_custom_texts[0].visible === false, "zero-opacity custom text was not hidden"],
  [profile.lockscreen_custom_texts[0].opacity >= 5, "custom text retained opacity below 5"],
  [profile.lockscreen_visualizer.enabled === false, "zero-opacity visualizer was not disabled"],
  [profile.lockscreen_visualizer.opacity >= 5, "visualizer retained opacity below 5"],
  [profile.lockscreen_background_opacity === 0, "background opacity was incorrectly clamped to 5"],
];
for (const [ok, message] of checks) {
  if (!ok) {
    console.error("FAIL: " + message);
    process.exit(1);
  }
}
process.stdout.write(JSON.stringify(profile));
NODE
)"

profiles="$(jq -cn --argjson profile "$profile" '{"DP-1":$profile}')"
bash "$BACKEND" save-lockscreen-editor-profiles "$profiles" "$profile"

invalid="$(jq -c '.lockscreen_layout.time.opacity = 4 | .lockscreen_show_time = true' <<<"$profile")"
invalid_profiles="$(jq -cn --argjson profile "$invalid" '{"DP-1":$profile}')"
if bash "$BACKEND" save-lockscreen-editor-profiles "$invalid_profiles" "$profile" >/dev/null 2>&1; then
    printf '%s\n' 'FAIL: backend accepted visible element opacity below 5' >&2
    exit 1
fi

printf '%s\n' 'PASS: visible lockscreen element opacity is constrained to 5-100'
