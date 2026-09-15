#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_capture.sh"
LOCK_MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"
POWER_MENU="${ROOT}/config/hypr/scripts/quickshell_power_menu.sh"
MAIN_SHELL="${ROOT}/config/quickshell/awtarchy/shell.qml"
EDITOR="${ROOT}/config/quickshell/awtarchy/LockscreenEditor.qml"
SURFACE="${ROOT}/config/quickshell/awtarchy-lock/LockSurface.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

require_text() {
    local file="$1" text="$2" message="$3"
    grep -Fq -- "$text" "$file" || fail "$message"
}

forbid_text() {
    local file="$1" text="$2" message="$3"
    if grep -Fq -- "$text" "$file"; then
        fail "$message"
    fi
}

require_order() {
    local file="$1" first="$2" second="$3" message="$4"
    local first_line second_line
    first_line="$(grep -nF -- "$first" "$file" | head -n1 | cut -d: -f1 || true)"
    second_line="$(grep -nF -- "$second" "$file" | head -n1 | cut -d: -f1 || true)"
    [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] \
        || fail "$message"
}

mode_of() {
    stat -c '%a' -- "$1"
}

[[ -f "$HELPER" ]] || fail 'secure pre-lock capture helper is missing'
bash -n "$HELPER" || fail 'capture helper has invalid Bash syntax'

mkdir -p "$TMP/runtime" "$TMP/bin"
chmod 700 "$TMP/runtime"
printf '%s\n' '[{"name":"DP-1"},{"name":"HDMI-A-1"}]' >"$TMP/monitors.json"

cat >"$TMP/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == monitors && "${2:-}" == -j ]] || exit 2
cat -- "$FAKE_MONITORS"
SH
chmod +x "$TMP/bin/hyprctl"

cat >"$TMP/bin/grim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
destination=""
while (($#)); do
    case "$1" in
        -l)
            shift 2
            ;;
        -o)
            output="${2:-}"
            shift 2
            ;;
        *)
            destination="$1"
            shift
            ;;
    esac
done
[[ -n "$output" && -n "$destination" ]] || exit 2
if [[ -n "${FAIL_GRIM_OUTPUT:-}" && "$output" == "$FAIL_GRIM_OUTPUT" ]]; then
    exit 7
fi
printf 'PNG:%s\n' "$output" >"$destination"
SH
chmod +x "$TMP/bin/grim"

run_prepare() {
    PATH="$TMP/bin:$PATH" \
    XDG_RUNTIME_DIR="$TMP/runtime" \
    FAKE_MONITORS="$TMP/monitors.json" \
        bash "$HELPER" prepare
}

run_stage_begin() {
    PATH="$TMP/bin:$PATH" \
    XDG_RUNTIME_DIR="$TMP/runtime" \
    FAKE_MONITORS="$TMP/monitors.json" \
        bash "$HELPER" stage-begin
}

capture_dir="$(run_prepare)" || fail 'capture helper failed with two valid outputs'
case "$capture_dir" in
    "$TMP/runtime/awtarchy-lock-transition"/capture.*) ;;
    *) fail 'capture helper returned a directory outside the dedicated runtime root' ;;
esac

[[ "$(mode_of "$TMP/runtime/awtarchy-lock-transition")" == 700 ]] \
    || fail 'capture root is not mode 0700'
[[ "$(mode_of "$capture_dir")" == 700 ]] \
    || fail 'capture directory is not mode 0700'
for output in DP-1 HDMI-A-1; do
    file="$capture_dir/$output.png"
    transition_file="$capture_dir/$output.transition.png"
    [[ -f "$file" && ! -L "$file" && -O "$file" && -s "$file" ]] \
        || fail "capture for $output is not a valid owned regular file"
    [[ "$(mode_of "$file")" == 600 ]] \
        || fail "capture for $output is not mode 0600"
    grep -Fqx -- "PNG:$output" "$file" \
        || fail "capture for $output did not come from the requested output"
    [[ -f "$transition_file" && ! -L "$transition_file" && -O "$transition_file" && -s "$transition_file" ]] \
        || fail "direct lock capture does not provide a compatible transition frame for $output"
    [[ "$(mode_of "$transition_file")" == 600 ]] \
        || fail "transition capture for $output is not mode 0600"
done

PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" cleanup "$capture_dir"
[[ ! -e "$capture_dir" ]] || fail 'validated capture directory was not removed'

# Stale cleanup must be constrained to capture.* children of the dedicated root.
root="$TMP/runtime/awtarchy-lock-transition"
mkdir -p "$root/capture.stale" "$root/keep-this"
printf 'keep\n' >"$root/keep-this/sentinel"
capture_dir="$(run_prepare)" || fail 'capture helper failed while cleaning stale state'
[[ ! -e "$root/capture.stale" ]] || fail 'stale capture directory was not removed'
[[ -f "$root/keep-this/sentinel" ]] || fail 'stale cleanup removed an unrelated runtime entry'
PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" cleanup "$capture_dir"

# A partial output set must never survive as a usable backing set.
printf '%s\n' '[{"name":"DP-1"},{"name":"HDMI-A-1"}]' >"$TMP/monitors.json"
if PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    FAKE_MONITORS="$TMP/monitors.json" FAIL_GRIM_OUTPUT='HDMI-A-1' \
    bash "$HELPER" prepare >"$TMP/partial.out" 2>"$TMP/partial.err"; then
    fail 'partial output capture unexpectedly succeeded'
fi
[[ ! -s "$TMP/partial.out" ]] || fail 'partial output capture leaked a directory path'
if find "$root" -mindepth 1 -maxdepth 1 -type d -name 'capture.*' | grep -q .; then
    fail 'partial output capture left a capture directory behind'
fi

# Monitor names become filenames, so path separators/control input must be rejected.
printf '%s\n' '[{"name":"DP/1"}]' >"$TMP/monitors.json"
if run_prepare >"$TMP/unsafe.out" 2>"$TMP/unsafe.err"; then
    fail 'unsafe output name was accepted'
fi
[[ ! -s "$TMP/unsafe.out" ]] || fail 'unsafe output failure leaked a directory path'

# Cleanup must refuse a caller-controlled path outside the dedicated capture root.
outside="$TMP/runtime/do-not-remove"
mkdir -p "$outside"
printf 'sentinel\n' >"$outside/sentinel"
if PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" cleanup "$outside" >/dev/null 2>&1; then
    fail 'cleanup accepted a directory outside the dedicated capture root'
fi
[[ -f "$outside/sentinel" ]] || fail 'cleanup removed data outside the dedicated capture root'

# The editor-visible fallback must still stage two distinct snapshots in one
# private bundle. The first snapshot is the visible editor/settings view; the
# clean desktop is captured only after those backing windows have unmapped.
printf '%s\n' '[{"name":"DP-1"},{"name":"HDMI-A-1"}]' >"$TMP/monitors.json"
stage_dir="$(run_stage_begin)" || fail 'two-snapshot staging did not capture the transition source'
[[ ! -e "$root/prepared" ]] || fail 'transition-only staging published an incomplete prepared bundle'
for output in DP-1 HDMI-A-1; do
    [[ -s "$stage_dir/$output.transition.png" ]] \
        || fail "transition source for $output is missing after stage-begin"
    [[ ! -e "$stage_dir/$output.png" ]] \
        || fail "clean desktop frame for $output was captured before editor suppression"
done

PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" FAKE_MONITORS="$TMP/monitors.json" \
    bash "$HELPER" stage-complete "$stage_dir" \
    || fail 'two-snapshot staging did not capture the clean desktop phase'
[[ -f "$root/prepared" && ! -L "$root/prepared" && -O "$root/prepared" ]] \
    || fail 'complete two-snapshot bundle was not published atomically'
for output in DP-1 HDMI-A-1; do
    [[ -s "$stage_dir/$output.png" ]] \
        || fail "clean desktop frame for $output is missing after stage-complete"
done
consumed="$(PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" consume-prepared)" \
    || fail 'complete two-snapshot bundle could not be consumed'
[[ "$consumed" == "$stage_dir" ]] || fail 'consume-prepared returned the wrong two-snapshot bundle'
[[ ! -e "$root/prepared" ]] || fail 'consume-prepared did not consume the prepared pointer'
PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" \
    bash "$HELPER" cleanup "$stage_dir"

# Failure in the clean phase must never publish or retain a partially usable set.
stage_dir="$(run_stage_begin)" || fail 'second two-snapshot staging setup failed'
if PATH="$TMP/bin:$PATH" XDG_RUNTIME_DIR="$TMP/runtime" FAKE_MONITORS="$TMP/monitors.json" \
    FAIL_GRIM_OUTPUT='HDMI-A-1' bash "$HELPER" stage-complete "$stage_dir" \
    >"$TMP/stage-complete.out" 2>"$TMP/stage-complete.err"; then
    fail 'partial clean desktop phase unexpectedly succeeded'
fi
[[ ! -e "$root/prepared" ]] || fail 'failed clean phase published a prepared pointer'
[[ ! -e "$stage_dir" ]] || fail 'failed clean phase retained an incomplete capture bundle'

# The lock manager must capture before spawn, scope the path to the lock process,
# and explicitly remove any inherited stale capture variable on fail-closed fallback.
require_text "$LOCK_MANAGER" 'quickshell_lockscreen_capture.sh' \
    'lock manager does not call the dedicated capture helper'
require_text "$LOCK_MANAGER" 'AWTARCHY_LOCK_CAPTURE_DIR=' \
    'lock manager does not scope the validated capture directory to Quickshell'
require_text "$LOCK_MANAGER" 'env -u AWTARCHY_LOCK_CAPTURE_DIR' \
    'lock manager does not fail closed when capture preparation fails'
require_text "$LOCK_MANAGER" 'consume-prepared' \
    'Power Menu lock path does not consume the already prepared capture bundle'

# SUPER+P arms transparent keyboard input first, then captures the visible frame
# and checks real editor backing state. If already clean it promotes that frame
# immediately. If an editor is mapped it preserves the secure two-snapshot
# fallback: suppress, verify, recapture, restore, and only then reveal visuals.
require_text "$POWER_MENU" 'powermenu begin' \
    'SUPER+P does not arm input before capture work begins'
require_text "$POWER_MENU" 'stage-begin' \
    'SUPER+P does not capture the visible transition source first'
require_text "$POWER_MENU" 'editorHidden' \
    'SUPER+P does not inspect real editor backing state after the first capture'
require_text "$POWER_MENU" 'stage-promote-clean' \
    'SUPER+P does not reuse an already-clean first capture'
require_text "$POWER_MENU" 'suppressEditor' \
    'SUPER+P has no editor-visible suppression fallback'
require_text "$POWER_MENU" 'stage-complete' \
    'SUPER+P has no separate clean capture for the editor-visible fallback'
require_text "$POWER_MENU" 'restoreEditor' \
    'SUPER+P does not restore an editor after the fallback clean capture'
require_text "$POWER_MENU" 'powermenu reveal' \
    'SUPER+P has no explicit post-capture visual reveal'
require_order "$POWER_MENU" 'powermenu begin' 'stage-begin' \
    'SUPER+P does not arm keyboard input before entering screenshot latency'
require_order "$POWER_MENU" 'stage-begin' 'editorHidden' \
    'SUPER+P checks editor state before taking the transition source snapshot'
require_order "$POWER_MENU" 'editorHidden' 'stage-promote-clean' \
    'SUPER+P promotes the first frame before proving it is already clean'
require_order "$POWER_MENU" 'stage-promote-clean' 'suppressEditor' \
    'SUPER+P enters the fallback before attempting the clean fast path'
require_order "$POWER_MENU" 'suppressEditor' 'stage-complete' \
    'SUPER+P fallback captures clean desktop before requesting editor suppression'
require_order "$POWER_MENU" 'stage-complete' 'restoreEditor' \
    'SUPER+P restores the editor before the fallback clean desktop snapshot is complete'
require_order "$POWER_MENU" 'restoreEditor' 'powermenu reveal' \
    'SUPER+P reveals Power Menu visuals before restoring a fallback-suppressed editor'

# Readiness must be based on real QsWindow backing state for both the primary
# editor and secondary-monitor preview windows, not a QML visibility guess.
require_text "$EDITOR" 'function suppressForLockCapture' \
    'lockscreen editor does not expose temporary capture suppression'
require_text "$EDITOR" 'function lockCaptureBackingHidden' \
    'lockscreen editor does not expose backing-window readiness'
require_text "$EDITOR" 'backingWindowVisible' \
    'lockscreen editor readiness does not inspect real backing-window state'
require_text "$EDITOR" 'editorPreviewVariants.instances' \
    'lockscreen editor readiness ignores secondary-monitor preview windows'
require_text "$EDITOR" 'function restoreAfterLockCapture' \
    'lockscreen editor does not restore its pre-capture visibility'
require_text "$MAIN_SHELL" 'target: "lockcapture"' \
    'main Quickshell session does not expose the lock-capture coordination IPC'
require_text "$MAIN_SHELL" 'suppressEditor' \
    'lock-capture IPC does not expose editor suppression'
require_text "$MAIN_SHELL" 'editorHidden' \
    'lock-capture IPC does not expose backing-window readiness'
require_text "$MAIN_SHELL" 'restoreEditor' \
    'lock-capture IPC does not expose editor restoration'

# The secure compositor-owned surface keeps the clean frame as its only desktop
# backdrop, while the separate editor/settings frame is used only as transition
# source. This prevents background transparency from revealing the dirty source.
require_text "$SURFACE" 'transitionCaptureSource' \
    'secure surface does not load the staged editor/settings transition frame separately'
require_text "$SURFACE" 'id: transitionBacking' \
    'secure surface does not isolate the transition source in its own backing item'
require_text "$SURFACE" 'startSource: transitionBacking' \
    'lock transition does not begin from the staged editor/settings screenshot'
require_text "$SURFACE" 'desktopBackingSource: desktopBacking' \
    'secure lockscreen composition no longer uses the clean frozen desktop backdrop'
forbid_text "$SURFACE" 'startSource: desktopBacking' \
    'lock transition still starts from the clean desktop instead of the visible editor/settings snapshot'

printf 'PASS: secure lockscreen snapshot capture contract\n'
