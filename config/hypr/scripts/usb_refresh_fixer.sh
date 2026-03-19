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
# Refresh an audio device without forcing default sink:
#   ./usb_refresh_fixer.sh refresh-audio ifi
#
# Refresh an audio device and force it as default sink:
#   ./usb_refresh_fixer.sh refresh-audio-default ifi
#
# Force the mapped audio device as default sink without refresh:
#   ./usb_refresh_fixer.sh audio-default ifi
#
# Refresh all mapped devices:
#   ./usb_refresh_fixer.sh

CONFIG_DIR="/etc/usb_refresh_fixer"
RESET_DELAY_SECONDS=2
POST_PORT_REBIND_WAIT_SECONDS=2
POST_CONTROLLER_REBIND_WAIT_SECONDS=3

AUDIO_WAIT_SECS=30
AUDIO_POLL_SECS=0.20
AUDIO_STABLE_POLLS=5

SELF_PATH="$(readlink -f "$0")"
RUN_USER="${SUDO_USER:-${USER:-$(id -un)}}"
SUDOERS_FILE="/etc/sudoers.d/usb_refresh_fixer-${RUN_USER}"
ACTIVE_LOCK_FILE="/tmp/usb_refresh_fixer.${RUN_USER}.active"

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

get_run_user_uid() {
    id -u "$RUN_USER" 2>/dev/null
}

get_run_user_home() {
    getent passwd "$RUN_USER" | awk -F: '{print $6}'
}

user_session_cmd() {
    local uid home
    uid="$(get_run_user_uid)" || return 1
    home="$(get_run_user_home)" || return 1
    [[ -S "/run/user/$uid/bus" ]] || return 1

    sudo -u "$RUN_USER" env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        HOME="$home" \
        PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}" \
        "$@"
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

refresh_lock_begin() {
    printf '%s\n' "$$" > "$ACTIVE_LOCK_FILE"
}

refresh_lock_end() {
    local cur=""
    [[ -e "$ACTIVE_LOCK_FILE" ]] || return 0
    cur="$(cat "$ACTIVE_LOCK_FILE" 2>/dev/null || true)"
    if [[ "$cur" == "$$" ]]; then
        rm -f "$ACTIVE_LOCK_FILE"
    fi
}

run_with_refresh_lock() {
    refresh_lock_begin
    trap 'refresh_lock_end' EXIT INT TERM HUP
    "$@"
    local rc=$?
    refresh_lock_end
    trap - EXIT INT TERM HUP
    return "$rc"
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

audio_prereqs_ok() {
    command -v sudo >/dev/null 2>&1 || return 1
    command -v wpctl >/dev/null 2>&1 || return 1
    command -v pw-dump >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    user_session_cmd true >/dev/null 2>&1 || return 1
}

audio_default_sink_name() {
    user_session_cmd wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '
        /node\.name =/        { print $2; found=1; exit }
        /node\.nick =/        { if (nick == "") nick=$2 }
        /node\.description =/ { if (desc == "") desc=$2 }
        END {
            if (!found) {
                if (nick != "") print nick
                else if (desc != "") print desc
            }
        }
    '
}

audio_find_sink_id_for_name() {
    local name="$1"
    local id=""

    load_config "$name"
    audio_prereqs_ok || return 1

    id="$(user_session_cmd pw-dump 2>/dev/null | jq -r --arg expected_id "${EXPECTED_ID,,}" '
        def norm: ascii_downcase;
        def split_id: $expected_id | split(":");
        .[]
        | select(.type == "PipeWire:Interface:Node")
        | select(.info.props["media.class"] == "Audio/Sink")
        | select(
            (
                (((.info.props["device.vendor.id"] // "") | norm) == (split_id[0]))
                and
                (((.info.props["device.product.id"] // "") | norm) == (split_id[1]))
            )
            or
            ((((.info.props["device.vendor.id"] // "") | norm) + ":" + ((.info.props["device.product.id"] // "") | norm)) == $expected_id)
            or
            (((.info.props["device.bus-id"] // "") | norm) | contains($expected_id))
        )
        | .id
    ' | head -n1 || true)"

    [[ -n "$id" ]] || return 1
    printf '%s\n' "$id"
}

wait_for_mapped_sink_id() {
    local name="$1"
    local end id=""

    end=$(( $(date +%s) + AUDIO_WAIT_SECS ))
    while (( $(date +%s) < end )); do
        id="$(audio_find_sink_id_for_name "$name" || true)"
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    return 1
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
        sleep "$POST_PORT_REBIND_WAIT_SECONDS"
        if device_present_by_id "$EXPECTED_ID"; then
            log "success: $name came back after port rebind"
            return 0
        fi
        log "$name still missing after port rebind, trying controller fallback"
    else
        log "usb path missing, trying controller fallback"
    fi

    rebind_usb_controller "$HOST_CONTROLLER_BDF" "$RESET_DELAY_SECONDS"
    sleep "$POST_CONTROLLER_REBIND_WAIT_SECONDS"

    if device_present_by_id "$EXPECTED_ID"; then
        log "success: $name came back after controller rebind"
        return 0
    fi

    die "$name is still missing after all reset attempts"
}

cmd_audio_default() {
    local name="$1"
    local id=""
    local end current="" last="" count=0

    audio_prereqs_ok || die "audio restore prerequisites missing: need sudo, wpctl, pw-dump, jq, and a live user session bus"
    load_config "$name"

    end=$(( $(date +%s) + AUDIO_WAIT_SECS ))
    while (( $(date +%s) < end )); do
        id="$(audio_find_sink_id_for_name "$name" || true)"
        if [[ -n "$id" ]]; then
            user_session_cmd wpctl set-default "$id" >/dev/null 2>&1 || true
            current="$(audio_default_sink_name || true)"
            if [[ -n "$current" ]]; then
                if [[ "$current" == "$last" ]]; then
                    ((count++))
                else
                    last="$current"
                    count=1
                fi
                if (( count >= AUDIO_STABLE_POLLS )); then
                    log "set mapped audio device as default sink: $name"
                    return 0
                fi
            else
                last=""
                count=0
            fi
        fi
        sleep "$AUDIO_POLL_SECS"
    done

    die "could not set mapped audio device as default sink: $name"
}

cmd_refresh_audio() {
    local name="$1"
    cmd_refresh "$name"
    audio_prereqs_ok || die "audio prerequisites missing after refresh: need sudo, wpctl, pw-dump, jq, and a live user session bus"
    wait_for_mapped_sink_id "$name" >/dev/null || die "mapped audio sink did not appear after refresh: $name"
    log "mapped audio sink is present after refresh: $name"
}

cmd_refresh_audio_default() {
    local name="$1"
    cmd_refresh "$name"
    cmd_audio_default "$name"
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
  usb_refresh_fixer.sh refresh-audio <name>
  usb_refresh_fixer.sh refresh-audio-default <name>
  usb_refresh_fixer.sh audio-default <name>
  usb_refresh_fixer.sh

Examples:
  lsusb
  ./usb_refresh_fixer.sh map 20b1:3008 ifi
  ./usb_refresh_fixer.sh refresh ifi
  ./usb_refresh_fixer.sh refresh-audio ifi
  ./usb_refresh_fixer.sh refresh-audio-default ifi
  ./usb_refresh_fixer.sh audio-default ifi
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
            run_with_refresh_lock cmd_refresh "$2"
            ;;
        refresh-audio)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh_audio "$2"
            ;;
        refresh-audio-default)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh_audio_default "$2"
            ;;
        audio-default)
            [[ $# -eq 2 ]] || { usage; exit 1; }
            cmd_audio_default "$2"
            ;;
        refresh-all)
            [[ $# -eq 1 ]] || { usage; exit 1; }
            run_with_refresh_lock cmd_refresh_all
            ;;
        *)
            if [[ $# -eq 0 ]]; then
                run_with_refresh_lock cmd_refresh_all
            else
                usage
                exit 1
            fi
            ;;
    esac
}

main "$@"
