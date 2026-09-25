#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n "$RUNTIME"

grep -Fq 'view_diff_file()' "$RUNTIME" \
    || fail 'updater has no internal managed-file diff viewer'
grep -Fq 'read_update_key' "$RUNTIME" \
    || fail 'internal diff viewer does not use Awtarchy raw-key input'
grep -Fq 'Approve update? y/n  (Enter confirms selection)' "$RUNTIME" \
    || fail 'managed-file review does not explain Enter-confirmed y/n approval'
grep -Fq 'approval_choice="y"' "$RUNTIME" \
    || fail 'review does not stage y before Enter confirmation'
grep -Fq 'approval_choice="n"' "$RUNTIME" \
    || fail 'review does not stage n before Enter confirmation'
grep -Fq 'case "$approval_choice" in' "$RUNTIME" \
    || fail 'review does not require Enter to confirm the staged approval choice'
grep -Fq 'approval_choice=""; index=$((index - page_size))' "$RUNTIME" \
    || fail 'review does not clear pending approval when navigation resumes'
grep -Fq 'if ! review_plan "$plan_file" update; then' "$RUNTIME" \
    || fail 'managed update is not gated directly by review approval'
grep -Fq 'review_plan "$plan_file" review-only' "$RUNTIME" \
    || fail 'review-only mode does not retain a non-mutating close path'

if grep -Fq 'confirm_update_after_review()' "$RUNTIME"; then
    fail 'updater still has a second confirmation prompt after review'
fi
if grep -Fq 'q closes review and continues the requested operation.' "$RUNTIME"; then
    fail 'update review still treats q as approval'
fi
if grep -Fq 'less -R "$tmp"' "$RUNTIME"; then
    fail 'managed-file review still delegates input to external less'
fi

mode_line="$(grep -nF 'select_update_mode' "$RUNTIME" | tail -n1 | cut -d: -f1)"
approval_line="$(grep -nF 'if ! review_plan "$plan_file" update; then' "$RUNTIME" | tail -n1 | cut -d: -f1)"
[[ -n "$mode_line" && -n "$approval_line" && "$mode_line" -lt "$approval_line" ]] \
    || fail 'update mode prompt still occurs after final y/n approval'

grep -Fq 'Update approved. Preparing required dependencies...' "$RUNTIME" \
    || fail 'updater gives no immediate feedback after approval'
grep -Fq 'Applying approved managed-file changes...' "$RUNTIME" \
    || fail 'updater gives no feedback before managed-file application'
grep -Fq 'Reloading Hyprland and validating the updated configuration...' "$RUNTIME" \
    || fail 'updater gives no feedback before live validation'

printf '%s\n' 'PASS: managed-file review requires y/n plus Enter and reports post-approval progress.'
