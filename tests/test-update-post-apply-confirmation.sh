#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n "$RUNTIME"

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

helper = text.find("confirm_live_update_result() {")
if helper < 0:
    raise SystemExit("FAIL: post-update confirmation helper is missing")

start = text.find('if ! start_quickshell_update_shell; then')
if start < 0:
    raise SystemExit("FAIL: live shell restart stage is missing")

confirm = text.find('if ! confirm_live_update_result; then', start)
if confirm < 0:
    raise SystemExit("FAIL: update does not ask for keep/rollback after live validation")

hardware = text.find('hardware_reconcile', confirm)
if hardware < 0:
    raise SystemExit("FAIL: hardware reconciliation disappeared from update path")

cleanup = text.find('remove_quickshell_update_legacy_files', confirm)
baseline = text.find('commit_baseline', confirm)
if cleanup < 0 or baseline < 0:
    raise SystemExit("FAIL: could not locate update finalization stages")

if not (start < confirm < hardware < cleanup < baseline):
    raise SystemExit(
        "FAIL: live confirmation must happen after shell restart and before "
        "hardware/package mutation, legacy cleanup, and baseline commit"
    )

body_end = text.find("\n}\n", helper)
body = text[helper:body_end]
for token in (
    '"Keep changes"',
    '"Roll back managed config changes"',
    'rollback_quickshell_update',
    'return 1',
):
    if token not in body:
        raise SystemExit(f"FAIL: post-update confirmation is missing {token}")

if 'if ! confirm_live_update_result; then\n    return 20\n  fi' not in text:
    raise SystemExit("FAIL: runtime does not return the dedicated user-rollback status")

print("PASS: live updates require an explicit keep/rollback decision before finalization.")
PY

python3 - "$ROOT/local/bin/awtarchy" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")

required = (
    '20)\n      log "Git-testing update was rolled back by the user; skipping post-update UI reconciliation."',
    '20)\n              log "Update was rolled back by the user; skipping post-update UI reconciliation."',
    '20)\n          log "Update was rolled back by the user; skipping post-update UI reconciliation."',
)
for token in required:
    if token not in text:
        raise SystemExit(f"FAIL: launcher does not consume user rollback status safely: {token}")

print("PASS: launcher suppresses post-update reconciliation after a user rollback.")
PY
