#!/bin/bash
# github.com/dillacorn/awtarchy/tree/main/scripts
# install_arch_repo_apps.sh

set -euo pipefail

# =============================================
# EDIT HERE: PACKAGE GROUPS (Arch repos only)
# Format: "Group Label:pkg1 pkg2 pkg3"
# =============================================
declare -a PKG_GROUPS=(
    "Window Management:hyprland hyprpaper hyprlock hypridle hyprpicker hyprsunset waybar wofi fuzzel swww grim satty slurp wl-clipboard cliphist zbar wf-recorder zenity qt5ct qt5-wayland kvantum-qt5 qt6ct qt6-wayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk mako nwg-look"
    "Fonts:woff2-font-awesome otf-font-awesome ttf-dejavu ttf-liberation ttf-noto-nerd noto-fonts-emoji"
    "Themes:papirus-icon-theme materia-gtk-theme xcursor-comix kvantum-theme-materia"
    "Terminal Apps:nano micro alacritty fastfetch btop htop curl wget git dos2unix brightnessctl ipcalc cmatrix sl asciiquarium figlet termdown espeak-ng cava man-db man-pages unzip xarchiver ncdu ddcutil"
    "Utilities:polkit-gnome gnome-keyring networkmanager network-manager-applet bluez bluez-utils blueman wiremix pcmanfm-qt gvfs gvfs-smb gvfs-mtp gvfs-afc speedcrunch imagemagick pipewire pipewire-pulse pipewire-alsa ufw jq earlyoom"
    "Multimedia:ffmpeg avahi mpv cheese exiv2 zathura zathura-pdf-mupdf mousai"
    "Development:base-devel archlinux-keyring clang ninja go rust virt-manager qemu qemu-hw-usb-host virt-viewer vde2 libguestfs dmidecode gamemode gamescope nftables swtpm"
    "Network Tools:firefox wireguard-tools wireplumber openssh iptables systemd-resolvconf bridge-utils qemu-guest-agent dnsmasq dhcpcd inetutils openbsd-netcat"
)

# =============================================
# COLOR DEFINITIONS
# =============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;96m'
NC='\033[0m' # No Color

# =============================================
# SCRIPT INITIALIZATION
# =============================================
if [[ -z "${SUDO_USER:-}" ]]; then
    echo -e "${RED}This script must be run with sudo!${NC}"
    exit 1
fi

# =============================================
# PROMPT HELPERS (no timeout)
# =============================================
ask_yn() {
    local ans
    while true; do
        read -r -n1 -s -p "$(echo -e "\n${CYAN}$1 [y/n]${NC} ")" ans
        echo
        case "$ans" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *)   echo -e "${YELLOW}Invalid input. Press y or n.${NC}" ;;
        esac
    done
}

ask_ld() {
    local ans
    while true; do
        read -r -n1 -s -p "$(echo -e "\n${CYAN}Is this a laptop or a desktop? [l/d]${NC} ")" ans
        echo
        case "$ans" in
            l|L) IS_LAPTOP=true;  echo -e "${CYAN}Laptop selected.${NC}";  return 0 ;;
            d|D) IS_LAPTOP=false; echo -e "${CYAN}Desktop selected.${NC}"; return 0 ;;
            *)   echo -e "${YELLOW}Invalid input. Press l or d.${NC}" ;;
        esac
    done
}

# =============================================
# FUNCTIONS
# =============================================
install_package() {
    local package="$1"
    if ! pacman -Qi "$package" &>/dev/null; then
        echo -e "${CYAN}Installing $package...${NC}"
        if ! pacman -S --needed --noconfirm "$package"; then
            echo -e "${RED}Failed to install $package!${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}$package already installed. Skipping...${NC}"
    fi
}

# =============================================
# SYSTEM CHECKS
# =============================================
if systemd-detect-virt --quiet; then
    IS_VM=true
    echo -e "${CYAN}Running in virtual machine. Skipping some hardware steps.${NC}"
else
    IS_VM=false
    echo -e "${CYAN}Running on physical hardware.${NC}"
fi

# Verify multilib is enabled
if ! grep -q "^\[multilib\]" /etc/pacman.conf || ! grep -q "^Include = /etc/pacman.d/mirrorlist" /etc/pacman.conf; then
    echo -e "${RED}ERROR: Multilib repository not enabled!${NC}"
    echo -e "${YELLOW}Enable in /etc/pacman.conf:${NC}"
    echo -e "${CYAN}[multilib]\nInclude = /etc/pacman.d/mirrorlist${NC}"
    echo -e "${YELLOW}Then run: pacman -Syu${NC}"
    exit 1
fi

# Resolve jack2 conflict before pipewire-jack
if pacman -Qi jack2 &>/dev/null; then
    echo -e "${YELLOW}Removing conflicting jack2 package...${NC}"
    pacman -Rdd --noconfirm jack2 || {
        echo -e "${RED}Failed to remove jack2. Remove manually and retry.${NC}"
        exit 1
    }
fi
install_package "pipewire-jack" || true

# =============================================
# MAIN PROMPT
# =============================================
if ! ask_yn "Install Dillacorn's Arch repo applications?"; then
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 0
fi

echo -e "\n${CYAN}Updating system...${NC}"
pacman -Syu --noconfirm || {
    echo -e "${RED}System update failed. Resolve and rerun.${NC}"
    exit 1
}

# =============================================
# PACKAGE INSTALLATION
# =============================================
for group in "${PKG_GROUPS[@]}"; do
    IFS=':' read -r group_name packages <<< "$group"
    echo -e "\n${CYAN}Installing ${group_name}...${NC}"
    for pkg in $packages; do
        install_package "$pkg" || echo -e "${YELLOW}Continuing despite failure: $pkg${NC}"
    done
done

# =============================================
# SYSTEM CONFIGURATION
# =============================================
echo -e "\n${CYAN}Configuring system services...${NC}"

# Avahi
systemctl enable --now avahi-daemon || true

# DNS Services
if systemctl is-active --quiet unbound; then
    systemctl disable --now unbound || true
fi
systemctl enable --now systemd-resolved || true
systemctl stop dnsmasq.service || true
systemctl disable dnsmasq.service || true

# NetworkManager
systemctl enable --now NetworkManager || true

# =============================================
# HARDWARE-SPECIFIC CONFIGURATION
# =============================================
if [[ "$IS_VM" = false ]]; then
    ask_ld

    # Intel laptop power management
    if grep -qi "Intel" /proc/cpuinfo && [[ "$IS_LAPTOP" = true ]]; then
        echo -e "${CYAN}Setting up Intel laptop power management...${NC}"
        install_package "thermald" && systemctl enable --now thermald || true
    fi

    # Laptop power management
    if [[ "$IS_LAPTOP" = true ]]; then
        echo -e "${CYAN}Configuring laptop power savings...${NC}"
        install_package "tlp" && systemctl enable --now tlp || true
    fi
fi

# =============================================
# VIRTUALIZATION SETUP
# =============================================
if [[ "$IS_VM" = false ]]; then
    echo -e "\n${CYAN}Configuring virtualization...${NC}"
    systemctl enable --now libvirtd || true

    echo -e "${CYAN}Waiting for libvirtd...${NC}"
    for _ in {1..10}; do
        if systemctl is-active --quiet libvirtd; then
            break
        fi
        sleep 1
    done

    virsh net-destroy default || true
    virsh net-start default || true
    virsh net-autostart default || true

    if command -v ufw >/dev/null 2>&1; then
        ufw allow in on virbr0 || true
        ufw allow out on virbr0 || true
        ufw reload || true
    fi
fi

# =============================================
# MEMORY SAFETY: EARLYOOM SETUP
# =============================================
if pacman -Qi earlyoom &>/dev/null; then
    echo -e "${CYAN}Enabling earlyoom service...${NC}"
    systemctl enable --now earlyoom || true
else
    echo -e "${YELLOW}earlyoom not installed — skipping service enable.${NC}"
fi

# =============================================
# BLUETOOTH
# =============================================
if pacman -Qi bluez &>/dev/null; then
    systemctl enable --now bluetooth.service || true
fi

echo -e "\n${GREEN}Installation complete.${NC}"
echo -e "${YELLOW}Some changes may require reboot.${NC}"
