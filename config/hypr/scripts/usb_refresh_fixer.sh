#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# usb_refresh_fixer.sh
# ============================================================================
#
# One-time setup:
# - On first run, this script opens a terminal, explains the sudo setup,
#   asks for sudo once, installs a root-owned helper + config + sudoers rule,
#   then runs the USB refresh.
# - Later runs use that installed helper and do not ask for sudo again.
#
# Runtime behavior:
# - Only resets devices when this script is run
# - Does not monitor in the background
# - Only works if Linux already detects the device
# - If the device is missing from lsusb/sysfs, there is nothing to reset
#
# Find device IDs:
#   lsusb
#
# Example lsusb line:
#   Bus 005 Device 004: ID 20b1:3008 XMOS Ltd iFi (by AMR) HD USB Audio
#
# Use the ID field only:
#   DEVICE_ID_MATCH_CSV="20b1:3008"
#   DEVICE_ID_MATCH_CSV="20b1:3008,1234:5678"
#
# Optional serial filtering:
# - Only use serial if you have duplicate identical devices
# - Exact match only
#   DEVICE_SERIAL_MATCH_CSV="ABC123"
#   DEVICE_SERIAL_MATCH_CSV="ABC123,XYZ789"
#
# ============================================================================
# USER CONFIG
# ============================================================================

# Exact vendor:product IDs from lsusb
DEVICE_ID_MATCH_CSV="20b1:3008"

# Optional exact USB serial values from sysfs
DEVICE_SERIAL_MATCH_CSV=""

# Delay before the privileged helper performs the reset
BOOT_DELAY_SECONDS=0

# Terminal preference for the one-time interactive sudo setup
# Leave empty for auto-detect
# Supported: footclient,foot,kitty,alacritty,xterm
TERMINAL_CMD=""

# Window title used for the one-time setup terminal
TERMINAL_TITLE="usb_refresh_fixer"


# ============================================================================
# SCRIPT
# ============================================================================

SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
RUN_USER="${SUDO_USER:-${USER:-$(id -un)}}"
HELPER_PATH="/usr/local/bin/usb_refresh_fixer-root"
CONFIG_DIR="/etc/usb_refresh_fixer"
CONFIG_PATH="${CONFIG_DIR}/${RUN_USER}.conf"
SUDOERS_PATH="/etc/sudoers.d/usb_refresh_fixer-${RUN_USER}"

log() {
    printf '[usb_refresh_fixer] %s\n' "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

trim_string() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

validate_config() {
    [[ "$BOOT_DELAY_SECONDS" =~ ^[0-9]+$ ]] || die "BOOT_DELAY_SECONDS must be a non-negative integer"
    [[ -n "$DEVICE_ID_MATCH_CSV" ]] || die "set DEVICE_ID_MATCH_CSV"
}

config_fingerprint() {
    printf '%s\n%s\n%s\n' \
        "$DEVICE_ID_MATCH_CSV" \
        "$DEVICE_SERIAL_MATCH_CSV" \
        "$BOOT_DELAY_SECONDS" | sha256sum | awk '{print $1}'
}

installed_fingerprint() {
    [[ -r "$CONFIG_PATH" ]] || return 1
    awk -F'=' '/^CONFIG_FINGERPRINT=/{gsub(/^["\047]|["\047]$/, "", $2); print $2; exit}' "$CONFIG_PATH"
}

need_install() {
    [[ -x "$HELPER_PATH" ]] || return 0
    [[ -r "$CONFIG_PATH" ]] || return 0
    [[ -r "$SUDOERS_PATH" ]] || return 0

    local current installed
    current="$(config_fingerprint)"
    installed="$(installed_fingerprint || true)"
    [[ -n "$installed" && "$installed" == "$current" ]] || return 0

    return 1
}

select_terminal() {
    if [[ -n "$TERMINAL_CMD" ]]; then
        command -v "$TERMINAL_CMD" >/dev/null 2>&1 || die "TERMINAL_CMD not found: $TERMINAL_CMD"
        printf '%s' "$TERMINAL_CMD"
        return 0
    fi

    local term
    for term in footclient foot kitty alacritty xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            printf '%s' "$term"
            return 0
        fi
    done

    return 1
}

spawn_terminal() {
    local term cmd_string
    term="$(select_terminal)" || die "no supported terminal found for one-time sudo setup"
    cmd_string="USBRF_PAUSE_ON_EXIT=1 exec $(printf '%q' "$SELF_PATH") --interactive"

    case "$term" in
        footclient)
            nohup footclient --app-id "$TERMINAL_TITLE" --title "$TERMINAL_TITLE" bash -lc "$cmd_string" >/dev/null 2>&1 &
            ;;
        foot)
            nohup foot --app-id "$TERMINAL_TITLE" --title "$TERMINAL_TITLE" bash -lc "$cmd_string" >/dev/null 2>&1 &
            ;;
        kitty)
            nohup kitty --class "$TERMINAL_TITLE" --title "$TERMINAL_TITLE" bash -lc "$cmd_string" >/dev/null 2>&1 &
            ;;
        alacritty)
            nohup alacritty --class "$TERMINAL_TITLE" --title "$TERMINAL_TITLE" -e bash -lc "$cmd_string" >/dev/null 2>&1 &
            ;;
        xterm)
            nohup xterm -T "$TERMINAL_TITLE" -e bash -lc "$cmd_string" >/dev/null 2>&1 &
            ;;
        *)
            die "unsupported terminal launcher: $term"
            ;;
    esac
}

generate_helper() {
    cat <<'EOF_HELPER'
#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[usb_refresh_fixer-root] %s\n' "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

trim_file() {
    local file="$1"
    [[ -r "$file" ]] || return 1
    tr -d '\n' < "$file"
}

trim_string() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

csv_to_array() {
    local csv="$1"
    local -n out_ref="$2"
    out_ref=()

    local part
    IFS=',' read -r -a __raw_parts <<< "$csv"
    for part in "${__raw_parts[@]}"; do
        part="$(trim_string "$part")"
        [[ -n "$part" ]] && out_ref+=("$part")
    done
}

validate_id_list() {
    local ids=("$@")
    local id
    for id in "${ids[@]}"; do
        [[ "$id" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]] || die "invalid ID in DEVICE_ID_MATCH_CSV: $id"
    done
}

string_in_csv_exact_ci() {
    local needle="${1,,}"
    shift
    local item
    for item in "$@"; do
        [[ "${item,,}" == "$needle" ]] && return 0
    done
    return 1
}

match_device() {
    local dev="$1"

    [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]] || return 1

    local vid pid serial id
    vid="$(trim_file "$dev/idVendor" 2>/dev/null || true)"
    pid="$(trim_file "$dev/idProduct" 2>/dev/null || true)"
    serial="$(trim_file "$dev/serial" 2>/dev/null || true)"

    [[ -n "$vid" && -n "$pid" ]] || return 1

    id="${vid,,}:${pid,,}"

    if (( ${#DEVICE_ID_MATCHES[@]} > 0 )); then
        string_in_csv_exact_ci "$id" "${DEVICE_ID_MATCHES[@]}" || return 1
    fi

    if (( ${#DEVICE_SERIAL_MATCHES[@]} > 0 )); then
        [[ -n "$serial" ]] || return 1
        string_in_csv_exact_ci "$serial" "${DEVICE_SERIAL_MATCHES[@]}" || return 1
    fi

    return 0
}

reset_device() {
    local dev="$1"

    local vid pid product manufacturer serial busnum devnum label
    vid="$(trim_file "$dev/idVendor" 2>/dev/null || true)"
    pid="$(trim_file "$dev/idProduct" 2>/dev/null || true)"
    product="$(trim_file "$dev/product" 2>/dev/null || true)"
    manufacturer="$(trim_file "$dev/manufacturer" 2>/dev/null || true)"
    serial="$(trim_file "$dev/serial" 2>/dev/null || true)"
    busnum="$(trim_file "$dev/busnum" 2>/dev/null || true)"
    devnum="$(trim_file "$dev/devnum" 2>/dev/null || true)"

    label="$(trim_string "${manufacturer} ${product}")"
    [[ -z "$label" ]] && label="Unknown USB Device"
    label="${label} (${vid}:${pid})"
    [[ -n "$serial" ]] && label="${label} serial=${serial}"

    log "matched: $label"

    if [[ -w "$dev/power/control" ]]; then
        echo on > "$dev/power/control"
        log "set power/control=on"
    fi

    if [[ -w "$dev/power/autosuspend_delay_ms" ]]; then
        echo -1 > "$dev/power/autosuspend_delay_ms"
        log "set power/autosuspend_delay_ms=-1"
    fi

    if command -v usbreset >/dev/null 2>&1 && [[ -n "$busnum" && -n "$devnum" ]]; then
        local busdev
        busdev="$(printf '%03d/%03d' "$busnum" "$devnum")"
        log "usbreset $busdev"
        usbreset "$busdev"
        return 0
    fi

    if [[ -w "$dev/authorized" ]]; then
        log "usbreset not found, using authorized 0/1 toggle"
        echo 0 > "$dev/authorized"
        sleep 1
        echo 1 > "$dev/authorized"
        return 0
    fi

    die "could not reset device: usbreset missing and authorized toggle unavailable"
}

main() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"
    [[ $# -eq 0 ]] || die "this helper takes no arguments"

    local run_user config_path
    run_user="${SUDO_USER:-}"
    [[ -n "$run_user" ]] || die "SUDO_USER is empty"

    config_path="/etc/usb_refresh_fixer/${run_user}.conf"
    [[ -r "$config_path" ]] || die "config not found: $config_path"

    # shellcheck disable=SC1090
    source "$config_path"

    [[ "$BOOT_DELAY_SECONDS" =~ ^[0-9]+$ ]] || die "BOOT_DELAY_SECONDS must be a non-negative integer"
    [[ -n "$DEVICE_ID_MATCH_CSV" ]] || die "set DEVICE_ID_MATCH_CSV"

    csv_to_array "$DEVICE_ID_MATCH_CSV" DEVICE_ID_MATCHES
    csv_to_array "$DEVICE_SERIAL_MATCH_CSV" DEVICE_SERIAL_MATCHES
    validate_id_list "${DEVICE_ID_MATCHES[@]}"

    if (( BOOT_DELAY_SECONDS > 0 )); then
        log "sleeping ${BOOT_DELAY_SECONDS}s before reset"
        sleep "$BOOT_DELAY_SECONDS"
    fi

    local matches=()
    local dev

    for dev in /sys/bus/usb/devices/*; do
        [[ -d "$dev" ]] || continue
        if match_device "$dev"; then
            matches+=("$dev")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        die "no matching detected USB device found. if Linux does not currently detect the device, this script cannot reset it."
    fi

    log "matched ${#matches[@]} device(s)"

    for dev in "${matches[@]}"; do
        reset_device "$dev"
    done

    udevadm settle --timeout=10 || true
    log "done"
}

DEVICE_ID_MATCHES=()
DEVICE_SERIAL_MATCHES=()

main "$@"
EOF_HELPER
}

generate_root_config() {
    local fp
    fp="$(config_fingerprint)"

    cat <<EOF_CONF
DEVICE_ID_MATCH_CSV=$(printf '%q' "$DEVICE_ID_MATCH_CSV")
DEVICE_SERIAL_MATCH_CSV=$(printf '%q' "$DEVICE_SERIAL_MATCH_CSV")
BOOT_DELAY_SECONDS=$(printf '%q' "$BOOT_DELAY_SECONDS")
CONFIG_FINGERPRINT=$(printf '%q' "$fp")
EOF_CONF
}

generate_sudoers() {
    printf '%s ALL=(root) NOPASSWD: %s\n' "$RUN_USER" "$HELPER_PATH"
}

install_privileged_assets() {
    local tmp_helper tmp_conf tmp_sudoers
    tmp_helper="$(mktemp)"
    tmp_conf="$(mktemp)"
    tmp_sudoers="$(mktemp)"
    trap 'rm -f "$tmp_helper" "$tmp_conf" "$tmp_sudoers"' RETURN

    generate_helper > "$tmp_helper"
    chmod 755 "$tmp_helper"

    generate_root_config > "$tmp_conf"
    chmod 644 "$tmp_conf"

    generate_sudoers > "$tmp_sudoers"
    chmod 440 "$tmp_sudoers"

    sudo -v || die "sudo authentication failed"
    sudo install -d -o root -g root -m 0755 "$CONFIG_DIR"
    sudo install -o root -g root -m 0755 "$tmp_helper" "$HELPER_PATH"
    sudo install -o root -g root -m 0644 "$tmp_conf" "$CONFIG_PATH"
    sudo visudo -cf "$tmp_sudoers" >/dev/null
    sudo install -o root -g root -m 0440 "$tmp_sudoers" "$SUDOERS_PATH"
}

run_interactive() {
    validate_config

    if need_install; then
        echo
        echo "usb_refresh_fixer.sh needs to install a sudo user rule for this USB task so it will not ask for sudo again on later runs."
        echo
        install_privileged_assets
        echo
        echo "Install complete. Future runs should not ask for sudo again."
        echo
    fi

    sudo -n "$HELPER_PATH"

    if [[ "${USBRF_PAUSE_ON_EXIT:-0}" == "1" ]]; then
        echo
        read -r -p "Press Enter to close..."
    fi
}

main() {
    validate_config

    if ! need_install && sudo -n "$HELPER_PATH" >/dev/null 2>&1; then
        sudo -n "$HELPER_PATH"
        exit 0
    fi

    if [[ "${1:-}" == "--interactive" ]]; then
        run_interactive
        exit 0
    fi

    if [[ -t 1 ]]; then
        run_interactive
        exit 0
    fi

    spawn_terminal
}

main "$@"
