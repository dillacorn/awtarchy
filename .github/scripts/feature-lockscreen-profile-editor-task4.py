#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "config/hypr/scripts/quickshell_application_state.sh"
SAVE = ROOT / "config/hypr/scripts/quickshell_lockscreen_editor_save.sh"
BAR = ROOT / "config/quickshell/awtarchy/BarState.qml"
EDITOR = ROOT / "config/quickshell/awtarchy/LockscreenEditor.qml"


def replace_once(text, old, new, label):
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Atomic application-state persistence.
text = STATE.read_text(encoding="utf-8")
text = replace_once(
    text,
    'LOCKSCREEN_CUSTOM_IMAGE_MAX=12\n',
    'LOCKSCREEN_CUSTOM_IMAGE_MAX=12\nLOCKSCREEN_SAVED_PROFILE_MAX=32\n',
    'saved profile maximum',
)

save_anchor = '''save_lockscreen_editor_profiles() {
    local shared overrides
    shared="$(normalize_lockscreen_profile_json "$1")" || return $?
    overrides="$(normalize_lockscreen_monitor_overrides_json "$2")" || return $?

    new_tmp
    jq --argjson shared "$shared" --argjson overrides "$overrides" '
        . + $shared
        | .lockscreen_monitor_overrides = $overrides
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
'''
save_replacement = r'''normalize_lockscreen_saved_profiles_json() {
    local value="$1" candidate count index entry profile normalized result='[]'

    if ! candidate="$(jq -ce -n \
        --argjson candidate "$value" \
        --argjson maximum "$LOCKSCREEN_SAVED_PROFILE_MAX" '
        def valid_name($value):
            ($value | type) == "string"
            and ($value | explode | length) >= 1
            and ($value | explode | length) <= 64
            and ($value | test("[^[:space:]]"))
            and ($value | test("[[:cntrl:]]") | not);
        if
            ($candidate | type) == "array"
            and ($candidate | length) <= $maximum
            and all($candidate[];
                (. | type) == "object"
                and ((. | keys | sort) == (["id", "name", "profile"] | sort))
                and (.id | type) == "string"
                and (.id | test("^profile-[A-Za-z0-9_-]{1,64}$"))
                and valid_name(.name)
                and (.profile | type) == "object")
            and ([ $candidate[].id ] | length) == ([ $candidate[].id ] | unique | length)
            and ([ $candidate[].name | ascii_downcase ] | length)
                == ([ $candidate[].name | ascii_downcase ] | unique | length)
        then $candidate else error("invalid saved lockscreen profiles") end
    ' 2>/dev/null)"; then
        printf 'invalid saved lockscreen profiles\n' >&2
        return 2
    fi

    count="$(jq -r 'length' <<<"$candidate")"
    for ((index = 0; index < count; ++index)); do
        entry="$(jq -c --argjson index "$index" '.[$index]' <<<"$candidate")"
        profile="$(jq -c '.profile' <<<"$entry")"
        normalized="$(normalize_lockscreen_profile_json "$profile")" || return $?
        entry="$(jq -c --argjson profile "$normalized" '.profile = $profile' <<<"$entry")"
        result="$(jq -c --argjson entry "$entry" '. + [$entry]' <<<"$result")"
    done

    printf '%s' "$result"
}

save_lockscreen_editor_profiles() {
    local shared overrides saved_profiles=''
    local has_saved_profiles=false
    shared="$(normalize_lockscreen_profile_json "$1")" || return $?
    overrides="$(normalize_lockscreen_monitor_overrides_json "$2")" || return $?
    if (( $# >= 3 )); then
        saved_profiles="$(normalize_lockscreen_saved_profiles_json "$3")" || return $?
        has_saved_profiles=true
    fi

    new_tmp
    if [[ "$has_saved_profiles" == true ]]; then
        jq --argjson shared "$shared" --argjson overrides "$overrides" \
            --argjson saved_profiles "$saved_profiles" '
            . + $shared
            | .lockscreen_monitor_overrides = $overrides
            | .lockscreen_saved_profiles = $saved_profiles
        ' "$STATE_FILE" >"$TMP_FILE"
    else
        jq --argjson shared "$shared" --argjson overrides "$overrides" '
            . + $shared
            | .lockscreen_monitor_overrides = $overrides
        ' "$STATE_FILE" >"$TMP_FILE"
    fi
    commit_tmp
}
'''.replace('\\"', '"')
text = replace_once(text, save_anchor, save_replacement, 'profile save function')

old_dispatch = '''    save-lockscreen-editor-profiles)
        [[ $# -eq 3 ]] || exit 2
        save_lockscreen_editor_profiles "$2" "$3"
        ;;
'''
new_dispatch = '''    save-lockscreen-editor-profiles)
        case "$#" in
            3) save_lockscreen_editor_profiles "$2" "$3" ;;
            4) save_lockscreen_editor_profiles "$2" "$3" "$4" ;;
            *) exit 2 ;;
        esac
        ;;
'''
text = replace_once(text, old_dispatch, new_dispatch, 'profile save dispatch')
STATE.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# Editor-save resource repair + compatibility wrapper.
text = SAVE.read_text(encoding="utf-8")
old_mode = '''if [[ "${1:-}" == "--profiles" ]]; then
    [[ $# -eq 3 ]] || {
        printf 'usage: %s --profiles <shared-profile-json> <monitor-overrides-json>\\n' "${0##*/}" >&2
        false
    }
    profile_mode=true
'''
new_mode = '''if [[ "${1:-}" == "--profiles" ]]; then
    [[ $# -eq 3 || $# -eq 4 ]] || {
        printf 'usage: %s --profiles <shared-profile-json> <monitor-overrides-json> [saved-profiles-json]\\n' "${0##*/}" >&2
        false
    }
    profile_mode=true
'''
text = replace_once(text, old_mode, new_mode, 'wrapper profile mode arity')

profile_mode_anchor = '''if [[ "$profile_mode" == true ]]; then
    shared_profile="$(repair_profile_optional_resources "$2")"
    monitor_overrides="$(repair_override_profiles "$3")"
    bash "$STATE_BACKEND" save-lockscreen-editor-profiles "$shared_profile" "$monitor_overrides"
    printf '%s\\n' '{"ok":true}'
    exit 0
fi
'''
profile_mode_replacement = r'''repair_saved_profiles() {
    local value="$1" candidate result='[]' count index entry profile repaired
    if ! candidate="$(jq -ce 'if type == "array" then . else empty end' <<<"$value" 2>/dev/null)"; then
        printf '%s' "$value"
        return 0
    fi

    count="$(jq -r 'length' <<<"$candidate")"
    for ((index = 0; index < count; ++index)); do
        entry="$(jq -c --argjson index "$index" '.[$index]' <<<"$candidate")"
        if jq -e 'type == "object" and (.profile | type) == "object"' >/dev/null 2>&1 <<<"$entry"; then
            profile="$(jq -c '.profile' <<<"$entry")"
            repaired="$(repair_profile_optional_resources "$profile")"
            if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$repaired"; then
                entry="$(jq -c --argjson profile "$repaired" '.profile = $profile' <<<"$entry")"
            fi
        fi
        result="$(jq -c --argjson entry "$entry" '. + [$entry]' <<<"$result")"
    done
    printf '%s' "$result"
}

if [[ "$profile_mode" == true ]]; then
    shared_profile="$(repair_profile_optional_resources "$2")"
    monitor_overrides="$(repair_override_profiles "$3")"
    if [[ $# -eq 4 ]]; then
        saved_profiles="$(repair_saved_profiles "$4")"
        bash "$STATE_BACKEND" save-lockscreen-editor-profiles \
            "$shared_profile" "$monitor_overrides" "$saved_profiles"
    else
        bash "$STATE_BACKEND" save-lockscreen-editor-profiles "$shared_profile" "$monitor_overrides"
    fi
    printf '%s\n' '{"ok":true}'
    exit 0
fi
'''.replace('\\"', '"')
text = replace_once(text, profile_mode_anchor, profile_mode_replacement, 'wrapper saved profiles')
SAVE.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# BarState facade.
text = BAR.read_text(encoding="utf-8")
text = replace_once(
    text,
    '            lockscreen_monitor_overrides: {},\n',
    '            lockscreen_monitor_overrides: {},\n            lockscreen_saved_profiles: [],\n',
    'BarState saved profile default',
)

facade_anchor = '''    function lockscreenProfileForMonitor(name) {
        return LockscreenPresentationState.profileForMonitor(
            lockscreenSharedProfile(), lockscreenMonitorOverrides(), String(name || ""));
    }

'''
facade_replacement = r'''    function lockscreenProfileForMonitor(name) {
        return LockscreenPresentationState.profileForMonitor(
            lockscreenSharedProfile(), lockscreenMonitorOverrides(), String(name || ""));
    }

    function lockscreenSavedProfiles() {
        const dependency = revision;
        const value = data().lockscreen_saved_profiles;
        if (!Array.isArray(value) || value.length > 32)
            return [];
        const result = [];
        const ids = ({});
        const names = ({});
        for (const raw of value) {
            if (!raw || typeof raw !== "object" || Array.isArray(raw))
                return [];
            const id = String(raw.id || "");
            const name = String(raw.name || "");
            const points = Array.from(name);
            const nameKey = name.toLowerCase();
            if (!/^profile-[A-Za-z0-9_-]{1,64}$/.test(id) || ids[id]
                    || points.length < 1 || points.length > 64 || name.trim().length === 0
                    || /[\u0000-\u001f\u007f-\u009f]/.test(name) || names[nameKey]
                    || !raw.profile || typeof raw.profile !== "object" || Array.isArray(raw.profile))
                return [];
            ids[id] = true;
            names[nameKey] = true;
            result.push(({
                id: id,
                name: name,
                profile: LockscreenPresentationState.cloneProfile(raw.profile)
            }));
        }
        return result;
    }

'''.replace('\\"', '"')
text = replace_once(text, facade_anchor, facade_replacement, 'BarState saved profile facade')
BAR.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# Editor session draft and atomic Ctrl+S payload.
text = EDITOR.read_text(encoding="utf-8")
text = replace_once(
    text,
    '    property var draftMonitorOverrides: ({})\n',
    '    property var draftMonitorOverrides: ({})\n    property var draftSavedProfiles: []\n',
    'editor saved profile draft',
)

load_anchor = '''        const shared = BarState.lockscreenSharedProfile();
        const overrides = BarState.lockscreenMonitorOverrides();
        draftSharedProfile = cloneSnapshot(shared) || ({});
'''
load_replacement = '''        const shared = BarState.lockscreenSharedProfile();
        const overrides = BarState.lockscreenMonitorOverrides();
        const savedProfiles = BarState.lockscreenSavedProfiles();
        draftSavedProfiles = cloneSnapshot(savedProfiles) || [];
        draftSharedProfile = cloneSnapshot(shared) || ({});
'''
text = replace_once(text, load_anchor, load_replacement, 'editor saved profile load')

save_payload = '''        saveProcess.exec(["bash", editorSaveBackend, "--profiles",
            JSON.stringify(draftSharedProfile), JSON.stringify(draftMonitorOverrides)]);
'''
save_payload_replacement = '''        saveProcess.exec(["bash", editorSaveBackend, "--profiles",
            JSON.stringify(draftSharedProfile), JSON.stringify(draftMonitorOverrides),
            JSON.stringify(draftSavedProfiles)]);
'''
text = replace_once(text, save_payload, save_payload_replacement, 'editor saved profile save payload')
EDITOR.write_text(text, encoding="utf-8")
