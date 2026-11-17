#!/usr/bin/env bash
# Exact-file Ly registration; never alter another compositor session.
set -euo pipefail
fail() { printf 'KWin Ly setup: %s\n' "$*" >&2; return 1; }

main() {
    [[ $# -eq 1 ]] || { fail 'Usage: setup-ly.sh plan|apply|remove'; return 2; }
    local mode="$1"
    [[ "$mode" == plan || "$mode" == apply || "$mode" == remove ]] || {
        fail 'Unknown mode'; return 2;
    }
    [[ ${EUID} -ne 0 ]] || { fail 'Run as normal user'; return 1; }
    local source=''
    source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
    local wrapper="$source/ly-session.sh"
    local desktop="$source/kwin.desktop"
    local target_wrapper=/usr/local/bin/awtarchy-kwin-trial-session
    local target_desktop=/usr/share/wayland-sessions/awtarchy-kwin-trial.desktop
    local directory path dest origin
    for directory in /usr/local/bin /usr/share/wayland-sessions; do
        [[ -d "$directory" && ! -L "$directory" ]] || {
            fail "Missing/unsafe system directory: $directory"; return 1;
        }
    done
    [[ -f "$wrapper" && ! -L "$wrapper" && -O "$wrapper" ]] ||
        { fail 'Invalid Ly wrapper'; return 1; }
    [[ -f "$desktop" && ! -L "$desktop" && -O "$desktop" ]] ||
        { fail 'Invalid Ly desktop file'; return 1; }
    bash -n "$wrapper" || return 1
    grep -Fqx 'Exec=/usr/local/bin/awtarchy-kwin-trial-session' "$desktop" ||
        { fail 'Desktop Exec mismatch'; return 1; }

    if [[ "$mode" != remove ]]; then
        local user_script="${XDG_DATA_HOME:-$HOME/.local/share}/awtarchy-kwin-trial/tty-smoke.sh"
        [[ -f "$user_script" && ! -L "$user_script" && -O "$user_script" ]] ||
            { fail 'Install or update the user-local KWin trial first'; return 1; }
        for path in /usr/bin/kwin_wayland /usr/bin/qs /usr/bin/foot /usr/bin/fuzzel; do
            [[ -x "$path" ]] || { fail "Missing executable: $path"; return 1; }
        done
        /usr/bin/python3 -c 'import dbus_next' >/dev/null 2>&1 ||
            { fail 'Missing python-dbus-next'; return 1; }
    fi

    local pairs=("$wrapper:$target_wrapper" "$desktop:$target_desktop")
    for path in "${pairs[@]}"; do
        origin="${path%%:*}"
        dest="${path#*:}"
        [[ ! -L "$dest" ]] || { fail "Symlink target refused: $dest"; return 1; }
        if [[ -e "$dest" ]]; then
            [[ -f "$dest" && "$(stat -c %u -- "$dest")" == 0 ]] ||
                { fail "Unowned/unsafe target: $dest"; return 1; }
            if pacman -Qo -- "$dest" >/dev/null 2>&1; then
                fail "Package-owned target refused: $dest"; return 1
            fi
            cmp -s -- "$origin" "$dest" ||
                { fail "Custom/unrecognized file preserved: $dest"; return 1; }
        fi
    done
    if [[ "$mode" == plan ]]; then
        for path in "${pairs[@]}"; do
            dest="${path#*:}"
            if [[ -f "$dest" ]]; then
                printf 'PRESERVE exact file: %s\n' "$dest"
            else
                printf 'WOULD INSTALL: %s\n' "$dest"
            fi
        done
        return 0
    fi
    if [[ "$mode" == remove ]]; then
        for path in "${pairs[@]}"; do
            dest="${path#*:}"
            [[ -f "$dest" ]] || continue
            sudo rm -- "$dest" || return 1
            printf 'REMOVED exact KWin Ly file: %s\n' "$dest"
        done
        printf 'Hyprland and Sway Ly entries unchanged.\n'
        return 0
    fi
    for path in "${pairs[@]}"; do
        origin="${path%%:*}"
        dest="${path#*:}"
        [[ -f "$dest" ]] && continue
        if [[ "$dest" == "$target_wrapper" ]]; then
            sudo install -m 0755 -- "$origin" "$dest" || return 1
        else
            sudo install -m 0644 -- "$origin" "$dest" || return 1
        fi
        cmp -s -- "$origin" "$dest" ||
            { fail "Verification failed for $dest"; return 1; }
        printf 'INSTALLED: %s\n' "$dest"
    done
    printf 'KWin (Awtarchy Trial) will appear in Ly after returning to the login screen.\n'
}

main "$@"
