#!/usr/bin/env bash
# Capture frozen Hyprland output frames for the secure lockscreen transition.

set -euo pipefail
umask 077

RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
CAPTURE_ROOT="${RUNTIME_DIR}/awtarchy-lock-transition"
PREPARED_POINTER="${CAPTURE_ROOT}/prepared"
OUTPUTS=()

fail() {
    printf 'quickshell_lockscreen_capture.sh: %s\n' "$*" >&2
    return 1
}

validate_runtime_dir() {
    if [[ -z "$RUNTIME_DIR" ]]; then
        fail 'XDG_RUNTIME_DIR is not set.'
        return 1
    fi
    if [[ ! -d "$RUNTIME_DIR" || -L "$RUNTIME_DIR" || ! -O "$RUNTIME_DIR" ]]; then
        fail 'XDG_RUNTIME_DIR is not an owned regular directory.'
        return 1
    fi
}

ensure_capture_root() {
    validate_runtime_dir || return 1

    if [[ -e "$CAPTURE_ROOT" || -L "$CAPTURE_ROOT" ]]; then
        if [[ ! -d "$CAPTURE_ROOT" || -L "$CAPTURE_ROOT" || ! -O "$CAPTURE_ROOT" ]]; then
            fail 'capture root is not an owned regular directory.'
            return 1
        fi
    else
        mkdir -m 700 -- "$CAPTURE_ROOT"
    fi

    chmod 700 -- "$CAPTURE_ROOT"
}

safe_output_name() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

refresh_outputs() {
    mapfile -t OUTPUTS < <(hyprctl monitors -j | jq -er '.[].name')
    if ((${#OUTPUTS[@]} == 0)); then
        fail 'Hyprland reported no active outputs.'
        return 1
    fi

    local output
    for output in "${OUTPUTS[@]}"; do
        if ! safe_output_name "$output"; then
            fail "unsafe output name: $output"
            return 1
        fi
    done
}

validate_capture_dir() {
    local target="$1"
    local parent base

    ensure_capture_root || return 1
    parent="$(dirname -- "$target")"
    base="$(basename -- "$target")"

    if [[ "$parent" != "$CAPTURE_ROOT" ]]; then
        fail 'capture directory is outside the capture root.'
        return 1
    fi
    if [[ ! "$base" =~ ^capture\.[A-Za-z0-9]+$ ]]; then
        fail 'capture directory name is invalid.'
        return 1
    fi
    if [[ ! -d "$target" || -L "$target" || ! -O "$target" ]]; then
        fail 'capture directory is not an owned regular directory.'
        return 1
    fi
}

validate_capture_file() {
    local target="$1"
    if [[ ! -f "$target" || -L "$target" || ! -O "$target" || ! -r "$target" || ! -s "$target" ]]; then
        fail "invalid capture file: $target"
        return 1
    fi
}

remove_owned_capture_dir() {
    local target="$1"

    validate_capture_dir "$target" || return 1

    if [[ -f "$PREPARED_POINTER" && ! -L "$PREPARED_POINTER" && -O "$PREPARED_POINTER" ]]; then
        local prepared=""
        IFS= read -r prepared <"$PREPARED_POINTER" || prepared=""
        if [[ "$prepared" == "$target" ]]; then
            rm -f -- "$PREPARED_POINTER"
        fi
    fi

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

new_capture_dir() {
    local capture_dir
    capture_dir="$(mktemp -d "${CAPTURE_ROOT}/capture.XXXXXX")"
    chmod 700 -- "$capture_dir"
    printf '%s\n' "$capture_dir"
}

capture_outputs() {
    local capture_dir="$1"
    local suffix="$2"
    local output output_file

    for output in "${OUTPUTS[@]}"; do
        output_file="${capture_dir}/${output}${suffix}"
        if ! grim -l 1 -o "$output" "$output_file"; then
            fail "failed to capture output: $output"
            return 1
        fi
        chmod 600 -- "$output_file"
        validate_capture_file "$output_file" || return 1
    done
}

prepare_capture() {
    local capture_dir output source transition_file

    ensure_capture_root || return 1
    rm -f -- "$PREPARED_POINTER"
    remove_stale_captures
    refresh_outputs || return 1

    capture_dir="$(new_capture_dir)" || return 1
    if ! capture_outputs "$capture_dir" '.png'; then
        rm -rf -- "$capture_dir"
        return 1
    fi

    # Direct lock triggers have one real pre-lock frame. Mirror it into the
    # transition-source slot so the secure surface can use one composition path
    # for both direct and staged Power Menu locking.
    for output in "${OUTPUTS[@]}"; do
        source="${capture_dir}/${output}.png"
        transition_file="${capture_dir}/${output}.transition.png"
        if ! cp -- "$source" "$transition_file"; then
            rm -rf -- "$capture_dir"
            fail "failed to stage transition copy for output: $output"
            return 1
        fi
        chmod 600 -- "$transition_file"
        if ! validate_capture_file "$transition_file"; then
            rm -rf -- "$capture_dir"
            return 1
        fi
    done

    printf '%s\n' "$capture_dir"
}

stage_begin() {
    local capture_dir

    ensure_capture_root || return 1
    discard_prepared_capture || true
    remove_stale_captures
    refresh_outputs || return 1

    capture_dir="$(new_capture_dir)" || return 1
    if ! capture_outputs "$capture_dir" '.transition.png'; then
        rm -rf -- "$capture_dir"
        return 1
    fi

    printf '%s\n' "$capture_dir"
}

publish_prepared_capture() {
    local capture_dir="$1"
    local pointer_tmp

    pointer_tmp="$(mktemp "${CAPTURE_ROOT}/prepared.XXXXXX")"
    printf '%s\n' "$capture_dir" >"$pointer_tmp"
    chmod 600 -- "$pointer_tmp"
    mv -f -- "$pointer_tmp" "$PREPARED_POINTER"
}

stage_complete() {
    local capture_dir="$1"
    local output

    validate_capture_dir "$capture_dir" || return 1
    refresh_outputs || {
        rm -rf -- "$capture_dir"
        return 1
    }

    for output in "${OUTPUTS[@]}"; do
        if ! validate_capture_file "${capture_dir}/${output}.transition.png"; then
            rm -rf -- "$capture_dir"
            return 1
        fi
    done

    if ! capture_outputs "$capture_dir" '.png'; then
        rm -rf -- "$capture_dir"
        return 1
    fi

    if ! publish_prepared_capture "$capture_dir"; then
        rm -rf -- "$capture_dir"
        return 1
    fi
}

consume_prepared_capture() {
    local capture_dir parent base clean_file output
    local found_pair=0

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

    # Consumption is intentionally independent of a second Hyprland monitor
    # query. The complete private bundle was already validated against the live
    # output set at stage-complete; a hotplug after that point safely falls back
    # to the lock surface's black backing for any newly added output.
    shopt -s nullglob
    for clean_file in "$capture_dir"/*.png; do
        [[ "$clean_file" == *.transition.png ]] && continue
        output="$(basename -- "$clean_file" .png)"
        if ! safe_output_name "$output" \
            || ! validate_capture_file "$clean_file" \
            || ! validate_capture_file "${capture_dir}/${output}.transition.png"; then
            shopt -u nullglob
            rm -rf -- "$capture_dir"
            return 1
        fi
        found_pair=1
    done
    shopt -u nullglob

    if (( ! found_pair )); then
        rm -rf -- "$capture_dir"
        return 1
    fi

    printf '%s\n' "$capture_dir"
}

discard_prepared_capture() {
    local capture_dir="" parent base

    ensure_capture_root || return 1
    if [[ ! -e "$PREPARED_POINTER" && ! -L "$PREPARED_POINTER" ]]; then
        return 0
    fi
    if [[ ! -f "$PREPARED_POINTER" || -L "$PREPARED_POINTER" || ! -O "$PREPARED_POINTER" ]]; then
        rm -f -- "$PREPARED_POINTER"
        return 1
    fi

    IFS= read -r capture_dir <"$PREPARED_POINTER" || capture_dir=""
    rm -f -- "$PREPARED_POINTER"

    parent="$(dirname -- "$capture_dir")"
    base="$(basename -- "$capture_dir")"
    if [[ "$parent" == "$CAPTURE_ROOT" && "$base" =~ ^capture\.[A-Za-z0-9]+$ \
        && -d "$capture_dir" && ! -L "$capture_dir" && -O "$capture_dir" ]]; then
        rm -rf -- "$capture_dir"
    fi
}

usage() {
    cat <<'EOF'
Usage: quickshell_lockscreen_capture.sh <command> [argument]

Commands:
  prepare                       Capture every active output for a direct lock.
  stage-begin                   Capture the visible pre-Power-Menu transition frame.
  stage-complete <capture-dir>  Add the clean desktop frame and publish the bundle.
  consume-prepared              Return and consume the completed Power Menu bundle.
  discard-prepared              Remove a completed but unused Power Menu bundle.
  cleanup <capture-dir>         Remove one validated capture directory.
EOF
}

case "${1:-}" in
    prepare)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        prepare_capture
        ;;
    stage-begin)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        stage_begin
        ;;
    stage-complete)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        stage_complete "$2"
        ;;
    consume-prepared)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        consume_prepared_capture
        ;;
    discard-prepared)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        discard_prepared_capture
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
