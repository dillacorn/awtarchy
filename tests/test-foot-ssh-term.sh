#!/usr/bin/env bash
# Foot SSH TERM compatibility: local value stays intact, remote receives a fallback.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p -- "$TMP/bin"

cat > "$TMP/bin/ssh" <<'MOCK_SSH'
#!/usr/bin/env bash
printf '%s\n' "${TERM-UNSET}" > "$AWTARCHY_TEST_SSH_TERM_LOG"
printf '%s\n' "$@" > "$AWTARCHY_TEST_SSH_ARGS_LOG"
exit 17
MOCK_SSH
chmod +x "$TMP/bin/ssh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

check() {
  local input="$1" expected="$2"
  local output
  output="$(
    env TERM="$input" \
      PATH="$TMP/bin:$PATH" \
      AWTARCHY_TEST_SSH_TERM_LOG="$TMP/remote-term" \
      AWTARCHY_TEST_SSH_ARGS_LOG="$TMP/ssh-args" \
      bash --noprofile --norc -ic '
        source "$1"
        ssh -p 2222 "user@host with spaces"
        code=$?
        printf "TERM=%s STATUS=%s\n" "$TERM" "$code"
      ' awtarchy-ssh-test "$ROOT/bashrc" 2>/dev/null
  )" || fail "interactive shell failed for TERM=$input"

  [[ "$(<"$TMP/remote-term")" == "$expected" ]] \
    || fail "ssh TERM incorrect for $input"
  [[ "$output" == "TERM=$input STATUS=17" ]] \
    || fail "local TERM or SSH exit status changed for $input"
  [[ "$(<"$TMP/ssh-args")" == $'-p\n2222\nuser@host with spaces' ]] \
    || fail "SSH arguments changed for $input"
}

check foot xterm-256color
check foot-direct xterm-256color
check xterm-256color xterm-256color
check screen-256color screen-256color

printf 'PASS: Foot SSH TERM fallback preserves local TERM, args, and exit status\n'
