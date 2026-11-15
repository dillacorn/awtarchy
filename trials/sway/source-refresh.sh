#!/usr/bin/env bash
# Registered Sway trial branch freshness. Read-only check and safe fast-forward.
set -euo pipefail
[[ $# -eq 2 ]] || { printf 'Usage: source-refresh.sh check|apply /absolute/repo\n' >&2; exit 2; }
action="$1"
repo="$2"
branch="SwayWM_Migration_Trial_Investigation"
[[ "$action" == check || "$action" == apply ]] || {
    printf 'Expected check or apply\n' >&2
    exit 2
}
[[ "$repo" == /* && -d "$repo/.git" && ! -L "$repo" ]] || {
    printf 'Unsafe or missing Sway trial checkout\n' >&2
    exit 1
}
[[ "$(git -C "$repo" branch --show-current)" == "$branch" ]] || {
    printf 'Registered checkout has the wrong branch\n' >&2
    exit 1
}
local_head="$(git -C "$repo" rev-parse --verify HEAD)"
remote_head="$(git -C "$repo" ls-remote --exit-code origin "refs/heads/$branch")" || {
    printf 'Cannot verify remote trial branch; refusing stale update\n' >&2
    exit 1
}
remote_head="${remote_head%%$'\t'*}"
[[ "$remote_head" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'Unexpected remote trial revision\n' >&2
    exit 1
}
if [[ "$local_head" == "$remote_head" ]]; then
    printf 'Sway trial source current: %s\n' "${local_head:0:12}"
    exit 0
fi
printf 'Sway trial checkout behind: local %s, remote %s\n' \
    "${local_head:0:12}" "${remote_head:0:12}"
if [[ "$action" == check ]]; then
    printf 'Preview blocked: checkout is stale. Apply will fast-forward a clean checkout first.\n' >&2
    exit 3
fi
[[ -z "$(git -C "$repo" status --porcelain --untracked-files=normal)" ]] || {
    printf 'Checkout has local changes; refusing fast-forward to preserve them.\n' >&2
    exit 1
}
git -C "$repo" fetch --no-tags origin "refs/heads/$branch"
fetched="$(git -C "$repo" rev-parse --verify FETCH_HEAD)"
[[ "$fetched" == "$remote_head" ]] || {
    printf 'Remote moved during fetch; checkout not modified. Retry.\n' >&2
    exit 1
}
git -C "$repo" merge --ff-only FETCH_HEAD
[[ "$(git -C "$repo" rev-parse --verify HEAD)" == "$remote_head" ]] || {
    printf 'Failed to verify updated trial revision\n' >&2
    exit 1
}
printf 'Sway trial source fast-forwarded: %s\n' "${remote_head:0:12}"
