#!/usr/bin/env bash
# Open a command in the user's preferred terminal using Foot.

set -euo pipefail

window_class="terminal-command"
hold_open=0
no_profile=0

while (( $# > 0 )); do
  case "$1" in
    --class)
      [[ -n ${2:-} ]] || { printf '%s\n' '--class requires a value' >&2; exit 2; }
      window_class="$2"
      shift 2
      ;;
    --hold)
      hold_open=1
      shift
      ;;
    --no-profile)
      no_profile=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

(( $# > 0 )) || {
  printf 'usage: %s [--class NAME] [--hold] [--no-profile] -- COMMAND [ARG...]\n' "${0##*/}" >&2
  exit 2
}

command_args=("$@")
if (( hold_open )); then
  printf -v command_line '%q ' "${command_args[@]}"
  hold_command="${command_line}; status=\$?; printf '\\n[command finished: %s]\\nPress ENTER to close...' \"\$status\"; IFS= read -r _; finish_with_status() { return \"\$1\"; }; finish_with_status \"\$status\""
  if (( no_profile )); then
    command_args=(bash --noprofile --norc -c "$hold_command")
  else
    command_args=(bash -lc "$hold_command")
  fi
fi

command -v foot >/dev/null 2>&1 || {
  printf '%s\n' 'Foot terminal emulator is required by Awtarchy.' >&2
  exit 127
}

exec foot --app-id="$window_class" "${command_args[@]}"
