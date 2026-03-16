#!/usr/bin/env bash
set -euo pipefail

# usb_refresh_fixer.sh
#
# Use lsusb yourself.
#
# Example:
#   lsusb
#   Bus 005 Device 004: ID 20b1:3008 XMOS Ltd iFi (by AMR) HD USB Audio
#
# First map the working device:
#   ./usb_refresh_fixer.sh map 20b1:3008 ifi
#
# Later refresh it:
#   ./usb_refresh_fixer.sh refresh ifi
#
# Refresh all mapped devices:
#   ./usb_refresh_fixer.sh

CONFIG_DIR="/etc/usb_refresh_fixer"
RESET_DELAY_SECONDS=2

SELF_PATH="$(readlink -f "$0")"
RUN_USER="${SUDO_USER:-${USER:-$(id -un)}}"
SUDOERS_FILE="/etc/sudoers.d/usb_refresh_fixer-${RUN_USER}"

log() { printf '[usb_refresh_fixer] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

readf() {
    local f="$1"
    [[ -r "$f" ]] || return 1
    tr -d '\n' < "$f"
}

validate_id() {
    [[ "$1" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]] || die "invalid USB ID: $1"
}

ensure_root() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        return 0
    fi

    if [[ -t 0 || -t 1 ]]; then
        exec sudo "$SELF_PATH" "$@"
    else
        exec sudo -n "$SELF_PATH" "$@" || die "run this manually once first so it can install its sudoers rule"
    fi
}

install_self_sudoers() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "install_self_sudoers requires root"
    [[ "$RUN_USER" != "root" ]] || return 0

    local rule
    local tmp
    rule="${RUN_USER} ALL=(root) NOPASSWD: ${SELF_PATH}"

    if [[ -r "$SUDOERS_FILE" ]] && grep -Fxq "$rule" "$SUDOERS_FILE"; then
        return 0
    fi

    tmp="$(mktemp)"
    printf '%s\n' "$rule" > "$tmp"
    chmod 0440 "$tmp"
    visudo -cf "$tmp" >/dev/null
    install -Dm440 "$tmp" "$SUDOERS_FILE"
    rm -f "$tmp"

    log "installed sudoers rule for ${RUN_USER}"
}

find_device_sysfs_by_id() {
    local target="${1,,}"
    local d vid pid cur

    for d in /sys/bus/usb/devices/*; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue

        vid="$(readf "$d/idVendor" 2>/dev/null || true)"
        pid="$(readf "$d/idProduct" 2>/dev/null || true)"
        [[ -n "$vid" && -n "$pid" ]] || continue

        cur="${vid,,}:${pid,,}"
        if [[ "$cur" == "$target" ]]; then
            basename "$d"
            return 0
        fi
    done

    return 1
}

find_controller_bdf_from_path() {
    local usb_path="$1"
    local rp part last=""

    rp="$(readlink -f "/sys/bus/usb/devices/$usb_path")" || return 1

    while IFS= read -r part; do
        [[ "$part" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]$ ]] && last="$part"
    done < <(tr '/' '\n' <<< "$rp")

    [[ -n "$last" ]] || return 1
    printf '%s\n' "$last"
}

get_pci_driver_for_bdf() {
    local bdf="$1"
    local drv

    drv="$(readlink -f "/sys/bus/pci/devices/$bdf/driver" 2>/dev/null || true)"
    [[ -n "$drv" ]] || return 1
    basename "$drv"
}

device_present_by_id() {
    local want="${1,,}"
    local d vid pid cur

    for d in /sys/bus/usb/devices/*; do
        [[ -f "$d/idVendor" && -f "$d/idProduct" ]] || continue
        vid="$(readf "$d/idVendor" 2>/dev/null || true)"
        pid="$(readf "$d/idProduct" 2>/dev/null || true)"
        [[ -n "$vid" && -n "$pid" ]] || continue
        cur="${vid,,}:${pid,,}"
        [[ "$cur" == "$want" ]] && return 0
    done

    return 1
}

write_config() {
    local name="$1"
    local expected_id="$2"
    local usb_port_path="$3"
    local host_controller_bdf="$4"

    install -d -m 0755 "$CONFIG_DIR"

    cat > "${CONFIG_DIR}/${name}.conf" <<EOF
EXPECTED_ID=$(printf '%q' "$expected_id")
USB_PORT_PATH=$(printf '%q' "$usb_port_path")
HOST_CONTROLLER_BDF=$(printf '%q' "$host_controller_bdf")
RESET_DELAY_SECONDS=$(printf '%q' "$RESET_DELAY_SECONDS")
EOF

    chmod 0644 "${CONFIG_DIR}/${name}.conf"
}

load_config() {
    local name="$1"
    local cfg="${CONFIG_DIR}/${name}.conf"

    [[ -r "$cfg" ]] || die "missing config: $cfg"

    # shellcheck disable=SC1090
    source "$cfg"

    : "${EXPECTED_ID:?missing EXPECTED_ID}"
    : "${USB_PORT_PATH:?missing USB_PORT_PATH}"
    : "${HOST_CONTROLLER_BDF:?missing HOST_CONTROLLER_BDF}"
    : "${RESET_DELAY_SECONDS:?missing RESET_DELAY_SECONDS}"
    [[ "$RESET_DELAY_SECONDS" =~ ^[0-9]+$ ]] || die "RESET_DELAY_SECONDS invalid in $cfg"
}

rebind_usb_port() {
    local usb_port_path="$1"
    local delay="$2"

    [[ -e "/sys/bus/usb/devices/$usb_port_path" ]] || return 1

    log "rebinding USB port path: $usb_port_path"
    printf '%s' "$usb_port_path" > /sys/bus/usb/drivers/usb/unbind
    sleep "$delay"
    printf '%s' "$usb_port_path" > /sys/bus/usb/drivers/usb/bind
    udevadm settle --timeout=10 || true
    return 0
}

rebind_usb_controller() {
    local bdf="$1"
    local delay="$2"
    local driver

    [[ -e "/sys/bus/pci/devices/$bdf" ]] || die "missing PCI device: $bdf"
    driver="$(get_pci_driver_for_bdf "$bdf")" || die "could not resolve PCI driver for $bdf"

    log "rebinding host controller: $bdf ($driver)"
    printf '%s' "$bdf" > "/sys/bus/pci/drivers/$driver/unbind"
    sleep "$delay"
    printf '%s' "$bdf" > "/sys/bus/pci/drivers/$driver/bind"
    udevadm settle --timeout=15 || true
}

cmd_map() {
    local id="${1,,}"
    local name="$2"
    local usb_port_path host_controller_bdf

    validate_id "$id"

    usb_port_path="$(find_device_sysfs_by_id "$id")" || die "device $id is not currently detected. map it while it is working."
    host_controller_bdf="$(find_controller_bdf_from_path "$usb_port_path")" || die "could not resolve PCI controller for $usb_port_path"

    write_config "$name" "$id" "$usb_port_path" "$host_controller_bdf"

    log "mapped $name"
    log "  id: $id"
    log "  usb path: $usb_port_path"
    log "  controller: $host_controller_bdf"
}

cmd_refresh() {
    local name="$1"
    load_config "$name"

    log "refreshing $name"
    log "  id: $EXPECTED_ID"
    log "  usb path: $USB_PORT_PATH"
    log "  controller: $HOST_CONTROLLER_BDF"

    if rebind_usb_port "$USB_PORT_PATH" "$RESET_DELAY_SECONDS"; then
        sleep 2
        if device_present_by_id "$EXPECTED_ID"; then
            log "success: $name came back after port rebind"
            return 0
        fi
        log "$name still missing after port rebind, trying controller fallback"
    else
        log "usb path missing, trying controller fallback"
    fi

    rebind_usb_controller "$HOST_CONTROLLER_BDF" "$RESET_DELAY_SECONDS"
    sleep 3

    if device_present_by_id "$EXPECTED_ID"; then
        log "success: $name came back after controller rebind"
        return 0
    fi

    die "$name is still missing after all reset attempts"
}

cmd_refresh_all() {
    local cfg name rc=0

    shopt -s nullglob
    for cfg in "$CONFIG_DIR"/*.conf; do
        name="$(basename "$cfg" .conf)"
        cmd_refresh "$name" || rc=1
    done
    shopt -u nullglob

    return "$rc"
}

usage() {
    cat <<'EOF'
Usage:
  usb_refresh_fixer.sh map <vendor:product> <name>
  usb_refresh_fixer.sh refresh <name>
  usb_refresh_fixer.sh

Examples:
  lsusb
  ./usb_refresh_fixer.sh map 20b1:3008 ifi
  ./usb_refresh_fixer.sh refresh ifi
  ./usb_refresh_fixer.sh
EOF
}

main() {
    ensure_root "$@"
    install_self_sudoers

    case "${1:-refresh-all}" in
        map)
            [[ $# -eq 3 ]] || { usage; exit 1; }
            cmd_map "$2" "$3"
            ;;
        refresh)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            cmd_refresh "$2"
            ;;
        refresh-all)
            [[ $# -eq 1 ]] || { usage; exit 1; }
            cmd_refresh_all
            ;;
        *)
            if [[ $# -eq 0 ]]; then
                cmd_refresh_all
            else
                usage
                exit 1
            fi
            ;;
    esac
}

main "$@"
