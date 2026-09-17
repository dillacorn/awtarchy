#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOLVERS = [
    ROOT / "config/quickshell/awtarchy/LockscreenPresentationState.js",
    ROOT / "config/quickshell/awtarchy-lock/LockscreenPresentationState.js",
]
BACKEND = ROOT / "config/hypr/scripts/quickshell_application_state.sh"

for path in RESOLVERS:
    text = path.read_text(encoding="utf-8")
    old = '''function normalizeLayout(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    return ({
        logo: normalizedElement(raw.logo, 0.50, 0.34, 0),
        time: normalizedElement(raw.time, 0.50, 0.51, 0),
        date: normalizedElement(raw.date, 0.50, 0.555, 0),
        username: normalizedElement(raw.username, 0.50, 0.595, 0),
        weather: normalizedElement(raw.weather, 0.50, 0.635, 0),
        password: normalizedElement(raw.password, 0.50, 0.70, 20)
    });
}
'''
    new = '''function normalizeLayout(value) {
    const raw = value && typeof value === "object" && !Array.isArray(value) ? value : ({});
    const password = normalizedElement(raw.password, 0.50, 0.70, 20);
    password.x = clampNumber(password.x, 0.50, 0.15, 0.85);
    password.y = clampNumber(password.y, 0.70, 0.20, 0.86);
    return ({
        logo: normalizedElement(raw.logo, 0.50, 0.34, 0),
        time: normalizedElement(raw.time, 0.50, 0.51, 0),
        date: normalizedElement(raw.date, 0.50, 0.555, 0),
        username: normalizedElement(raw.username, 0.50, 0.595, 0),
        weather: normalizedElement(raw.weather, 0.50, 0.635, 0),
        password: password
    });
}
'''
    if old not in text:
        if new in text:
            continue
        raise SystemExit(f"normalizeLayout anchor missing in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

text = BACKEND.read_text(encoding="utf-8")
anchor = '''normalize_lockscreen_profile_json() {
    local value="$1" normalized wallpaper count index path resolved zone

'''
helper = r'''validate_lockscreen_profile_layout_section() {
    local value="$1"
    jq -e -n --argjson candidate "$value" '
        def layout_keys: ["logo", "time", "date", "username", "weather", "password"];
        def valid_color($value):
            ($value | type) == "string"
            and ($value == "auto" or ($value | test("^#[0-9A-Fa-f]{6}$")));
        def valid_transform($value; $password):
            ($value | type) == "object"
            and (($value | keys - ["color", "opacity", "rotation", "scale", "stretch_x", "stretch_y", "x", "y"] | length) == 0)
            and ($value.x | type) == "number"
            and ($value.y | type) == "number"
            and ($value.scale | type) == "number"
            and ($value.stretch_x | type) == "number"
            and ($value.stretch_y | type) == "number"
            and ($value.opacity | type) == "number"
            and ($value.rotation | type) == "number"
            and valid_color($value.color)
            and ($value.x >= (if $password then 0.15 else 0.05 end))
            and ($value.x <= (if $password then 0.85 else 0.95 end))
            and ($value.y >= (if $password then 0.20 else 0.08 end))
            and ($value.y <= (if $password then 0.86 else 0.92 end))
            and ($value.scale >= 0.5 and $value.scale <= 100)
            and ($value.stretch_x >= 0.25 and $value.stretch_x <= 4)
            and ($value.stretch_y >= 0.25 and $value.stretch_y <= 4)
            and ($value.opacity >= (if $password then 20 else 0 end) and $value.opacity <= 100)
            and ($value.rotation >= -180 and $value.rotation <= 180);
        ($candidate | type) == "object"
        and ($candidate.lockscreen_layout | type) == "object"
        and (($candidate.lockscreen_layout | keys | sort) == (layout_keys | sort))
        and all(layout_keys[]; . as $key | valid_transform($candidate.lockscreen_layout[$key]; $key == "password"))
    ' >/dev/null 2>&1
}

normalize_lockscreen_profile_json() {
    local value="$1" normalized wallpaper count index path resolved zone

    if ! validate_lockscreen_profile_layout_section "$value"; then
        printf 'invalid lockscreen profile: layout\n' >&2
        return 2
    fi

'''
if helper not in text:
    if anchor not in text:
        raise SystemExit("profile normalizer anchor missing")
    text = text.replace(anchor, helper, 1)

old_error = "        printf 'invalid lockscreen profile\\n' >&2\n        return 2\n"
new_error = "        printf 'invalid lockscreen profile: schema\\n' >&2\n        return 2\n"
if old_error in text:
    text = text.replace(old_error, new_error, 1)
elif new_error not in text:
    raise SystemExit("generic profile error anchor missing")

BACKEND.write_text(text, encoding="utf-8")
