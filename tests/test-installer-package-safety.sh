#!/usr/bin/env bash
# Mocked installer-package checks. Never contact pacman, systemctl, or virsh.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
extract() { sed -n "/^$1() {/,/^}/p" "$RUNTIME"; }

for function in array_contains_exact install_arch_repo_apps_stage install_desktop_core_dependencies_stage compositor_has_hyprland; do
  eval "$(extract "$function")"
  declare -F "$function" >/dev/null || fail "Missing function: $function"
done

COLOR_CYAN='' COLOR_YELLOW='' COLOR_RESET=''
PKG_GROUPS=()
ARCH_SELECTED=()
COMPOSITOR_SELECTION=hyprland
IS_VM=false
IS_LAPTOP=false
INSTALL_ARCH=1
jack_present=1
libvirt_present=0
default_exists=1
default_active=1
fail_pipewire=0
calls="$TMP/commands.log"
: >"$calls"

log() { :; }
warn() { printf 'WARN: %s\n' "$*" >>"$calls"; }
die() { printf 'ERROR: %s\n' "$*" >&2; return 95; }
is_cachyos_install() { return 0; }
have() {
  case "$1" in virsh|ufw) return 0 ;; *) return 1 ;; esac
}
pacman() {
  local action="$1" pkg="${2:-}"
  case "$action" in
    -Qi)
      [[ "$pkg" == jack2 && "$jack_present" == 1 ]] ||
        [[ "$pkg" == earlyoom && 0 == 1 ]] ||
        [[ "$pkg" == bluez && 0 == 1 ]]
      ;;
    -Qq) [[ "$pkg" == libvirt && "$libvirt_present" == 1 ]] ;;
    -Syu) printf 'pacman-update\n' >>"$calls" ;;
    *) fail "Unexpected pacman call: $*" ;;
  esac
}
pacman_install_one() {
  printf 'install %s\n' "$1" >>"$calls"
  if [[ "$1" == pipewire-jack && "$fail_pipewire" == 1 ]]; then
    return 1
  fi
}
systemctl() { printf 'systemctl %s\n' "$*" >>"$calls"; }
ufw() { printf 'ufw %s\n' "$*" >>"$calls"; }
virsh() {
  printf 'virsh %s\n' "$*" >>"$calls"
  case "$*" in
    "net-info default") [[ "$default_exists" == 1 ]] ;;
    "net-list --name")
      [[ "$default_active" == 1 ]] && printf 'default\n'
      return 0
      ;;
    "net-start default"|"net-autostart default") return 0 ;;
    *) fail "Unexpected virsh command: $*" ;;
  esac
}
check_absent() {
  if grep -Fq -- "$1" "$calls"; then
    fail "Unexpected operation: $1"
  fi
}
check_present() {
  grep -Fq -- "$1" "$calls" || fail "Missing operation: $1"
}

# An install with optional Arch packages disabled should do no work in this
# stage. The mandatory compositor prerequisites run independently.
INSTALL_ARCH=0
install_arch_repo_apps_stage || fail "Arch opt-out failed"
check_absent 'install pipewire-jack'
check_absent 'systemctl'
INSTALL_ARCH=1

# The ordinary desktop install must not uninstall JACK2 or touch any libvirt
# network even when libvirt/virsh are available.
: >"$calls"
jack_present=1
libvirt_present=1
install_arch_repo_apps_stage || fail "Desktop-only install failed"
check_absent 'install pipewire-jack'
check_absent 'libvirtd'
check_absent 'virsh '
check_absent 'ufw '
check_present 'Existing jack2 package preserved'
if grep -Fq 'pacman -Rdd --noconfirm jack2' "$RUNTIME" ||
  grep -Fq 'virsh net-destroy default' "$RUNTIME"; then
  fail "Installer still contains destructive audio/network operations"
fi

# An absent optional PipeWire JACK provider can fail without reporting a
# failed overall desktop install. Previously installed JACK must remain alone.
: >"$calls"
jack_present=0
fail_pipewire=1
install_arch_repo_apps_stage || fail "Optional JACK failure blocked install"
check_present 'install pipewire-jack'
check_present 'Optional pipewire-jack installation failed'
fail_pipewire=0

# Only explicit virt-manager selection is allowed to enable its service or
# configure the default network. An already active guest network stays up.
: >"$calls"
ARCH_SELECTED=(virt-manager)
libvirt_present=1
default_active=1
install_arch_repo_apps_stage || fail "Selected virtualization install failed"
check_present 'install virt-manager'
check_present 'systemctl enable --now libvirtd'
check_present 'virsh net-info default'
check_present 'virsh net-autostart default'
check_absent 'virsh net-start default'
check_absent 'virsh net-destroy'
: >"$calls"
default_active=0
install_arch_repo_apps_stage || fail "Selected inactive guest network setup failed"
check_present 'virsh net-start default'
check_absent 'virsh net-destroy'
: >"$calls"
default_exists=0
install_arch_repo_apps_stage || fail "Missing default network failed installer"
check_present 'No default libvirt network found'
check_absent 'virsh net-start default'
default_exists=1

# Even an explicit virt-manager selection must not try service/network setup
# when the backing libvirt package is unavailable.
: >"$calls"
libvirt_present=0
install_arch_repo_apps_stage || fail "Missing optional libvirt blocked install"
check_present 'libvirt is missing'
check_absent 'systemctl enable --now libvirtd'
check_absent 'virsh '

# Multilib must not be an unconditional precondition for installing ordinary
# Arch packages. A selected unavailable package is rejected by pacman itself.
if extract install_arch_repo_apps_stage | grep -Eq 'pacman-conf|pacman -Rdd'; then
  fail "Unconditional multilib gate or unsafe dependency-bypassing removal returned"
fi

# Real required desktop dependencies must include the managed Hyprland
# PolicyKit Python agent and shared UPower provider even with INSTALL_ARCH=0.
core="$(extract install_desktop_core_dependencies_stage)"
for pkg in polkit python-gobject upower; do
  grep -Fq "$pkg" <<<"$core" || fail "Missing mandatory core package: $pkg"
done

printf 'PASS: Audio preservation, virtualization opt-in, multilib independence and core dependencies\n'
