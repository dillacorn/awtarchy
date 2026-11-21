#!/usr/bin/env bash
# Restore the 80/20 Steam/Friends horizontal split after Steam launches.
# Umbriel-only; do not change unrelated windows or override user resizes later.
set -euo pipefail

main() {
    [[ "${XDG_CURRENT_DESKTOP,,}" == umbriel && -n "${WAYLAND_DISPLAY:-}" ]] || return 0
    command -v umbriel >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Avoid parallel long-lived workers if the Steam desktop shortcut is
    # invoked more than once. The lock is isolated to this user session.
    local runtime="${XDG_RUNTIME_DIR:-}"
    [[ -n "$runtime" && -d "$runtime" && ! -L "$runtime" && -O "$runtime" ]] || return 0
    local lock="$runtime/awtarchy-umbriel-steam-layout.lock"
    if [[ -L "$lock" || ( -e "$lock" && ( ! -f "$lock" || ! -O "$lock" ) ) ]]; then
        return 0
    fi
    local lock_fd
    exec {lock_fd}>"$lock"
    flock -n "$lock_fd" || return 0

    local deadline=$((SECONDS + 90))
    local windows row main_id main_width friends_width total_width
    while (( SECONDS < deadline )); do
        windows="$(umbriel windows --json 2>/dev/null)" || {
            sleep 0.2
            continue
        }
        # Wait for exactly the two Steam primary windows on the same visible,
        # side-by-side tiled workspace. Never resize dialogs or unrelated apps.
        row="$(jq -er '
            if type != "array" then empty else
                [.[] | select(
                    .app_id == "steam" and
                    (.title == "Steam" or .title == "Friends List")
                )] as $pair |
                [$pair[] | select(.title == "Steam")] as $main |
                [$pair[] | select(.title == "Friends List")] as $friends |
                if ($pair | length) == 2 and ($main | length) == 1
                    and ($friends | length) == 1
                    and ($main[0].id | type) == "string"
                    and ($main[0].id | length) > 0
                    and ($main[0].workspace == $friends[0].workspace)
                    and ($main[0].output == $friends[0].output)
                    and ($main[0].visible == true and $friends[0].visible == true)
                    and ($main[0].floating == false and $friends[0].floating == false)
                    and ($main[0].fullscreen == false and $friends[0].fullscreen == false)
                    and ($main[0].x | type) == "number"
                    and ($friends[0].x | type) == "number"
                    and ($main[0].x < $friends[0].x)
                    and ($main[0].w | type) == "number"
                    and ($friends[0].w | type) == "number"
                    and ($main[0].w > 0 and $friends[0].w > 0)
                then [$main[0].id, $main[0].w, $friends[0].w] | @tsv
                else empty end
            end
        ' <<< "$windows" 2>/dev/null)" || {
            sleep 0.2
            continue
        }
        IFS=$'\t' read -r main_id main_width friends_width <<< "$row"
        total_width=$((main_width + friends_width))

        # An already-correct split must stay untouched.
        if ((main_width * 100 >= total_width * 74 &&
             main_width * 100 <= total_width * 86)); then
            return 0
        fi

        # Proven on the Umbriel dwindle layout with the Steam main tile left.
        # It sets the focused tile's horizontal extent to 80 percent.
        umbriel msg window-focus "$main_id" >/dev/null 2>&1 || return 1
        umbriel msg window-set-primary-extent 0.8 >/dev/null 2>&1
        return
    done
    return 0
}

main "$@"
