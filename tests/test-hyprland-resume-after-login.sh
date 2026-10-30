#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LAUNCHER="$ROOT/local/bin/awtarchy"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
HYPR_LUA="$ROOT/config/hypr/hyprland.lua"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }

bash -n "$LAUNCHER"
bash -n "$RUNTIME"
# Extract only actual production functions, never source the entire updater.
for f in deferred_resume_marker clear_deferred_resume_marker resume_deferred_hyprland_update; do
  sed -n "/^${f}() {/,/^}/p" "$LAUNCHER" >> "$TMP/launcher-functions.sh"
done
sed -n '/^stage_hyprland_resume_update() {/,/^}/p' "$RUNTIME" >"$TMP/stage-function.sh"
# shellcheck disable=SC1091
source "$TMP/launcher-functions.sh"
# shellcheck disable=SC1091
source "$TMP/stage-function.sh"

TARGET_HOME="$TMP/home"
HOME_DIR="$TARGET_HOME"
STATE_HOME="$TARGET_HOME/.local/state"
STATE_DIR="$STATE_HOME/awtarchy"
GIT_TEST_STATE_FILE="$STATE_DIR/git-testing"
mkdir -p "$STATE_DIR" "$TARGET_HOME/.local/bin" "$TARGET_HOME/.config/hypr" "$TMP/bin"
: >"$TARGET_HOME/.local/bin/awtarchy"
chmod 0755 "$TARGET_HOME/.local/bin/awtarchy"
export PATH="$TMP/bin:$PATH"
export WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=old-session
LOG_PREFIX="[awtarchy-test]"
log() { :; }
warn() { :; }
have() { command -v "$1" >/dev/null 2>&1; }
pacman() { [[ "$1" == -Q && "$2" == hyprland ]] || fail "unexpected pacman request"; printf 'hyprland 0.57.0-1\n'; }
hyprctl() {
  [[ "$1" == -j && "$2" == version ]] || fail "unexpected hyprctl request"
  printf '{"tag":"v%s"}\n' "${MOCK_COMPOSITOR_VERSION:-0.57.0}"
}
foot() {
  local IFS=" "
  printf '%s\n' "$*" >>"$TMP/foot-invocations"
}
TESTING_COMMIT=""
# An immutable older release without the startup hook cannot auto-resume.
stage_hyprland_resume_update v4.1.3
[[ ! -e "$STATE_DIR/hyprland-update-resume-pending" ]] ||
  fail "missing installed hook incorrectly scheduled auto-resume"
cp -- "$HYPR_LUA" "$TARGET_HOME/.config/hypr/hyprland.lua"
marker="$(deferred_resume_marker)"
[[ $marker == "$STATE_DIR/hyprland-update-resume-pending" ]] ||
  fail "launcher and runtime disagree about marker location"

# Only stable, approved update deferrals can create the pending marker.
stage_hyprland_resume_update v4.1.3
[[ -f "$marker" && ! -L "$marker" && -O "$marker" ]] ||
  fail "stable update failed to create a regular owned marker"
[[ "$(stat -c %a "$marker")" == 600 ]] || fail "marker permissions must be 0600"
mapfile -t payload <"$marker"
[[ ${#payload[@]} == 2 && ${payload[0]} == v4.1.3 && ${payload[1]} == old-session ]] ||
  fail "marker did not capture approved target and initial session"

# Never launch in the same Hyprland session or against an old compositor.
resume_deferred_hyprland_update
[[ -f $marker && ! -e $TMP/foot-invocations ]] ||
  fail "resume launched before the new session"
HYPRLAND_INSTANCE_SIGNATURE=new-session
MOCK_COMPOSITOR_VERSION=0.56.2
resume_deferred_hyprland_update
[[ -f $marker && ! -e $TMP/foot-invocations ]] ||
  fail "resume launched before installed/running versions matched"

# Never launch while explicit Git testing is active.
MOCK_COMPOSITOR_VERSION=0.57.0
printf 'test-state\n' >"$GIT_TEST_STATE_FILE"
resume_deferred_hyprland_update
[[ -f $marker && ! -e $TMP/foot-invocations ]] ||
  fail "resume bypassed active Git-testing state"
rm -f -- "$GIT_TEST_STATE_FILE"

# A new compositor session claims the marker before launching exactly one Foot.
resume_deferred_hyprland_update
[[ ! -e $marker && -f $TMP/foot-invocations ]] ||
  fail "resume did not consume the marker and invoke Foot"
[[ "$(wc -l <"$TMP/foot-invocations")" == 1 ]] ||
  fail "resume created duplicate windows"
grep -Fq 'awtarchy-update-resume' "$TMP/foot-invocations" ||
  fail "resume missed isolated Foot app-id"
grep -Fq 'update' "$TMP/foot-invocations" ||
  fail "resume omitted the update command"
grep -Fq 'v4.1.3' "$TMP/foot-invocations" ||
  fail "resume did not preserve the previously approved release"
resume_deferred_hyprland_update
[[ "$(wc -l <"$TMP/foot-invocations")" == 1 ]] ||
  fail "resume repeated after marker consumption"

# A canceled normal review must not cause the terminal to reopen on login.
HYPRLAND_INSTANCE_SIGNATURE=old-session
stage_hyprland_resume_update v4.1.3
clear_deferred_resume_marker
[[ ! -e $marker ]] || fail "normal update success did not clear stale pending marker"

# Git test staging is deliberately never scheduled.
TESTING_COMMIT=0123456789abcdef0123456789abcdef01234567
stage_hyprland_resume_update v4.1.3
[[ ! -e $marker ]] || fail "Git testing accidentally scheduled an unattended resume"
TESTING_COMMIT=""

# A damaged marker cannot result in arbitrary terminal commands.
printf 'v4.1.3\nold-session\nthird-line\n' >"$marker"
resume_deferred_hyprland_update
[[ -f $marker && "$(wc -l <"$TMP/foot-invocations")" == 1 ]] ||
  fail "malformed marker was executed"

python3 - "$LAUNCHER" "$RUNTIME" "$HYPR_LUA" <<'PY'
from pathlib import Path
import sys
launcher, runtime, lua = (Path(p).read_text(encoding="utf-8") for p in sys.argv[1:])
assert '    stage_hyprland_resume_update "$tag"' in runtime
assert runtime.index('stage_hyprland_resume_update "$tag"') < runtime.index('    return 21', runtime.index('stage_hyprland_resume_update "$tag"'))
assert 'resume-update)' in launcher
assert 'clear_deferred_resume_marker' in launcher
assert lua.count('resume-update') == 1
assert 'hyprland-update-resume-pending' in lua
assert 'if [ -f ' in lua and 'sleep 4' in lua
PY

printf '%s\n' 'PASS: deferred Hyprland update marker, session/version checks, one-time Foot launch, Git isolation, and manual completion.'
