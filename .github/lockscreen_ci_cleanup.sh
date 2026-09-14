#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

workflow='.github/workflows/validate-quickshell-lockscreen-editor-elements.yml'
history='local/share/awtarchy/quickshell-managed-history.sha256'

python3 - <<'PY'
from pathlib import Path

picker = Path('tests/test-quickshell-lockscreen-picker-targeting.sh')
text = picker.read_text(encoding='utf-8')
old = text
text = text.replace('lockscreenHeaderActions', 'lockscreenSectionActions')
text = text.replace(
    'label: root.lockscreenSectionExpanded ? "Collapse" : "Expand"',
    'label: root.lockscreenSectionOpen ? "Collapse Lockscreen" : "Expand Lockscreen"'
)
if text == old:
    raise SystemExit('picker contract patch made no change')
picker.write_text(text, encoding='utf-8')

editor = Path('tests/test-quickshell-lockscreen-editor.sh')
text = editor.read_text(encoding='utf-8')
old_block = '''# shellcheck disable=SC2016
require_text "$EDITOR_SAVE" 'bash "$STATE_BACKEND" save-lockscreen-editor "${@:1:19}"' \\
    'editor save wrapper no longer delegates the original atomic layout/visibility save'
'''
new_block = '''# shellcheck disable=SC2016
require_text "$EDITOR_SAVE" 'backend_args=("${@:1:19}")' \\
    'editor save wrapper no longer preserves the original 19-field backend save boundary'
# shellcheck disable=SC2016
require_text "$EDITOR_SAVE" 'bash "$STATE_BACKEND" save-lockscreen-editor "${backend_args[@]}"' \\
    'editor save wrapper no longer delegates the normalized atomic layout/visibility save'
'''
if old_block not in text:
    raise SystemExit('stale editor save-wrapper contract block not found exactly')
editor.write_text(text.replace(old_block, new_block, 1), encoding='utf-8')
PY

specs=(
  'config/hypr/scripts/quickshell_application_state.sh:.config/hypr/scripts/quickshell_application_state.sh'
  'config/hypr/scripts/quickshell_lockscreen_audio.sh:.config/hypr/scripts/quickshell_lockscreen_audio.sh'
  'config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh:.config/hypr/scripts/quickshell_lockscreen_wallpaper_picker.sh'
  'config/hypr/scripts/quickshell_lockscreen_weather.sh:.config/hypr/scripts/quickshell_lockscreen_weather.sh'
  'config/hypr/scripts/quickshell_lockscreen_contrast.sh:.config/hypr/scripts/quickshell_lockscreen_contrast.sh'
  'config/hypr/scripts/quickshell_lockscreen_preview_capture.sh:.config/hypr/scripts/quickshell_lockscreen_preview_capture.sh'
  'config/hypr/scripts/quickshell_lockscreen_editor_save.sh:.config/hypr/scripts/quickshell_lockscreen_editor_save.sh'
  'config/hypr/scripts/quickshell_lockscreen_timezones.sh:.config/hypr/scripts/quickshell_lockscreen_timezones.sh'
  'config/quickshell/awtarchy/shell.qml:.config/quickshell/awtarchy/shell.qml'
  'config/quickshell/awtarchy/BarState.qml:.config/quickshell/awtarchy/BarState.qml'
  'config/quickshell/awtarchy/QuickSettings.qml:.config/quickshell/awtarchy/QuickSettings.qml'
  'config/quickshell/awtarchy/LockscreenEditor.qml:.config/quickshell/awtarchy/LockscreenEditor.qml'
  'config/quickshell/awtarchy/LockscreenCompactSelector.qml:.config/quickshell/awtarchy/LockscreenCompactSelector.qml'
  'config/quickshell/awtarchy/LockPreviewScene.qml:.config/quickshell/awtarchy/LockPreviewScene.qml'
  'config/quickshell/awtarchy/LockPreviewTransitionLayer.qml:.config/quickshell/awtarchy/LockPreviewTransitionLayer.qml'
  'config/quickshell/awtarchy/LockPreviewWallpaperState.qml:.config/quickshell/awtarchy/LockPreviewWallpaperState.qml'
  'config/quickshell/awtarchy/LockscreenWeather.qml:.config/quickshell/awtarchy/LockscreenWeather.qml'
  'config/quickshell/awtarchy/LockscreenContrast.qml:.config/quickshell/awtarchy/LockscreenContrast.qml'
  'config/quickshell/awtarchy-lock/shell.qml:.config/quickshell/awtarchy-lock/shell.qml'
  'config/quickshell/awtarchy-lock/LockSurface.qml:.config/quickshell/awtarchy-lock/LockSurface.qml'
  'config/quickshell/awtarchy-lock/LockScene.qml:.config/quickshell/awtarchy-lock/LockScene.qml'
  'config/quickshell/awtarchy-lock/LockTransitionLayer.qml:.config/quickshell/awtarchy-lock/LockTransitionLayer.qml'
  'config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml:.config/quickshell/awtarchy-lock/LockAudioAnalyzer.qml'
  'config/quickshell/awtarchy-lock/LockWeatherCache.qml:.config/quickshell/awtarchy-lock/LockWeatherCache.qml'
  'config/quickshell/awtarchy-lock/LockWallpaperState.qml:.config/quickshell/awtarchy-lock/LockWallpaperState.qml'
  'config/quickshell/awtarchy-lock/LockContrastCache.qml:.config/quickshell/awtarchy-lock/LockContrastCache.qml'
  'config/quickshell/awtarchy-lock/cava.conf:.config/quickshell/awtarchy-lock/cava.conf'
)

missing=()
for spec in "${specs[@]}"; do
  source_path="${spec%%:*}"
  installed_path="${spec#*:}"
  [[ -f "$source_path" ]] || continue
  digest="$(sha256sum "$source_path" | awk '{print $1}')"
  entry="${digest}"$'\t'"${installed_path}"
  if ! grep -Fqx -- "$entry" "$history"; then
    missing+=("$entry")
  fi
done

if (( ${#missing[@]} > 0 )); then
  {
    printf '\n# 2026-09-14 lockscreen editor elements and Quick Settings alignment current stock hashes.\n'
    printf '%s\n' "${missing[@]}"
  } >>"$history"
fi

git show HEAD^^^:"$workflow" >"$workflow"
rm -f -- .github/lockscreen_ci_cleanup.sh

bash -n tests/test-quickshell-lockscreen-picker-targeting.sh
bash -n tests/test-quickshell-lockscreen-editor.sh
shellcheck tests/test-quickshell-lockscreen-picker-targeting.sh
shellcheck tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-quicksettings-header.sh
bash tests/test-quickshell-lockscreen-picker-targeting.sh
bash tests/test-quickshell-lockscreen-editor.sh
bash tests/test-quickshell-lockscreen-interactive-managed-history.sh
bash tests/test-quick-settings-layout.sh
cmp -s config/quickshell/awtarchy-lock/LockScene.qml config/quickshell/awtarchy/LockPreviewScene.qml
git diff --check
