#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="${ROOT}/config/hypr/scripts/sunshine_awtarchy_setup.sh"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$HELPER"

grep -Fq 'configure_sunshine_awtarchy_hook_stage()' "$RUNTIME" \
  || fail 'runtime is missing Sunshine hook reconciliation stage'
[[ "$(grep -Fc 'configure_sunshine_awtarchy_hook_stage' "$RUNTIME")" -ge 3 ]] \
  || fail 'Sunshine hook reconciliation is not wired into both fresh install and update paths'

if grep -Eq 'systemctl[[:space:]].*(enable|disable|start|stop|restart)' "$HELPER"; then
  fail 'Sunshine configurator changes Sunshine service/autostart state'
fi

fakebin="${TMP}/fakebin"
mkdir -p -- "$fakebin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fakebin}/sunshine"
# The fake script expands its own arguments and log path when executed.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >>"${SYSTEMCTL_LOG:?}"' 'exit 99' >"${fakebin}/systemctl"
chmod 0755 "$fakebin/sunshine" "$fakebin/systemctl"

# Match the literal command persisted for Sunshine; $HOME expands when Sunshine runs it.
# shellcheck disable=SC2016
hook='/usr/bin/env bash -lc "$HOME/.config/hypr/scripts/sunshine-moonlight-fix.sh"'

run_helper() {
  local home="$1" log="$2"
  env \
    HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    PATH="$fakebin:$PATH" \
    SYSTEMCTL_LOG="$log" \
    bash "$HELPER"
}

assert_hook_state() {
  local conf="$1" expected_count="$2" expected_user_command="$3"
  python3 - "$conf" "$hook" "$expected_count" "$expected_user_command" <<'PY'
import json
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
hook = sys.argv[2]
expected_count = int(sys.argv[3])
expected_user_command = sys.argv[4]
text = path.read_text(encoding="utf-8")
matches = re.findall(r"^[ \t]*global_prep_cmd[ \t]*=[ \t]*(.+)$", text, flags=re.MULTILINE)
if len(matches) != 1:
    raise SystemExit(f"expected one global_prep_cmd assignment, found {len(matches)}")
commands = json.loads(matches[0])
hook_count = sum(1 for item in commands if isinstance(item, dict) and item.get("do") == hook)
if hook_count != expected_count:
    raise SystemExit(f"expected {expected_count} Awtarchy hook entries, found {hook_count}")
if expected_user_command and not any(
    isinstance(item, dict) and item.get("do") == expected_user_command for item in commands
):
    raise SystemExit("existing user preparation command was not preserved")
PY
}

# Fresh Sunshine config: create only the Awtarchy hook and do not touch systemd.
fresh_home="${TMP}/fresh-home"
fresh_log="${TMP}/fresh-systemctl.log"
mkdir -p -- "$fresh_home"
run_helper "$fresh_home" "$fresh_log" >/dev/null
fresh_conf="${fresh_home}/.config/sunshine/sunshine.conf"
[[ -f "$fresh_conf" ]] || fail 'fresh Sunshine config was not created'
assert_hook_state "$fresh_conf" 1 ""
[[ ! -s "$fresh_log" ]] || fail 'fresh Sunshine setup invoked systemctl'
[[ "$(stat -c '%a' "$fresh_conf")" == "600" ]] || fail 'fresh Sunshine config is not private mode 0600'

fresh_hash="$(sha256sum "$fresh_conf" | awk '{print $1}')"
run_helper "$fresh_home" "$fresh_log" >/dev/null
[[ "$fresh_hash" == "$(sha256sum "$fresh_conf" | awk '{print $1}')" ]] \
  || fail 'idempotent Sunshine setup rewrote an already-correct config'
shopt -s nullglob
fresh_backups=("${fresh_conf}".awtarchy-backup.*)
shopt -u nullglob
(( ${#fresh_backups[@]} == 0 )) || fail 'idempotent fresh setup created an unnecessary backup'

# Existing user commands must survive; a backup is created only for the actual edit.
existing_home="${TMP}/existing-home"
existing_log="${TMP}/existing-systemctl.log"
existing_dir="${existing_home}/.config/sunshine"
existing_conf="${existing_dir}/sunshine.conf"
mkdir -p -- "$existing_dir"
printf '%s\n' \
  'encoder = software' \
  'global_prep_cmd = [{"do":"echo user-command","undo":"echo user-undo"}]' \
  'capture = wlr' >"$existing_conf"
chmod 0640 "$existing_conf"

run_helper "$existing_home" "$existing_log" >/dev/null
assert_hook_state "$existing_conf" 1 "echo user-command"
grep -Fxq 'encoder = software' "$existing_conf" || fail 'Sunshine encoder setting changed'
grep -Fxq 'capture = wlr' "$existing_conf" || fail 'Sunshine capture setting changed'
[[ "$(stat -c '%a' "$existing_conf")" == "640" ]] || fail 'existing Sunshine config mode was not preserved'
[[ ! -s "$existing_log" ]] || fail 'existing Sunshine setup invoked systemctl'

shopt -s nullglob
existing_backups=("${existing_conf}".awtarchy-backup.*)
shopt -u nullglob
(( ${#existing_backups[@]} == 1 )) || fail 'existing Sunshine config did not receive exactly one backup'

existing_hash="$(sha256sum "$existing_conf" | awk '{print $1}')"
run_helper "$existing_home" "$existing_log" >/dev/null
[[ "$existing_hash" == "$(sha256sum "$existing_conf" | awk '{print $1}')" ]] \
  || fail 'second Sunshine reconciliation was not idempotent'
shopt -s nullglob
existing_backups=("${existing_conf}".awtarchy-backup.*)
shopt -u nullglob
(( ${#existing_backups[@]} == 1 )) || fail 'idempotent reconciliation created another backup'

# Malformed user configuration must never be replaced.
bad_home="${TMP}/bad-home"
bad_log="${TMP}/bad-systemctl.log"
bad_dir="${bad_home}/.config/sunshine"
bad_conf="${bad_dir}/sunshine.conf"
mkdir -p -- "$bad_dir"
printf '%s\n' 'global_prep_cmd = not-json' >"$bad_conf"
bad_hash="$(sha256sum "$bad_conf" | awk '{print $1}')"
if run_helper "$bad_home" "$bad_log" >/dev/null 2>&1; then
  fail 'malformed Sunshine global_prep_cmd was accepted'
fi
[[ "$bad_hash" == "$(sha256sum "$bad_conf" | awk '{print $1}')" ]] \
  || fail 'malformed Sunshine config changed despite reconciliation failure'
[[ ! -s "$bad_log" ]] || fail 'malformed Sunshine setup invoked systemctl'

printf '%s\n' 'PASS: Sunshine hook is configured idempotently on install/update without changing Sunshine service/autostart state.'
