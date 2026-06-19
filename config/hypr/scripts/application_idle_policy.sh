#!/usr/bin/env bash
set -Eeuo pipefail

application="${APPLICATION_IDLE_POLICY_APP:-${0##*/}}"

case "$application" in
    vesktop)
        electron_bin="$(command -v electron39 || true)"
        vesktop_asar="/usr/lib/vesktop/app.asar"

        [[ -n "$electron_bin" && -x "$electron_bin" ]] || {
            printf '%s\n' \
                'application_idle_policy: electron39 was not found' >&2
            exit 127
        }

        [[ -f "$vesktop_asar" ]] || {
            printf 'application_idle_policy: missing %s\n' \
                "$vesktop_asar" >&2
            exit 1
        }

        exec env ELECTRON_OZONE_PLATFORM_HINT=auto \
            "$electron_bin" \
            --disable-features=EnableIdleInhibit \
            --disable-blink-features=WakeLock \
            "$vesktop_asar" \
            "$@"
        ;;

    application_idle_policy.sh)
        printf 'Usage: invoke through an application symlink, such as:\n' >&2
        printf '  ~/.local/bin/vesktop -> %s\n' "$0" >&2
        exit 64
        ;;

    *)
        printf 'application_idle_policy: unsupported application: %s\n' \
            "$application" >&2
        exit 64
        ;;
esac
