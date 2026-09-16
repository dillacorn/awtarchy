from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}: {old!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_exact(path: str, old: str, new: str, expected: int) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} replacement targets, found {count}: {old!r}")
    target.write_text(text.replace(old, new), encoding="utf-8")


helper = Path("config/hypr/scripts/quickshell_lockscreen_contrast.sh")
text = helper.read_text(encoding="utf-8")

old = '''TMP_FILE=""
OUTPUT_STDOUT=0
'''
new = '''TMP_FILE=""
TMP_DIR=""
WALLPAPER_SAMPLE=""
OUTPUT_STDOUT=0
'''
if text.count(old) != 1:
    raise SystemExit("contrast helper temporary-state anchor changed")
text = text.replace(old, new, 1)

old = '''cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
}
'''
new = '''cleanup() {
    [[ -z "$TMP_FILE" ]] || rm -f -- "$TMP_FILE"
    [[ -z "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"
}
'''
if text.count(old) != 1:
    raise SystemExit("contrast helper cleanup anchor changed")
text = text.replace(old, new, 1)

anchor = '''sample_wallpaper_contrast() {
'''
function = '''function prepare_wallpaper_sample() {
    local image="$1" output
    WALLPAPER_SAMPLE="$image"

    if [[ ! -f "$image" || ! -r "$image" ]]; then
        return 0
    fi

    case "${image,,}" in
        *.gif)
            command -v magick >/dev/null 2>&1 || return 0
            TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awtarchy-lock-contrast.XXXXXX")"
            output="${TMP_DIR}/wallpaper.png"
            if magick "${image}[0]" "$output" >/dev/null 2>&1; then
                WALLPAPER_SAMPLE="$output"
            fi
            ;;
        *.mp4)
            command -v ffmpeg >/dev/null 2>&1 || return 0
            TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/awtarchy-lock-contrast.XXXXXX")"
            output="${TMP_DIR}/wallpaper.png"
            if ffmpeg -v error -nostdin -i "$image" -map 0:v:0 -frames:v 1 -y "$output" >/dev/null 2>&1; then
                WALLPAPER_SAMPLE="$output"
            fi
            ;;
    esac
}

sample_wallpaper_contrast() {
'''
if text.count(anchor) != 1:
    raise SystemExit("contrast helper sampling function anchor changed")
text = text.replace(anchor, function, 1)

old = '''colors='{}'
for element in $ELEMENTS; do
'''
new = '''WALLPAPER_SAMPLE="$wallpaper"
if [[ "$background" == "wallpaper" ]]; then
    prepare_wallpaper_sample "$wallpaper"
fi

colors='{}'
for element in $ELEMENTS; do
'''
if text.count(old) != 1:
    raise SystemExit("contrast helper element-loop anchor changed")
text = text.replace(old, new, 1)

old = '''        wallpaper) color="$(sample_wallpaper_contrast "$wallpaper" "$layout" "$element")" ;;
'''
new = '''        wallpaper) color="$(sample_wallpaper_contrast "$WALLPAPER_SAMPLE" "$layout" "$element")" ;;
'''
if text.count(old) != 1:
    raise SystemExit("contrast helper wallpaper sampling call changed")
text = text.replace(old, new, 1)
helper.write_text(text, encoding="utf-8")

editor_path = Path("config/quickshell/awtarchy/LockscreenEditor.qml")
editor = str(editor_path)
replace_exact(editor, "Custom image limit reached (", "Custom media limit reached (", 2)
replace_exact(editor, "Opening custom image picker…", "Opening custom media picker…", 2)
replacements = [
    ("Custom image must be a local absolute path", "Custom media must be a local absolute path"),
    ("Image added. Save to apply.", "Media added. Save to apply."),
    ("Image removed. Save to apply.", "Media removed. Save to apply."),
    ("Awtwall returned an invalid local image", "Awtwall returned an invalid local media"),
    ("Custom image picker closed without a selection", "Custom media picker closed without a selection"),
    ("No image selected.", "No media selected."),
    ("Custom images are local presentation-only elements.", "Custom media are local presentation-only elements."),
    ('text: "Image Opacity"', 'text: "Media Opacity"'),
    ('label: "Add Image"', 'label: "Add Media"'),
    ('label: "Remove Image"', 'label: "Remove Media"'),
]
for old, new in replacements:
    replace_once(editor, old, new)

# Earlier branch-only patch replay could duplicate insertion-only editor lines
# because their anchors remain present inside the replacement. Normalize those
# additions here and keep a regression test requiring exact uniqueness.
text = editor_path.read_text(encoding="utf-8")
threshold = '    readonly property real dragActivationThresholdPx: 5\n'
save_shortcut = '    Shortcut { sequence: "Ctrl+S"; context: Qt.ApplicationShortcut; enabled: root.open && !root.pickerSuspended; autoRepeat: false; onActivated: root.save() }\n'
hint = '                        Text { text: "Ctrl+S Save  •  Esc Cancel"; color: Theme.muted; font.family: Theme.fontFamily; font.pixelSize: 8 }\n'
for line, label in ((threshold, "drag threshold"), (save_shortcut, "Ctrl+S shortcut"), (hint, "shortcut hint")):
    if line not in text:
        raise SystemExit(f"editor lost expected {label} before duplicate normalization")
    text = re.sub(r'(?:' + re.escape(line) + r')+', line, text)
editor_path.write_text(text, encoding="utf-8")

# Persisted/internal customImages naming remains unchanged for backward compatibility;
# only superseded user-facing test labels move to Media.
test = "tests/test-quickshell-lockscreen-element-system.sh"
replace_once(test, 'label: "Add Image"', 'label: "Add Media"')
replace_once(test, "editor has no local custom-image insertion action", "editor has no local custom-media insertion action")
replace_once(test, 'label: "Remove Image"', 'label: "Remove Media"')
replace_once(test, "editor has no custom-image removal action", "editor has no custom-media removal action")

contract = Path("tests/test-quickshell-lockscreen-media-editor-polish.sh")
contract_text = contract.read_text(encoding="utf-8")
anchor = '''require_text "$EDITOR" 'Esc Cancel' \\
    'editor does not advertise its cancel shortcut'\n'''
addition = anchor + '''[[ "$(grep -Fc -- 'readonly property real dragActivationThresholdPx: 5' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor drag activation threshold is declared more than once'\n[[ "$(grep -Fc -- 'sequence: \"Ctrl+S\"' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor Ctrl+S save shortcut is declared more than once'\n[[ "$(grep -Fc -- 'Ctrl+S Save  •  Esc Cancel' "$EDITOR")" -eq 1 ]] \\
    || fail 'editor shortcut hint is rendered more than once'\n'''
if addition not in contract_text:
    if contract_text.count(anchor) != 1:
        raise SystemExit("media/editor contract shortcut-hint anchor changed")
    contract_text = contract_text.replace(anchor, addition, 1)
contract.write_text(contract_text, encoding="utf-8")
