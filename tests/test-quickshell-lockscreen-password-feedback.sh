#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$ROOT/config/quickshell/awtarchy/LockscreenPresentationState.js"
SECURE_RESOLVER="$ROOT/config/quickshell/awtarchy-lock/LockscreenPresentationState.js"
STATE="$ROOT/config/hypr/scripts/quickshell_application_state.sh"
EDITOR="$ROOT/config/quickshell/awtarchy/LockscreenEditor.qml"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$3"; }
reject_text() { if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }

node - "$RESOLVER" "$SECURE_RESOLVER" <<'NODE'
const assert = require("node:assert/strict");
const fs = require("fs");
const vm = require("vm");

function load(file) {
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/m, "");
  const context = {};
  vm.createContext(context);
  vm.runInContext(source, context, { filename: file });
  return context;
}

for (const file of process.argv.slice(2)) {
  const api = load(file);
  assert.equal(typeof api.normalizedProfile, "function", file + " missing normalizedProfile()");

  assert.equal(
    api.normalizedProfile({ lockscreen_password_mask_mode: "dots" }).lockscreen_password_feedback_mode,
    "dots",
    file + " did not migrate legacy dots mode",
  );
  for (const mode of ["squares", "dots", "custom", "sparks", "mini-flash", "hidden"]) {
    assert.equal(
      api.normalizedProfile({ lockscreen_password_feedback_mode: mode }).lockscreen_password_feedback_mode,
      mode,
      file + " rejected feedback mode " + mode,
    );
  }
  assert.equal(
    api.normalizedProfile({ lockscreen_password_feedback_mode: "bogus" }).lockscreen_password_feedback_mode,
    "squares",
    file + " did not fall back invalid feedback mode",
  );
  assert.equal(
    Object.prototype.hasOwnProperty.call(
      api.normalizedProfile({ lockscreen_password_mask_mode: "dots" }),
      "lockscreen_password_mask_mode",
    ),
    false,
    file + " still emits legacy mask mode as active profile state",
  );
}
NODE

# Backend must accept the new complete-profile key and reject invalid modes.
export HOME="$TMP/home"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$HOME" "$XDG_CACHE_HOME/awtarchy" "$XDG_CONFIG_HOME"
printf '%s\n' '{"enabled":true,"monitors":{},"launcher_sizes":{}}' >"$XDG_CACHE_HOME/awtarchy/quickshell-state.json"

profile="$(node - "$RESOLVER" <<'NODE'
const fs = require("fs");
const vm = require("vm");
const file = process.argv[2];
const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/m, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context, { filename: file });
process.stdout.write(JSON.stringify(context.normalizedProfile({
  lockscreen_password_feedback_mode: "sparks"
})));
NODE
)"

bash "$STATE" save-lockscreen-editor-profiles '{}' "$profile" '[]'
jq -e '
  .lockscreen_last_edited_profile.lockscreen_password_feedback_mode == "sparks"
  and .lockscreen_password_feedback_mode == "sparks"
  and (.lockscreen_password_mask_mode | not)
' "$XDG_CACHE_HOME/awtarchy/quickshell-state.json" >/dev/null   || fail 'backend did not persist the new password feedback field'

invalid="$(jq -c '.lockscreen_password_feedback_mode="bogus"' <<<"$profile")"
if bash "$STATE" save-lockscreen-editor-profiles '{}' "$invalid" '[]' >/dev/null 2>&1; then
  fail 'backend accepted invalid password feedback mode'
fi

require_text "$EDITOR" 'property string draftPasswordFeedbackMode: "squares"'   'editor has no password feedback draft state'
require_text "$EDITOR" '{ key: "sparks", label: "Sparks" }'   'editor password feedback selector is missing Sparks'
require_text "$EDITOR" '{ key: "mini-flash", label: "Mini Flash" }'   'editor password feedback selector is missing Mini Flash'
require_text "$EDITOR" '{ key: "hidden", label: "Hidden" }'   'editor password feedback selector is missing Hidden'
require_text "$EDITOR" 'lockscreen_password_feedback_mode: draftPasswordFeedbackMode'   'editor profile does not persist password feedback mode'
require_text "$EDITOR" 'draftPasswordFeedbackMode = normalizedPasswordFeedbackMode('   'editor does not load password feedback mode'
reject_text "$EDITOR" 'property string draftPasswordMaskMode:'   'editor still owns legacy password mask draft state'

printf '%s\n' 'PASS: lockscreen password feedback schema and editor controls'
