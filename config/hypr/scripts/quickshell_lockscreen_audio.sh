#!/usr/bin/env bash
set -euo pipefail

command -v cava >/dev/null 2>&1 || exit 0

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
config_path="${config_home}/quickshell/awtarchy-lock/cava.conf"

[[ -r "$config_path" ]] || exit 0

mode="${1:-balanced}"
case "$mode" in
    balanced) framerate=60 ;;
    responsive) framerate=90 ;;
    *) framerate=60 ;;
esac

runtime_home="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}}"
mkdir -p -- "$runtime_home"
runtime_config="$(mktemp "${runtime_home}/awtarchy-lock-cava.XXXXXX.conf")"
cleanup() { rm -f -- "$runtime_config"; }
trap cleanup EXIT

sed -E "s/^framerate[[:space:]]*=.*/framerate = ${framerate}/" \
    "$config_path" >"$runtime_config"
cava -p "$runtime_config"
