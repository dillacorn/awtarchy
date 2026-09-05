#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PATCH="${ROOT}/patches/aur-scanner/0001-single-auth-privileged-broker.patch"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

[[ -s "$PATCH" ]] || fail "aur-scanner privileged-broker patch is missing or empty"

for required in \
  'BrokerRequest' \
  'BrokerResponse' \
  'Command::new(sudo)' \
  '.arg("-v")' \
  '.arg("-k")' \
  'PR_SET_DUMPABLE' \
  'FD_CLOEXEC' \
  'command.stdin(Stdio::null())' \
  'O_NOFOLLOW' \
  'canonical_base' \
  'tempdir_in("/var/tmp")' \
  '--packagelist' \
  'pacman' \
  'PKGDEST'; do
  grep -Fq -- "$required" "$PATCH" \
    || fail "patch is missing required security/install contract: ${required}"
done

added_lines="$(grep '^+' "$PATCH" | grep -v '^+++' || true)"
for forbidden in \
  'PACMAN_AUTH' \
  'SUDO_ASKPASS' \
  'NOPASSWD' \
  'cmd.arg("-si")'; do
  if grep -Fq -- "$forbidden" <<<"$added_lines"; then
    fail "patch adds forbidden privilege shortcut: ${forbidden}"
  fi
done

printf 'aur-scanner privileged-broker patch contract passed.\n'
