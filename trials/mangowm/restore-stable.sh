#!/usr/bin/env bash
# Restore the recorded stable Awtarchy release using the exact Mango-aware
# trial runtime. The ordinary main updater cannot parse a Mango-managed baseline.
set -euo pipefail

fail() {
    printf 'Mango stable restore: %s\n' "$*" >&2
    return 1
}

main() {
    local mode="${1:-}" root="" runtime="" repo_remote="" head="" dirty=""
    local state_root="" state="" version_file="" key="" value=""
    local branch="" revision="" stable="" installed=""

    [[ $# -eq 1 && ( "$mode" == --review || "$mode" == --restore ) ]] || {
        printf 'Usage: bash trials/mangowm/restore-stable.sh --review|--restore\n' >&2
        return 2
    }
    [[ "$(id -u)" -ne 0 ]] || { fail 'Run as the normal desktop user, never root.'; return 1; }
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -n "${WAYLAND_DISPLAY:-}" \
        && -z "${MANGO_INSTANCE_SIGNATURE:-}" ]] || {
        fail 'Log out of Mango and log into the Hyprland session first.'
        return 1
    }
    command -v hyprctl >/dev/null 2>&1 && hyprctl -j version 2>/dev/null | \
        jq -e 'type == "object"' >/dev/null 2>&1 || {
        fail 'No responsive Hyprland compositor; refusing restoration.'
        return 1
    }
    if [[ "$mode" == --restore && ( ! -t 0 || ! -t 1 ) ]]; then
        fail 'Restore requires an interactive terminal for review and rollback confirmation.'
        return 1
    fi

    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)" || return 1
    runtime="$root/local/share/awtarchy/awtarchy-runtime.sh"
    [[ -f "$runtime" && ! -L "$runtime" ]] || { fail 'Missing trial runtime.'; return 1; }
    state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
    state="$state_root/awtarchy/git-testing"
    version_file="$state_root/awtarchy/config-version"
    for file in "$state" "$version_file"; do
        [[ -f "$file" && ! -L "$file" && -O "$file" ]] || {
            fail 'Trusted installed Git-testing state is unavailable.'
            return 1
        }
        [[ "$(stat -c %s -- "$file")" -le 4096 ]] || {
            fail 'Installed state has unexpected size.'
            return 1
        }
    done

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            branch) [[ -z "$branch" ]] || { fail 'Duplicate branch state.'; return 1; }; branch="$value" ;;
            revision) [[ -z "$revision" ]] || { fail 'Duplicate revision state.'; return 1; }; revision="$value" ;;
            stable_release) [[ -z "$stable" ]] || { fail 'Duplicate stable state.'; return 1; }; stable="$value" ;;
        esac
    done <"$state"
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        if [[ "$key" == tag ]]; then
            [[ -z "$installed" ]] || { fail 'Duplicate installed tag.'; return 1; }
            installed="$value"
        fi
    done <"$version_file"

    [[ "$branch" == MangoWM_Migration_Trial_Investigation \
        && "$revision" =~ ^[0-9a-f]{40}$ \
        && "$stable" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ \
        && "$installed" == "${branch}@${revision}" ]] || {
        fail 'Installed Mango revision or recorded stable predecessor is inconsistent.'
        return 1
    }

    [[ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" == "$root" ]] || {
        fail 'Run from a checkout of dillacorn/awtarchy, not an archive.'
        return 1
    }
    repo_remote="$(git -C "$root" remote get-url origin 2>/dev/null)" || return 1
    case "$repo_remote" in
        https://github.com/dillacorn/awtarchy|https://github.com/dillacorn/awtarchy.git|git@github.com:dillacorn/awtarchy.git) ;;
        *) fail 'Checkout origin does not match dillacorn/awtarchy.'; return 1 ;;
    esac
    head="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || return 1
    [[ "$head" == "$revision" ]] || {
        fail 'Checkout HEAD must equal the exact installed Mango trial revision.'
        return 1
    }
    dirty="$(git -C "$root" status --porcelain --untracked-files=all)" || return 1
    [[ -z "$dirty" ]] || { fail 'Checkout is modified; refusing to run altered updater code.'; return 1; }
    bash -n "$runtime" || { fail 'Trial runtime failed Bash syntax validation.'; return 1; }

    printf 'Mango stable restore: %s from exact trial revision %s\n' "$stable" "$revision"
    if [[ "$mode" == --review ]]; then
        bash "$runtime" update-reset-backup --tag "$stable" --mode preserve --review-only
    else
        bash "$runtime" update-reset-backup --tag "$stable" --mode preserve
    fi
}

main "$@"
