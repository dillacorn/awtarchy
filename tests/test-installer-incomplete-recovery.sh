#!/usr/bin/env bash
# Offline installer safety tests: never invoke real pacman or write system state.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/awtarchy-install.sh"
RUNTIME="$ROOT/local/share/awtarchy/awtarchy-runtime.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

extract() {
  local func="$1" file="$2"
  sed -n "/^${func}() {/,/^}/p" "$file"
}
for func in installed_command_exists installed_desktop_ready legacy_install_evidence_present legacy_install_exists; do
  eval "$(extract "$func" "$INSTALLER")"
done
for func in pacman_install_one install_arch_repo_apps_stage install_desktop_core_dependencies_stage verify_installed_desktop_config_stage compositor_has_hyprland compositor_has_sway; do
  eval "$(extract "$func" "$RUNTIME")"
done
for func in installed_command_exists installed_desktop_ready legacy_install_exists pacman_install_one install_desktop_core_dependencies_stage verify_installed_desktop_config_stage; do
  declare -F "$func" >/dev/null || fail "Missing installer function: $func"
done

COLOR_CYAN='' COLOR_YELLOW='' COLOR_RESET=''
TARGET_HOME="$TMP/home"
mkdir -p "$TARGET_HOME"
fake_packages=()
mock_installed=0
mock_install_result=1
mock_register=0
mock_install_calls=0
pacman() {
  local operation="$1" package saved present
  shift
  case "$operation" in
    -Qi) (( mock_installed == 1 )) ;;
    -S)
      mock_install_calls=$((mock_install_calls + 1))
      if (( mock_install_result == 0 && mock_register == 1 )); then
        mock_installed=1
      fi
      return "$mock_install_result"
      ;;
    -Qq)
      for package in "$@"; do
        present=0
        for saved in "${fake_packages[@]}"; do
          [[ "$saved" == "$package" ]] && present=1
        done
        (( present == 1 )) || return 1
      done
      ;;
    *) fail "Unexpected mock pacman operation: $operation" ;;
  esac
}

legacy_source="$(extract legacy_install_exists "$INSTALLER")"
[[ "$legacy_source" != *'[[ -f /var/lib/awtarchy/managed-packages ]] && return 0'* ]] ||
  fail "Global package record still classifies another user's installation"
if legacy_install_exists; then fail "Empty home was classified as legacy"; fi
mkdir -p "$TARGET_HOME/.cache/awtarchy"
: >"$TARGET_HOME/.cache/awtarchy/version"
if legacy_install_exists; then fail "Legacy marker without desktop was accepted"; fi
mkdir -p "$TARGET_HOME/.config/hypr"
: >"$TARGET_HOME/.config/hypr/hyprland.lua"
legacy_install_evidence_present || fail "Legacy marker with desktop configuration was not detected"
if legacy_install_exists; then
  fail "Partial legacy desktop without installed compositor was accepted"
fi
fake_packages=(hyprland)
legacy_install_exists || fail "Installed Hyprland legacy desktop was rejected"
fake_packages=(sway)
if legacy_install_exists; then
  fail "Sway package alone accepted a Hyprland-only legacy config"
fi
fake_packages=(hyprland)
rm -f -- "$TARGET_HOME/.cache/awtarchy/version"

mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/awtarchy"
: >"$TARGET_HOME/.local/bin/awtarchy"
chmod 0755 "$TARGET_HOME/.local/bin/awtarchy"
: >"$TARGET_HOME/.local/share/awtarchy/awtarchy-runtime.sh"
installed_command_exists || fail "Existing command/runtime pair not found"
if installed_desktop_ready; then fail "CLI alone was accepted as full installation"; fi

mkdir -p "$TARGET_HOME/.config/foot" "$TARGET_HOME/.config/quickshell/awtarchy" "$TARGET_HOME/.local/state/awtarchy"
: >"$TARGET_HOME/.config/foot/foot.ini"
: >"$TARGET_HOME/.config/quickshell/awtarchy/shell.qml"
: >"$TARGET_HOME/.local/state/awtarchy/config-version"
if installed_desktop_ready; then fail "Missing desktop packages were accepted"; fi
fake_packages=(foot quickshell hyprland)
installed_desktop_ready || fail "Healthy Hyprland installation rejected"
fake_packages=(quickshell hyprland)
if installed_desktop_ready; then fail "Missing Foot accepted"; fi
fake_packages=(foot quickshell)
if installed_desktop_ready; then fail "Missing compositor accepted"; fi
fake_packages=(foot quickshell sway)
if installed_desktop_ready; then fail "Sway package mismatched with Hyprland config"; fi
mkdir -p "$TARGET_HOME/.config/sway/awtarchy-trial"
: >"$TARGET_HOME/.config/sway/awtarchy-trial/config"
installed_desktop_ready || fail "Healthy Sway installation rejected"
rm -f -- "$TARGET_HOME/.config/quickshell/awtarchy/shell.qml"
if installed_desktop_ready; then fail "Missing Quickshell configuration accepted"; fi
: >"$TARGET_HOME/.config/quickshell/awtarchy/shell.qml"
rm -f -- "$TARGET_HOME/.local/state/awtarchy/config-version"
if installed_desktop_ready; then fail "Missing configuration version accepted"; fi

# A partial installation must fail before *any* user or privileged helper
# installation. Exercise the installer entrypoint with a command-only home.
installer_home="$TMP/incomplete-installer-home"
mkdir -p "$installer_home/.local/bin" "$installer_home/.local/share/awtarchy"
: >"$installer_home/.local/bin/awtarchy"
chmod 0755 "$installer_home/.local/bin/awtarchy"
: >"$installer_home/.local/share/awtarchy/awtarchy-runtime.sh"
installer_bin="$TMP/no-installer-writes"
if HOME="$installer_home" USER="$(id -un)" AWTARCHY_SYSTEM_BIN_DIR="$installer_bin" \
  bash "$INSTALLER" >"$TMP/partial-install.log" 2>&1; then
  fail "Installer accepted command-only partial desktop"
fi
grep -Fq 'desktop installation is incomplete' "$TMP/partial-install.log" ||
  fail "Partial install rejection did not explain recovery"
[[ ! -e "$installer_home/vpn" && ! -e "$installer_bin" ]] ||
  fail "Partial-install rejection made changes before preflight"

# A legacy version record and copied Hyprland configuration without the
# compositor package must fail, not silently enter full installation.
legacy_preflight_home="$TMP/partial-legacy-home"
mkdir -p "$legacy_preflight_home/.cache/awtarchy" "$legacy_preflight_home/.config/hypr"
: >"$legacy_preflight_home/.cache/awtarchy/version"
: >"$legacy_preflight_home/.config/hypr/hyprland.lua"
if HOME="$legacy_preflight_home" USER="$(id -un)" AWTARCHY_SYSTEM_BIN_DIR="$installer_bin" \
  bash "$INSTALLER" >"$TMP/partial-legacy.log" 2>&1; then
  fail "Installer accepted legacy desktop without compositor package"
fi
grep -Fq 'compositor package is missing' "$TMP/partial-legacy.log" ||
  fail "Legacy preflight did not explain the missing package"
[[ ! -e "$legacy_preflight_home/vpn" && ! -e "$installer_bin" ]] ||
  fail "Legacy-install rejection made changes before preflight"

# The old helper returned zero when pacman failed or a package stayed missing.
mock_installed=0
mock_install_result=42
mock_register=0
mock_install_calls=0
if pacman_install_one unavailable >"$TMP/pacman.log" 2>&1; then
  fail "pacman -S failure was accepted"
fi
[[ "$mock_install_calls" -eq 1 ]] || fail "Pacman install was not called"
grep -Fq 'Package installation failed: unavailable' "$TMP/pacman.log" ||
  fail "Missing package failure report"
mock_installed=0
mock_install_result=0
mock_register=0
if pacman_install_one absent-after-download >"$TMP/pacman.log" 2>&1; then
  fail "Missing package after pacman -S was accepted"
fi
grep -Fq 'Package is still missing after installation: absent-after-download' "$TMP/pacman.log" ||
  fail "Missing post-install verification report"
mock_installed=1
mock_install_calls=0
pacman_install_one already-installed >/dev/null || fail "Installed package rejected"
[[ "$mock_install_calls" -eq 0 ]] || fail "Already-installed package reinstalled"

# Selecting no additional Arch packages must still install a usable desktop.
warn() { :; }
INSTALL_ARCH=0
install_arch_repo_apps_stage || fail "Arch opt-out failed"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 91; }
pacman_install_one() {
  core_calls+=("$1")
  fake_packages+=("$1")
}
for compositor in hyprland sway both; do
  COMPOSITOR_SELECTION="$compositor"
  core_calls=()
  fake_packages=()
  install_desktop_core_dependencies_stage || fail "Required desktop rejected: $compositor"
  for pkg in quickshell qt6-multimedia qt6-multimedia-ffmpeg foot upower; do
    [[ " ${core_calls[*]} " == *" $pkg "* ]] ||
      fail "Required $pkg was skipped for $compositor"
  done
  if [[ "$compositor" == sway ]]; then
    [[ " ${core_calls[*]} " != *" hyprland "* ]] ||
      fail "Sway-only pulled in Hyprland"
  else
    for pkg in hyprland hypridle hyprsunset xdg-desktop-portal-hyprland polkit python-gobject; do
      [[ " ${core_calls[*]} " == *" $pkg "* ]] ||
        fail "Required $pkg was skipped for $compositor"
    done
  fi
done
if (
  pacman_install_one() { [[ "$1" != quickshell ]]; }
  COMPOSITOR_SELECTION=hyprland
  install_desktop_core_dependencies_stage
); then
  fail "Failed required dependency did not halt installation"
fi
if (
  pacman_install_one() { return 0; }
  fake_packages=()
  COMPOSITOR_SELECTION=hyprland
  install_desktop_core_dependencies_stage
); then
  fail "Missing post-install core dependency did not halt installation"
fi

# A full install must never report success when the selected desktop's
# managed configuration was not deployed.
HOME_DIR="$TMP/config-home"
COMPOSITOR_SELECTION=hyprland
if (verify_installed_desktop_config_stage); then
  fail "Missing desktop configuration was accepted"
fi
mkdir -p "$HOME_DIR/.config/foot" "$HOME_DIR/.config/quickshell/awtarchy" "$HOME_DIR/.config/hypr"
: >"$HOME_DIR/.config/foot/foot.ini"
: >"$HOME_DIR/.config/quickshell/awtarchy/shell.qml"
: >"$HOME_DIR/.config/hypr/hyprland.lua"
verify_installed_desktop_config_stage || fail "Complete Hyprland config rejected"
COMPOSITOR_SELECTION=both
if (verify_installed_desktop_config_stage); then
  fail "Both compositors accepted without Sway config"
fi
mkdir -p "$HOME_DIR/.config/sway/awtarchy-trial"
: >"$HOME_DIR/.config/sway/awtarchy-trial/config"
verify_installed_desktop_config_stage || fail "Complete dual-compositor config rejected"
COMPOSITOR_SELECTION=sway
rm -f -- "$HOME_DIR/.config/hypr/hyprland.lua"
verify_installed_desktop_config_stage || fail "Complete Sway-only config rejected"
rm -f -- "$HOME_DIR/.config/foot/foot.ini"
if (verify_installed_desktop_config_stage); then
  fail "Missing Foot config was accepted"
fi

run_install_source="$(extract run_install "$RUNTIME")"
[[ "$run_install_source" == *'  install_arch_repo_apps_stage
  install_sway_repo_dependencies_stage
  install_desktop_core_dependencies_stage'* ]] ||
  fail "Required core stage not reached by installer"
[[ "$run_install_source" == *'  copy_awtarchy_configs_stage
  install_sway_session_stage
  verify_installed_desktop_config_stage'* ]] ||
  fail "Required desktop config verification is missing from installer"
[[ "$(grep -Fc 'pacman_install_one "$pkg" || die "Selected Arch repository package failed: $pkg"' "$RUNTIME")" -eq 2 ]] ||
  fail "A selected package loop still ignores failed installs"
printf 'PASS: Incomplete install and required desktop package regressions\n'
