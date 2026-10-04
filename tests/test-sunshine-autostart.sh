#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
COMMAND="${ROOT}/local/bin/awtarchy"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

bash -n "$COMMAND"

grep -Fq '"Sunshine autostart"' "$COMMAND" \
  || fail 'maintenance menu is missing Sunshine autostart'
grep -Fq 'awtarchy sunshine-autostart [status|enable|disable]' "$COMMAND" \
  || fail 'Sunshine autostart CLI usage is missing'

fakebin="${TMP}/fakebin"
home="${TMP}/home"
state="${TMP}/state"
log="${TMP}/systemctl.log"
mkdir -p -- "$fakebin" "$home"
printf '%s\n' disabled >"$state"

cat >"${fakebin}/systemctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${SYSTEMCTL_LOG:?}"

[[ "${1:-}" == "--user" ]] || exit 97
shift
action="${1:-}"
shift || true

case "$action" in
  cat)
    [[ "${1:-}" == "app-dev.lizardbyte.app.Sunshine.service" ]]
    ;;
  is-enabled)
    current="$(cat "${SUNSHINE_STATE:?}")"
    printf '%s\n' "$current"
    [[ "$current" == enabled ]]
    ;;
  daemon-reload)
    ;;
  enable)
    [[ "${1:-}" == "app-dev.lizardbyte.app.Sunshine.service" ]]
    printf '%s\n' enabled >"${SUNSHINE_STATE:?}"
    ;;
  disable)
    [[ "${1:-}" == "app-dev.lizardbyte.app.Sunshine.service" ]]
    printf '%s\n' disabled >"${SUNSHINE_STATE:?}"
    ;;
  start|stop|restart|try-restart)
    exit 98
    ;;
  *)
    exit 96
    ;;
esac
SH
chmod 0755 "${fakebin}/systemctl"

run_cmd() {
  env \
    HOME="$home" \
    USER=awtarchy-test \
    LOGNAME=awtarchy-test \
    XDG_DATA_HOME="$home/.local/share" \
    XDG_STATE_HOME="$home/.local/state" \
    PATH="$fakebin:/usr/bin:/bin" \
    SYSTEMCTL_LOG="$log" \
    SUNSHINE_STATE="$state" \
    bash "$COMMAND" sunshine-autostart "$@"
}

out="$(run_cmd status)"
grep -Fq 'Sunshine autostart: disabled' <<<"$out" \
  || fail 'initial Sunshine autostart status was not disabled'

out="$(run_cmd enable)"
grep -Fq 'Sunshine autostart enabled for future desktop logins.' <<<"$out" \
  || fail 'enable did not report future-login autostart'
grep -Fq 'Sunshine was not started.' <<<"$out" \
  || fail 'enable did not report that Sunshine was left stopped'
[[ "$(cat "$state")" == enabled ]] || fail 'enable did not enable the service'

out="$(run_cmd status)"
grep -Fq 'Sunshine autostart: enabled' <<<"$out" \
  || fail 'enabled Sunshine autostart status was not reported'

out="$(run_cmd disable)"
grep -Fq 'Sunshine autostart disabled for future desktop logins.' <<<"$out" \
  || fail 'disable did not report future-login autostart removal'
grep -Fq 'A currently running Sunshine process was not stopped.' <<<"$out" \
  || fail 'disable did not preserve current Sunshine process state'
[[ "$(cat "$state")" == disabled ]] || fail 'disable did not disable the service'

if grep -Eq -- '(^| )(start|stop|restart|try-restart)( |$)|--now' "$log"; then
  fail 'Sunshine autostart control started or stopped Sunshine'
fi

printf '%s\n' 'PASS: Sunshine autostart menu/CLI toggles login startup without starting or stopping Sunshine.'
