#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

HOME_DIR="${AWTARCHY_MIC_HOME:-${HOME}}"
CONFIG_DIR="${HOME_DIR}/.config/pipewire/pipewire.conf.d"
CONFIG_FILE="${CONFIG_DIR}/99-input-denoising.conf"
STATE_DIR="${HOME_DIR}/.local/state/awtarchy/mic-suppression"
ORIGINAL_BACKUP="${STATE_DIR}/pre-awtarchy-99-input-denoising.conf"
OWNERSHIP_MARKER="# Managed by Awtarchy: microphone-noise-suppression"
SYSTEM_PLUGIN="/usr/lib/ladspa/librnnoise_ladspa.so"
PACKAGE="noise-suppression-for-voice"

test_override_allowed() {
    [[ -n ${AWTARCHY_MIC_TEST_ROOT:-}
      && ${AWTARCHY_MIC_TEST_ROOT} == /tmp/*
      && ${HOME_DIR} == "${AWTARCHY_MIC_TEST_ROOT%/}"/* ]]
}

pacman_bin() {
    if test_override_allowed && [[ -n ${AWTARCHY_MIC_TEST_PACMAN_BIN:-} ]]; then
        printf '%s\n' "$AWTARCHY_MIC_TEST_PACMAN_BIN"
    else
        printf '%s\n' /usr/bin/pacman
    fi
}

plugin_path() {
    if test_override_allowed && [[ -n ${AWTARCHY_MIC_TEST_PLUGIN_PATH:-} ]]; then
        printf '%s\n' "$AWTARCHY_MIC_TEST_PLUGIN_PATH"
    else
        printf '%s\n' "$SYSTEM_PLUGIN"
    fi
}

managed_packages_file() {
    if test_override_allowed && [[ -n ${AWTARCHY_MANAGED_PACKAGES_FILE:-} ]]; then
        printf '%s\n' "$AWTARCHY_MANAGED_PACKAGES_FILE"
    else
        printf '%s\n' /var/lib/awtarchy/managed-packages
    fi
}

root_run() {
    if [[ ${EUID} -eq 0 ]]; then
        "$@"
    else
        have sudo || die "sudo is required to install the RNNoise package."
        sudo -- "$@"
    fi
}

record_managed_package() {
    local manifest
    manifest="$(managed_packages_file)"
    root_run /usr/bin/install -d -m 0755 -- "${manifest%/*}"
    root_run /usr/bin/touch -- "$manifest"
    if ! grep -Fxq "$PACKAGE" "$manifest" 2>/dev/null; then
        printf '%s\n' "$PACKAGE" | root_run /usr/bin/tee -a "$manifest" >/dev/null
    fi
    root_run /usr/bin/sort -u -o "$manifest" "$manifest"
    root_run /usr/bin/chmod 0644 "$manifest"
}

package_installed() {
    local pacman
    pacman="$(pacman_bin)"
    [[ -x "$pacman" ]] && "$pacman" -Qq "$PACKAGE" >/dev/null 2>&1
}

ensure_package() {
    local pacman was_installed=0
    pacman="$(pacman_bin)"
    [[ -x "$pacman" ]] || die "pacman is unavailable; cannot install ${PACKAGE}."
    package_installed && was_installed=1
    if (( was_installed == 0 )); then
        log "Installing ${PACKAGE} from the Arch repositories..."
        root_run "$pacman" -S --needed --noconfirm "$PACKAGE"
        package_installed || die "${PACKAGE} installation completed without a detectable package."
        record_managed_package
    fi
    [[ -f "$(plugin_path)" ]] || die "RNNoise LADSPA plugin is missing: $(plugin_path)"
}

config_owned() {
    [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] && grep -Fq "$OWNERSHIP_MARKER" "$CONFIG_FILE"
}

config_compatible() {
    [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || return 1
    grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*libpipewire-module-filter-chain([[:space:]]|$)' "$CONFIG_FILE" \
        && grep -Eq '^[[:space:]]*node\.name[[:space:]]*=[[:space:]]*"rnnoise_source"[[:space:]]*$' "$CONFIG_FILE" \
        && grep -Eq '^[[:space:]]*node\.name[[:space:]]*=[[:space:]]*"capture\.rnnoise_source"[[:space:]]*$' "$CONFIG_FILE" \
        && grep -Fq '/usr/lib/ladspa/librnnoise_ladspa.so' "$CONFIG_FILE" \
        && grep -Eq '^[[:space:]]*label[[:space:]]*=[[:space:]]*noise_suppressor_(mono|stereo)[[:space:]]*$' "$CONFIG_FILE"
}

config_kind() {
    if [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
        printf '%s\n' absent
    elif [[ -L "$CONFIG_FILE" ]]; then
        printf '%s\n' conflict
    elif config_owned; then
        printf '%s\n' owned
    elif config_compatible; then
        printf '%s\n' compatible-unmanaged
    else
        printf '%s\n' conflict
    fi
}

config_mode() {
    [[ -r "$CONFIG_FILE" ]] || return 1
    if grep -Fq 'label = noise_suppressor_stereo' "$CONFIG_FILE"; then
        printf '%s\n' stereo
    elif grep -Fq 'label = noise_suppressor_mono' "$CONFIG_FILE"; then
        printf '%s\n' mono
    else
        return 1
    fi
}

config_target() {
    [[ -r "$CONFIG_FILE" ]] || return 1
    sed -n 's/^[[:space:]]*target\.object[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$CONFIG_FILE" | head -n1
}

preserve_unmanaged_config() {
    [[ "$(config_kind)" == compatible-unmanaged ]] || return 0
    mkdir -p -- "$STATE_DIR"
    if [[ ! -e "$ORIGINAL_BACKUP" ]]; then
        cp -a -- "$CONFIG_FILE" "$ORIGINAL_BACKUP"
        chmod 0600 "$ORIGINAL_BACKUP"
        log "Preserved the pre-Awtarchy RNNoise config at ${ORIGINAL_BACKUP}"
    fi
}

pipewire_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

render_config() {
    local mode="$1" target="${2:-}" label target_line=""
    case "$mode" in
        mono) label=noise_suppressor_mono ;;
        stereo) label=noise_suppressor_stereo ;;
        *) die "Unknown RNNoise mode: ${mode}" ;;
    esac
    if [[ -n "$target" ]]; then
        target_line="            target.object = \"$(pipewire_escape "$target")\""
    fi
    cat <<EOF
${OWNERSHIP_MARKER}
# Generated by Awtarchy. Edit through: awtarchy mic-suppression
# 48 kHz is required by noise-suppression-for-voice.
context.modules = [
{   name = libpipewire-module-filter-chain
    args = {
        node.description = "Noise Canceling source"
        media.name = "Noise Canceling source"
        filter.graph = {
            nodes = [
                {
                    type = ladspa
                    name = rnnoise
                    plugin = /usr/lib/ladspa/librnnoise_ladspa.so
                    label = ${label}
                    control = {
                        "VAD Threshold (%)" = 50.0
                        "VAD Grace Period (ms)" = 200
                        "Retroactive VAD Grace (ms)" = 0
                    }
                }
            ]
        }
        capture.props = {
            node.name = "capture.rnnoise_source"
            node.passive = true
            audio.rate = 48000
${target_line}
        }
        playback.props = {
            node.name = "rnnoise_source"
            media.class = Audio/Source
            audio.rate = 48000
        }
    }
}
]
EOF
}

atomic_write_config() {
    local content="$1" tmp
    mkdir -p -- "$CONFIG_DIR"
    [[ ! -L "$CONFIG_DIR" ]] || die "Refusing to write through symlinked PipeWire config directory: ${CONFIG_DIR}"
    [[ ! -L "$CONFIG_FILE" ]] || die "Refusing to replace symlinked RNNoise config: ${CONFIG_FILE}"
    tmp="$(mktemp "${CONFIG_DIR}/.99-input-denoising.conf.XXXXXX")"
    printf '%s\n' "$content" >"$tmp"
    chmod 0644 "$tmp"
    mv -Tf -- "$tmp" "$CONFIG_FILE"
}

audio_session_available() {
    have systemctl \
        && systemctl --user is-active --quiet pipewire.service >/dev/null 2>&1 \
        && systemctl --user is-active --quiet wireplumber.service >/dev/null 2>&1
}

warn_restart() {
    warn "Applying this change restarts PipeWire, PipeWire-Pulse, and WirePlumber."
    warn "Active games, VOIP apps, browsers, OBS/recording software, or other programs using the microphone/audio may need to be restarted afterward."
}

restart_audio() {
    if ! audio_session_available; then
        warn "No active user PipeWire/WirePlumber session was detected. The configuration will load on the next audio session/login."
        return 0
    fi
    warn_restart
    systemctl --user daemon-reload
    systemctl --user reset-failed
    systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service
    sleep 0.5
    systemctl --user is-active --quiet pipewire.service || die "PipeWire did not return to an active state."
    systemctl --user is-active --quiet pipewire-pulse.service || die "PipeWire-Pulse did not return to an active state."
    systemctl --user is-active --quiet wireplumber.service || die "WirePlumber did not return to an active state."
    have wpctl && wpctl status >/dev/null || die "wpctl could not query the restarted audio graph."
    have pactl && pactl info >/dev/null || die "pactl could not query the restarted PipeWire-Pulse server."
}

rnnoise_source_present() {
    have pactl || return 1
    pactl list short sources 2>/dev/null | awk '$2 == "rnnoise_source" { found=1 } END { exit !found }'
}

validate_enabled() {
    local mode="$1"
    package_installed || die "${PACKAGE} is not installed."
    [[ -f "$(plugin_path)" ]] || die "RNNoise LADSPA plugin is missing."
    config_compatible || die "RNNoise PipeWire config is missing or malformed."
    [[ "$(config_mode)" == "$mode" ]] || die "RNNoise mode did not apply as ${mode}."
    if audio_session_available; then
        rnnoise_source_present || die "PipeWire restarted, but rnnoise_source did not appear."
    fi
}

validate_disabled() {
    [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || die "RNNoise config still exists after disable."
    if audio_session_available && rnnoise_source_present; then
        die "rnnoise_source still exists after disabling and restarting PipeWire."
    fi
}

enable_mode() {
    local mode="${1:-mono}" kind existing_target="" target="" rendered=""
    case "$mode" in mono|stereo) ;; *) die "Mode must be mono or stereo." ;; esac
    kind="$(config_kind)"
    [[ "$kind" != conflict ]] || die "A non-Awtarchy PipeWire config already exists at ${CONFIG_FILE}; refusing to overwrite it."
    ensure_package
    if [[ "$kind" == compatible-unmanaged ]]; then
        preserve_unmanaged_config
        target="$(config_target 2>/dev/null || true)"
    elif [[ "$kind" == owned ]]; then
        existing_target="$(config_target 2>/dev/null || true)"
        target="$existing_target"
    fi
    if [[ -n "$target" ]]; then
        log "Using physical capture target: ${target}"
    else
        log "Leaving capture device selection to PipeWire/WirePlumber automatic routing."
    fi
    rendered="$(render_config "$mode" "$target")"
    atomic_write_config "$rendered"
    restart_audio
    validate_enabled "$mode"
    log "Microphone noise suppression: enabled (${mode})"
    log "Input device: Noise Canceling source"
    [[ "$mode" == stereo ]] && warn "Stereo RNNoise is intended only for a true stereo microphone and roughly doubles processing."
    warn "Restart microphone-using applications if they kept an old PipeWire stream open."
}

disable_suppression() {
    local kind
    kind="$(config_kind)"
    case "$kind" in
        absent)
            log "Microphone noise suppression is already disabled."
            return 0
            ;;
        conflict)
            die "Refusing to remove unrelated PipeWire config at ${CONFIG_FILE}."
            ;;
        compatible-unmanaged)
            preserve_unmanaged_config
            ;;
        owned) ;;
    esac
    rm -f -- "$CONFIG_FILE"
    restart_audio
    validate_disabled
    log "Microphone noise suppression: disabled"
    log "The ${PACKAGE} package was left installed."
    warn "Restart microphone-using applications if they kept an old PipeWire stream open."
}

configured_healthy() {
    package_installed \
        && [[ -f "$(plugin_path)" ]] \
        && config_compatible \
        || return 1
    if audio_session_available; then
        rnnoise_source_present
    fi
}

status() {
    local kind mode="off" target="" package_state="missing" plugin_state="missing" source_state="inactive"
    kind="$(config_kind)"
    mode="$(config_mode 2>/dev/null || printf off)"
    target="$(config_target 2>/dev/null || true)"
    package_installed && package_state=installed
    [[ -f "$(plugin_path)" ]] && plugin_state=present
    rnnoise_source_present && source_state=present
    printf 'Microphone noise suppression\n'
    printf '  Config: %s\n' "$kind"
    printf '  Mode: %s\n' "$mode"
    printf '  Package: %s\n' "$package_state"
    printf '  Plugin: %s\n' "$plugin_state"
    printf '  Capture target: %s\n' "${target:-WirePlumber automatic/default}"
    printf '  Virtual source: %s\n' "$source_state"
    if audio_session_available; then
        printf '  Audio services: active\n'
    else
        printf '  Audio services: not currently reachable\n'
    fi
}

usage() {
    cat <<'EOF'
Usage:
  awtarchy mic-suppression status
  awtarchy mic-suppression enable [mono|stereo]
  awtarchy mic-suppression mono
  awtarchy mic-suppression stereo
  awtarchy mic-suppression disable
  awtarchy mic-suppression restart

Mono is recommended for normal microphones. Stereo should be used only for a
true stereo microphone. Applying changes restarts PipeWire/WirePlumber; active
microphone/audio applications may need to be restarted afterward.
EOF
}

case "${1:-status}" in
    status) status ;;
    is-configured) configured_healthy ;;
    enable) enable_mode "${2:-mono}" ;;
    mono) enable_mode mono ;;
    stereo) enable_mode stereo ;;
    disable) disable_suppression ;;
    restart) restart_audio; status ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
