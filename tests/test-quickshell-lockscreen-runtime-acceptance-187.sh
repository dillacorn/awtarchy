#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
BAR_STATE="$ROOT/config/quickshell/awtarchy/BarState.qml"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
QUICK_SETTINGS="$ROOT/config/quickshell/awtarchy/QuickSettings.qml"
SCENE="$ROOT/config/quickshell/awtarchy-lock/LockScene.qml"
PREVIEW_SCENE="$ROOT/config/quickshell/awtarchy/LockPreviewScene.qml"
SURFACE="$ROOT/config/quickshell/awtarchy-lock/LockSurface.qml"
SHELL="$ROOT/config/quickshell/awtarchy-lock/shell.qml"
LAYER="$ROOT/config/quickshell/awtarchy-lock/LockTransitionLayer.qml"
AUTH="$ROOT/config/quickshell/awtarchy-lock/LockAuth.qml"
ANALYZER="$ROOT/config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml"
PREVIEW_ANALYZER="$ROOT/config/quickshell/awtarchy/LockPreviewAudioAnalyzer.qml"
AUDIO_HELPER="$ROOT/config/hypr/scripts/quickshell_lockscreen_audio.sh"
CAVA_CONFIG="$ROOT/config/quickshell/awtarchy-lock/cava.conf"
PICKER="$ROOT/config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has() { grep -Fq -- "$2" "$1" || fail "$3"; }
lacks() { ! grep -Fq -- "$2" "$1" || fail "$3"; }

# Transition duration is persisted once, passed only through presentation, and
# delays logo formation until the shared desktop-to-lockscreen reveal completes.
has "$STATE" 'lockscreen_entry_transition_duration' 'transition duration is not persisted'
has "$STATE" '1800' 'approved 1800ms transition duration default is missing'
has "$STATE" '800 6000' 'approved 800-6000ms transition duration range is missing'
has "$BAR_STATE" 'function lockscreenEntryTransitionDuration()' 'BarState duration reader is missing'
has "$EDITOR" 'property int draftEntryTransitionDuration: 1800' 'editor duration draft is not 1800ms'
has "$EDITOR" 'text: "Transition Speed"' 'editor duration control is missing'
has "$SURFACE" 'required property int entryTransitionDuration' 'secure surface duration input is missing'
has "$SHELL" 'entryTransitionDuration: root.lockEntryTransitionDuration' 'secure shell does not pass duration'
has "$LAYER" 'Math.max(800, Math.min(6000' 'shared renderer does not enforce transition duration bounds'
has "$SCENE" '&& !root.effectiveEntryTransitionRunning' 'logo formation is not sequenced after the active scene reveal'
lacks "$AUTH" 'entryTransitionDuration' 'transition duration leaked into authentication owner'

# One bounded simulation owns smooth coherent hover targets, explosion impulse,
# collision response, and damped spring return. No connector/bridge line returns.
has "$SCENE" 'function logoHoverTarget(row, column)' 'coherent logo hover field is missing'
has "$SCENE" 'function ensureLogoParticle(row, column)' 'hover and explosion do not share particle state'
has "$SCENE" 'readonly property bool logoHoverActive: mouseInteractive && pointerActive' 'hover does not expire with pointer activity'
has "$SCENE" 'logoHoverDirty = wasLogoHovering || logoContainsPoint(x, y)' 'off-logo motion still wakes the particle solver'
has "$SCENE" 'running: root.logoSimulationActive' 'logo solver is not active-only'
has "$SCENE" 'hoverTarget.x' 'logo solver does not consume coherent hover targets'
has "$SCENE" 'resolveLogoCollisions()' 'bounded collision response is missing'
has "$SCENE" 'function bounceLogoParticleAtBounds(particle)' 'outer bounds do not return particle velocity'
lacks "$SCENE" 'ShapePath' 'connector-line path returned to logo effect'

# CAVA owns the selected production cadence; QML displays each parsed frame
# directly instead of adding a second slow interpolation loop.
has "$STATE" 'performance' 'visualizer performance mode is not persisted'
has "$STATE" '"balanced"' 'balanced visualizer mode is missing'
has "$STATE" '"responsive"' 'responsive visualizer mode is missing'
has "$AUDIO_HELPER" 'balanced) framerate=60' 'balanced CAVA rate is not 60 Hz'
has "$AUDIO_HELPER" 'responsive) framerate=90' 'responsive CAVA rate is not 90 Hz'
has "$AUDIO_HELPER" 'mkdir -p -- "$runtime_home"' 'CAVA runtime config directory is not prepared'
has "$ANALYZER" 'bands = normalizedSpectrum(values);' 'analyzer does not publish parsed frames directly'
has "$ANALYZER" 'onPerformanceModeChanged: root.restartAnalyzer()' 'live performance-mode changes do not restart CAVA'
lacks "$ANALYZER" 'smoothingTimer' 'retired QML smoothing timer remains'
lacks "$ANALYZER" 'function smoothed' 'retired QML interpolation remains'
has "$CAVA_CONFIG" 'noise_reduction = 35' 'CAVA responsiveness tuning is missing'
cmp -s "$ANALYZER" "$PREVIEW_ANALYZER" || fail 'secure/editor analyzer paths diverged'

# Detailed background controls live in the editor, stay usable for every mode,
# and use direct pointer-driven slider tracks. The first transparency adjustment
# seeds blur only until the user has explicitly chosen a blur value.
has "$EDITOR" 'text: "Brightness"' 'editor brightness slider is missing'
has "$EDITOR" 'function setDraftBrightness(value)' 'direct brightness adjustment is missing'
has "$EDITOR" 'function setBackgroundOpacityFromPointer(pointerX, trackWidth)' 'opacity pointer slider is missing'
has "$EDITOR" 'if (draftBackgroundOpacity === 100 && next < 100 && draftWallpaperBlur === 0' 'first transparency adjustment does not seed blur'
has "$EDITOR" '&& !draftWallpaperBlurExplicit)' 'explicit blur choice is not respected by opacity seeding'
lacks "$EDITOR" 'enabled: root.draftBackgroundMode === "wallpaper"' 'blur remains wallpaper-gated'
lacks "$QUICK_SETTINGS" 'text: "Background Opacity"' 'detailed opacity still duplicated in Quick Settings'
has "$SURFACE" 'id: desktopCaptureBlur' 'blur is not applied to the secure frozen desktop backing'

# Delete removes only a selected custom image through the existing undo path;
# all elements share one high defensive scale ceiling instead of a 200% UX cap.
has "$EDITOR" 'event.key === Qt.Key_Delete' 'Delete key is not routed in editor'
has "$EDITOR" 'root.removeCustomImage(root.selectedElement)' 'Delete does not use safe image removal'
has "$EDITOR" 'readonly property real elementScaleMaximum: 100.0' 'common scale safety bound is missing'
has "$STATE" '.scale <= 100.00' 'persisted custom images do not use the common scale bound'
has "$BAR_STATE" 'scale > 100.00' 'BarState does not use the common scale bound'
has "$SCENE" 'const maximum = 100.00;' 'renderer still uses a visible 200%/10x ceiling'

# Production picker owns an exact identity and has a Hyprland fallback in
# addition to Alacritty's startup request. The stricter mapped-address behavior
# is covered by the dedicated picker task before the runtime candidate is cut.
has "$PICKER" '--title Awtarchy-Lockscreen-Wallpaper' 'picker title is not stable'
has "$PICKER" 'window.startup_mode=Fullscreen' 'Alacritty fullscreen request is missing'
has "$PICKER" 'hyprctl dispatch fullscreen 1' 'Hyprland fullscreen fallback is missing'
has "$PICKER" '--select-only --type images' 'picker no longer uses selection-only mode'

picker_tmp="$(mktemp -d)"
trap 'rm -rf -- "$picker_tmp"' EXIT
mkdir -p "$picker_tmp/bin" "$picker_tmp/cache" "$picker_tmp/home"
selected_image="$picker_tmp/selected image.png"
printf 'fixture\n' >"$selected_image"
cat >"$picker_tmp/bin/awtwall" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then printf '%s\n' '--select-only'; fi
EOF
cat >"$picker_tmp/bin/alacritty" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$PICKER_TERMINAL_LOG"
while (( $# )); do
    if [[ "$1" == --select-result ]]; then
        printf '%s\n' "$PICKER_SELECTED_IMAGE" >"$2"
        break
    fi
    shift
done
EOF
cat >"$picker_tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == clients && "${2:-}" == -j ]]; then
    printf '%s\n' '[{"class":"awtarchy-lock-wallpaper","title":"Awtarchy-Lockscreen-Wallpaper"}]'
else
    printf '%s\n' "$*" >>"$PICKER_HYPR_LOG"
fi
EOF
chmod +x "$picker_tmp/bin/awtwall" "$picker_tmp/bin/alacritty" "$picker_tmp/bin/hyprctl"
picker_output="$(
    PATH="$picker_tmp/bin:$PATH" \
    HOME="$picker_tmp/home" \
    XDG_CACHE_HOME="$picker_tmp/cache" \
    AWTWALL_CMD="$picker_tmp/bin/awtwall" \
    LOCKSCREEN_WALLPAPER_TERMINAL="$picker_tmp/bin/alacritty" \
    PICKER_TERMINAL_LOG="$picker_tmp/terminal.log" \
    PICKER_HYPR_LOG="$picker_tmp/hypr.log" \
    PICKER_SELECTED_IMAGE="$selected_image" \
    bash "$PICKER"
)"
[[ "$picker_output" == "$selected_image" ]] || fail 'picker did not return the selected absolute path'
has "$picker_tmp/terminal.log" '--option window.startup_mode=Fullscreen' 'picker omitted Alacritty fullscreen startup mode'
has "$picker_tmp/terminal.log" '--class awtarchy-lock-wallpaper --title Awtarchy-Lockscreen-Wallpaper' 'picker terminal identity drifted'
has "$picker_tmp/hypr.log" 'dispatch focuswindow class:^(awtarchy-lock-wallpaper)$' 'picker did not focus its exact Hyprland class'
has "$picker_tmp/hypr.log" 'dispatch fullscreen 1' 'picker did not request Hyprland fullscreen'

cmp -s "$SCENE" "$PREVIEW_SCENE" || fail 'secure/editor scene parity is broken'
lacks "$AUTH" 'audioBands' 'audio presentation leaked into authentication owner'
lacks "$AUTH" 'logoHover' 'pointer presentation leaked into authentication owner'

printf '%s\n' 'PASS: issue #187 lockscreen runtime acceptance contracts'