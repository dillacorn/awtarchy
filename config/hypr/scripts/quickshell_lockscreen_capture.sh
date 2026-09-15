#!/usr/bin/env bash
# Capture frozen Hyprland output frames for the secure lockscreen transition.

set -euo pipefail
umask 077

RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
CAPTURE_ROOT="${RUNTIME_DIR}/awtarchy-lock-transition"
PREPARED_POINTER="${CAPTURE_ROOT}/prepared"

fail() {
    printf 'quickshell_lockscreen_capture.sh: %s\n' "$*" >&2
    return 1
}

validate_runtime_dir() {
    [[ -n "$RUNTIME_DIR" ]] || fail 'XDG_RUNTIME_DIR is not set.'
    [[ -d "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" && -O "$RUNTIME_DIR" ]] \
        || fail 'XDG_RUNTIME_DIR is not an owned regular directory.'
}

ensure_capture_root() {
    validate_runtime_dir || return 1

    if [[ -e "$CAPTURE_ROOT" || -L "$CAPTURE_ROOT" ]]; then
        [[ -d "$CAPTURE_ROOT" && ! -L "$CAPTURE_ROOT" && -O "$CAPTURE_ROOT" ]] \
            || fail 'capture root is not an owned regular directory.'
    else
        mkdir -m 700 -- "$CAPTURE_ROOT"
    fi

    chmod 700 -- "$CAPTURE_ROOT"
}

safe_output_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

remove_owned_capture_dir() {
    local target="$1"
    local parent base

    ensure_capture_root || return 1
    parent="$(dirname -- "$target")"
    base="$(basename -- "$target")"

    [[ "$parent" == "$CAPTURE_ROOT" ]] || fail 'refusing cleanup outside the capture root.'
    [[ "$base" =~ ^capture\.[A-Za-z0-9]+$ ]] || fail 'refusing cleanup of a non-capture directory.'
    [[ -d "$target" && ! -L "$target" && -O "$target" ]] \
        || fail 'capture directory is not an owned regular directory.'

    rm -rf -- "$target"
}

remove_stale_captures() {
    local stale

    shopt -s nullglob
    for stale in "$CAPTURE_ROOT"/capture.*; do
        [[ -d "$stale" && ! -L "$stale" && -O "$stale" ]] || continue
        rm -rf -- "$stale"
    done
    shopt -u nullglob
}

prepare_capture() {
    local capture_dir output output_file
    local -a outputs=()

    ensure_capture_root || return 1
    remove_stale_captures

    mapfile -t outputs < <(hyprctl monitors -j | jq -er '.[].name')
    ((${#outputs[@]} > 0)) || fail 'Hyprland reported no active outputs.'

    for output in "${outputs[@]}"; do
        safe_output_name "$output" || fail "unsafe output name: $output"
    done

    capture_dir="$(mktemp -d "${CAPTURE_ROOT}/capture.XXXXXX")"
    chmod 700 -- "$capture_dir"

    for output in "${outputs[@]}"; do
        output_file="${capture_dir}/${output}.png"
        if ! grim -l 1 -o "$output" "$output_file"; then
            rm -rf -- "$capture_dir"
            fail "failed to capture output: $output"
            return 1
        fi

        chmod 600 -- "$output_file"
        if [[ ! -f "$output_file" || -L "$output_file" || ! -O "$output_file" \
            || ! -r "$output_file" || ! -s "$output_file" ]]; then
            rm -rf -- "$capture_dir"
            fail "invalid capture file for output: $output"
            return 1
        fi
    done

    printf '%s\n' "$capture_dir"
}


stage_capture() {
    local capture_dir pointer_tmp

    ensure_capture_root || return 1
    rm -f -- "$PREPARED_POINTER"
    capture_dir="$(prepare_capture)" || return 1

    pointer_tmp="$(mktemp "${CAPTURE_ROOT}/prepared.XXXXXX")"
    printf '%s\n' "$capture_dir" >"$pointer_tmp"
    chmod 600 -- "$pointer_tmp"
    mv -f -- "$pointer_tmp" "$PREPARED_POINTER"
}

consume_prepared_capture() {
    local capture_dir parent base

    ensure_capture_root || return 1
    [[ -f "$PREPARED_POINTER" && ! -L "$PREPARED_POINTER" && -O "$PREPARED_POINTER" ]] \
        || return 1

    IFS= read -r capture_dir <"$PREPARED_POINTER" || capture_dir=""
    rm -f -- "$PREPARED_POINTER"

    parent="$(dirname -- "$capture_dir")"
    base="$(basename -- "$capture_dir")"
    [[ "$parent" == "$CAPTURE_ROOT" ]] || return 1
    [[ "$base" =~ ^capture\.[A-Za-z0-9]+$ ]] || return 1
    [[ -d "$capture_dir" && ! -L "$capture_dir" && -O "$capture_dir" ]] || return 1

    printf '%s\n' "$capture_dir"
}

usage() {
    cat <<'EOF'
Usage: quickshell_lockscreen_capture.sh <command> [argument]

Commands:
  prepare               Capture every active Hyprland output.
  stage                 Capture every active output for the next Power Menu lock.
  consume-prepared      Return and consume the staged Power Menu capture.
  cleanup <capture-dir> Remove one validated capture directory.
EOF
}

case "${1:-}" in
    prepare)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        prepare_capture
        ;;
    stage)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        stage_capture
        ;;
    consume-prepared)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        consume_prepared_capture
        ;;
    cleanup)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        remove_owned_capture_dir "$2"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
