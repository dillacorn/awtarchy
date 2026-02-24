#!/bin/bash
# github.com/dillacorn/awtarchy/tree/main/scripts
# install_aur_repo_apps.sh

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# EDIT HERE: AUR packages to install (top-level, easy to modify)
# ──────────────────────────────────────────────────────────────────────────────
PACKAGES_AUR=(
  # Utilities
  wlogout
  qimgv-git
  alacritty-graphics
)

# ──────────────────────────────────────────────────────────────────────────────
# Color codes
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;96m'
NC='\033[0m' # No Color

# ──────────────────────────────────────────────────────────────────────────────
# Globals for cleanup
# ──────────────────────────────────────────────────────────────────────────────
TMP_SUDOERS=""
YAY_TMP_DIR=""

cleanup() {
    # Use default-empty expansions to avoid unbound var issues on early exit
    echo -e "${CYAN-}Cleaning up temporary files...${NC-}"
    sudo rm -f "/etc/sudoers.d/temp_sudo_nopasswd" 2>/dev/null || true
    [[ -n "${YAY_TMP_DIR-}" ]]  && sudo rm -rf "${YAY_TMP_DIR}" 2>/dev/null || true
    [[ -n "${TMP_SUDOERS-}" ]]  && sudo rm -f "${TMP_SUDOERS}" 2>/dev/null || true
}
trap cleanup EXIT

# ──────────────────────────────────────────────────────────────────────────────
# Preconditions
# ──────────────────────────────────────────────────────────────────────────────
if [[ -z "${SUDO_USER:-}" ]]; then
    echo "This script must be run with sudo!"
    exit 1
fi

if [[ ! -d "/home/$SUDO_USER" ]]; then
    echo -e "${RED}Error: Home directory for $SUDO_USER not found!${NC}"
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# Prompt helpers (no timeouts)
# ──────────────────────────────────────────────────────────────────────────────
ask_yn() {
    # returns 0 for yes, 1 for no
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
    # sets global IS_LAPTOP=true/false
    local ans
    while true; do
        read -r -n1 -s -p "$(echo -e "\n${CYAN}Is this system a laptop or a desktop? [l/d]${NC} ")" ans
        echo
        case "$ans" in
            l|L) IS_LAPTOP=true;  echo -e "${CYAN}User specified this system is a laptop.${NC}";  return 0 ;;
            d|D) IS_LAPTOP=false; echo -e "${CYAN}User specified this system is a desktop.${NC}"; return 0 ;;
            *)   echo -e "${YELLOW}Invalid input. Press l or d.${NC}" ;;
        esac
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# Temporary NOPASSWD for the invoking user
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${CYAN}Creating temporary sudo permissions...${NC}"
TMP_SUDOERS=$(mktemp /tmp/temp_sudoers.XXXXXX)
echo "${SUDO_USER} ALL=(ALL) NOPASSWD: ALL" | sudo tee "$TMP_SUDOERS" >/dev/null

if ! sudo visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1; then
    echo -e "${RED}Error: Generated sudoers file is invalid!${NC}" >&2
    sudo rm -f "$TMP_SUDOERS"
    exit 1
fi

sudo install -m 0440 "$TMP_SUDOERS" /etc/sudoers.d/temp_sudo_nopasswd
sudo rm -f "$TMP_SUDOERS"
echo -e "${GREEN}Temporary sudo permissions created successfully.${NC}"

# ──────────────────────────────────────────────────────────────────────────────
# Ensure yay exists (install as the non-root user if missing)
# ──────────────────────────────────────────────────────────────────────────────
if ! command -v yay >/dev/null 2>&1; then
    echo -e "${YELLOW}'yay' not found. Installing...${NC}"
    YAY_TMP_DIR=$(sudo -u "$SUDO_USER" mktemp -d -t yay-XXXXXX)
    sudo -u "$SUDO_USER" bash -c "
        set -euo pipefail
        git clone https://aur.archlinux.org/yay.git '$YAY_TMP_DIR'
        cd '$YAY_TMP_DIR'
        makepkg -sirc --noconfirm
        rm -rf '$YAY_TMP_DIR'
    "
fi

# ──────────────────────────────────────────────────────────────────────────────
# Detect VM
# ──────────────────────────────────────────────────────────────────────────────
IS_VM=false
if systemd-detect-virt --quiet; then
    IS_VM=true
    echo -e "${CYAN}Running in a virtual machine. Skipping TLPUI installation.${NC}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Install selected AUR apps
# ──────────────────────────────────────────────────────────────────────────────
if ask_yn "Install Dillacorn's AUR apps?"; then
    echo -e "\n${GREEN}Proceeding with installation of selected AUR applications...${NC}"

    # Full system + AUR sync
    sudo -u "$SUDO_USER" yay -Syu --noconfirm

    # Install loop runs as the invoking user
    for pkg in "${PACKAGES_AUR[@]}"; do
        if sudo -u "$SUDO_USER" yay -Qi "$pkg" >/dev/null 2>&1; then
            echo -e "${YELLOW}$pkg is already installed. Skipping...${NC}"
        else
            echo -e "${CYAN}Installing $pkg...${NC}"
            sudo -u "$SUDO_USER" yay -S --needed --noconfirm "$pkg"
            echo -e "${GREEN}$pkg installed successfully!${NC}"
        fi
        # Clean build dir for the package
        sudo -u "$SUDO_USER" rm -rf "/home/$SUDO_USER/.cache/yay/$pkg" || true
    done

    # Clean the package cache to free up space
    sudo -u "$SUDO_USER" yay -Sc --noconfirm

    echo -e "\n${GREEN}Installation complete and disk space optimized!${NC}"
else
    echo -e "\n${YELLOW}Skipping installation of selected AUR applications.${NC}"
    exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# Laptop/desktop prompt and optional tlpui
# ──────────────────────────────────────────────────────────────────────────────
ask_ld

if [[ "$IS_LAPTOP" = true && "$IS_VM" = false ]]; then
    echo -e "${CYAN}Installing tlpui for laptop power management...${NC}"
    sudo -u "$SUDO_USER" yay -S --needed --noconfirm tlpui
    echo -e "${GREEN}TLPUI installed successfully.${NC}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Optional: Moonlight firewall rules if moonlight-qt-bin is installed
# ──────────────────────────────────────────────────────────────────────────────
if sudo -u "$SUDO_USER" yay -Qs moonlight-qt-bin >/dev/null 2>&1; then
    echo -e "${CYAN}Moonlight detected! Configuring firewall rules for Moonlight...${NC}"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow 48010/tcp
        sudo ufw allow 48000/udp
        sudo ufw allow 48010/udp
        echo -e "${GREEN}Firewall rules for Moonlight configured successfully.${NC}"
    else
        echo -e "${YELLOW}UFW is not installed. Skipping firewall configuration.${NC}"
    fi
fi

echo -e "\n${GREEN}Successfully installed all selected AUR applications!${NC}"
