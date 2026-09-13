#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/hypr/scripts/quickshell_lockscreen_capture.sh"
LOCK_MANAGER="${ROOT}/config/hypr/scripts/awtarchy_lock.sh"
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
    [[ -f "$file" && ! -L "$file" && -O "$file" && -s "$file" ]] \
        || fail "capture for $output is not a valid owned regular file"
    [[ "$(mode_of "$file")" == 600 ]] \
        || fail "capture for $output is not mode 0600"
    grep -Fqx -- "PNG:$output" "$file" \
        || fail "capture for $output did not come from the requested output"
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

# The lock manager must capture before spawn, scope the path to the lock process,
# and explicitly remove any inherited stale capture variable on fail-closed fallback.
require_text "$LOCK_MANAGER" 'quickshell_lockscreen_capture.sh' \
    'lock manager does not call the dedicated capture helper'
require_text "$LOCK_MANAGER" 'AWTARCHY_LOCK_CAPTURE_DIR=' \
    'lock manager does not scope the validated capture directory to Quickshell'
require_text "$LOCK_MANAGER" 'env -u AWTARCHY_LOCK_CAPTURE_DIR' \
    'lock manager does not fail closed when capture preparation fails'

printf 'PASS: secure lockscreen pre-lock capture contract\n'
