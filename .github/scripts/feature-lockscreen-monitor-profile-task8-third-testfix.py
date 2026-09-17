#!/usr/bin/env python3
from pathlib import Path

path = Path("tests/test-quickshell-lockscreen-third-runtime-pass.sh")
text = path.read_text()
old = '''contains "$EDITOR" 'String(draftLastBackgroundOpacity)' \\
    'editor does not persist the reversible Opaque metadata with the existing save path'
contains "$STATE" '6|12|13|14|16|17|18|19|20) ;;' \\
    'save-lockscreen-editor dispatcher rejects the current 19-value editor payload'
'''
new = '''contains "$EDITOR" 'lockscreen_background_opacity_previous: draftLastBackgroundOpacity' \\
    'editor profile snapshot does not retain reversible Opaque metadata'
contains "$EDITOR" 'saveProcess.exec(["bash", editorSaveBackend, "--profiles",' \\
    'editor does not save reversible Opaque metadata through the atomic profile path'
contains "$STATE" 'save-lockscreen-editor-profiles)' \\
    'state backend does not expose the atomic Shared/monitor profile save dispatcher'
contains "$STATE" 'save_lockscreen_editor_profiles "$2" "$3"' \\
    'atomic profile dispatcher does not persist both Shared and monitor profiles'
'''
if old not in text:
    raise SystemExit("third-runtime-pass legacy Opaque save block not found")
path.write_text(text.replace(old, new, 1))
