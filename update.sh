#!/bin/bash
#################################################
##           Installation Instructions         ##
#################################################

# Step 1: Download the repository
# --------------------------------
# Open a terminal and run:
#   sudo pacman -S git
#   git clone https://github.com/dillacorn/awtarchy

# Step 2: Run the installer
# -------------------------
# Navigate to the awtarchy directory:
#   cd awtarchy
# Make the installer executable and run it:
#   chmod +x install.sh
#   sudo ./install.sh
# Follow the on-screen instructions.

#################################################
##              End of Instructions            ##
#################################################

# Color Variables
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_BLUE="\033[1;34m"
COLOR_MAGENTA="\033[1;35m"
COLOR_CYAN="\033[1;36m"
COLOR_RESET="\033[0m"

# Global Variables
HOME_DIR="/home/$SUDO_USER"
REPO_DIR="$HOME_DIR/awtarchy"
REQUIRED_SPACE_MB=1024
INSTALL_SCRIPTS=(
    "install_arch_repo_apps.sh"
    "install_aur_repo_apps.sh"
    "install_flatpak_apps.sh"
    "install_alacritty_themes.sh"
    "install_GPU_dependencies.sh"
    "install_micro_themes.sh"
    "enable_keyring_pam.sh"
    "install_ly.sh"
)

# Ensure the script is run with sudo
if [ -z "$SUDO_USER" ]; then
    echo -e "${COLOR_RED}This script must be run with sudo!${COLOR_RESET}"
    exit 1
fi

retry_command() {
    local retries=3 count=0
    until "$@"; do
        exit_code=$?
        ((count++))
        echo -e "${COLOR_RED}Attempt $count/$retries failed for command:${COLOR_RESET}"
        printf "'%s' " "$@"; echo
        if [ $count -lt $retries ]; then
            echo -e "${COLOR_RED}Retrying...${COLOR_RESET}"
            sleep 2
        else
            echo -e "${COLOR_RED}Command failed after $retries attempts. Exiting.${COLOR_RESET}"
            return $exit_code
        fi
    done
}

create_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo -e "${COLOR_YELLOW}Creating missing directory: ${COLOR_CYAN}$dir${COLOR_RESET}"
        retry_command mkdir -p "$dir" || { echo -e "${COLOR_RED}Failed to create directory ${COLOR_CYAN}$dir${COLOR_RESET}. Exiting.${COLOR_RESET}"; exit 1; }
    fi
    retry_command chown "$SUDO_USER:$SUDO_USER" "$dir"
    retry_command chmod 755 "$dir"
}

# First confirmation
echo -e "${COLOR_RED}WARNING: This script will overwrite the following directories:${COLOR_RESET}"
echo -e "${COLOR_YELLOW}
- ~/.config/hypr
- ~/.config/waybar
- ~/.config/alacritty
- ~/.config/wofi
- ~/.config/fuzzel
- ~/.config/mako
- ~/.config/gtk-3.0
- ~/.config/Kvantum
- ~/.config/pcmanfm-qt
- ~/.config/yazi
- ~/.config/SpeedCrunch
- ~/.config/fastfetch
- ~/.config/wlogout
- ~/.config/qt5ct
- ~/.config/qt6ct
- ~/.config/xdg-desktop-portal
- ~/.config/lsfg-vk
- ~/.config/YouTube Music
- ~/.config/wiremix
- ~/.config/cava
- ~/.Xresources
- ~/.local/share/nwg-look/gsettings${COLOR_RESET}"
echo -e "${COLOR_RED}Are you sure you want to continue? This action CANNOT be undone.${COLOR_RESET}"
echo -e "${COLOR_GREEN}Press 'y' to continue or 'n' to cancel. Default is 'yes' if Enter is pressed:${COLOR_RESET}"

read -r -n 1 first_confirmation
echo

if [[ "$first_confirmation" != "y" && "$first_confirmation" != "Y" && "$first_confirmation" != "" ]]; then
    echo -e "${COLOR_RED}Installation canceled by user.${COLOR_RESET}"
    exit 1
fi

# Second confirmation
echo -e "${COLOR_MAGENTA}This is your last chance! Are you absolutely sure? (y/n)${COLOR_RESET}"
read -r -n 1 second_confirmation
echo

if [[ "$second_confirmation" != "y" && "$second_confirmation" != "Y" && "$second_confirmation" != "" ]]; then
    echo -e "${COLOR_RED}Installation canceled by user.${COLOR_RESET}"
    exit 1
fi

# Adding pause before continuing
echo -e "${COLOR_GREEN}Proceeding with the installation...${COLOR_RESET}"
read -r -p "Press Enter to continue..."

# Check disk space
AVAILABLE_SPACE_MB=$(df --output=avail / | tail -1)
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_MB / 1024))
if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
    echo -e "${COLOR_RED}Not enough disk space (1GB required). Exiting.${COLOR_RESET}"
    exit 1
fi

# Update system and install basic packages
echo -e "${COLOR_BLUE}Updating package list and installing git...${COLOR_RESET}"
if ! retry_command pacman -Syu --noconfirm; then
    echo -e "${COLOR_RED}Failed to update package list. Refreshing mirrors...${COLOR_RESET}"
    retry_command reflector --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
    retry_command pacman -Syu --noconfirm || exit 1
fi

retry_command pacman -S --needed --noconfirm git ipcalc dos2unix reflector xcursor-comix || exit 1

# Clone repository if not exists
if [ ! -d "$REPO_DIR" ]; then
    echo -e "${COLOR_BLUE}Cloning awtarchy repository to ${COLOR_CYAN}${REPO_DIR}${COLOR_RESET}...${COLOR_RESET}"
    retry_command git clone https://github.com/dillacorn/awtarchy "$REPO_DIR" || exit 1
fi
retry_command chown -R "$SUDO_USER:$SUDO_USER" "$REPO_DIR"

# Convert line endings
echo -e "${COLOR_BLUE}Converting files to Unix line endings...${COLOR_RESET}"
find "$REPO_DIR" -type f -exec dos2unix {} + 2>/dev/null

# Run installation scripts in order
cd "$REPO_DIR/scripts" || exit 1
for script in "${INSTALL_SCRIPTS[@]}"; do
    echo -e "${COLOR_BLUE}Running ${COLOR_CYAN}$script${COLOR_RESET}...${COLOR_RESET}"
    chmod +x "$script"
    
    # Special handling for GPU script in VMs
    if [[ "$script" == "install_GPU_dependencies.sh" ]] && systemd-detect-virt --quiet; then
        echo -e "${COLOR_YELLOW}Skipping GPU script in virtual machine${COLOR_RESET}"
        continue
    fi
    
    retry_command "./$script" || { echo -e "${COLOR_RED}$script failed!${COLOR_RESET}"; exit 1; }
    read -r -p "Press Enter to continue..."
done

# Handle .bashrc and .bash_profile with user confirmation
for config_file in bashrc bash_profile; do
    if [ -f "$HOME_DIR/.$config_file" ]; then
        echo -e "${COLOR_YELLOW}$HOME_DIR/.$config_file exists. Overwrite? (y/N)${COLOR_RESET}"
        read -r -n 1 response
        echo
        if [[ "$response" =~ ^[Yy]$ ]]; then
            retry_command cp "$REPO_DIR/$config_file" "$HOME_DIR/.$config_file"
            # Special handling for Btrfs
            if findmnt -n -o FSTYPE / | grep -qi btrfs; then
                sed -i '/alias flatpak=.flatpak --user./ s/^/#/' "$HOME_DIR/.$config_file"
                echo "Btrfs detected on root. Commented out flatpak --user alias in .$config_file"
            fi
            retry_command chown "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.$config_file"
            retry_command chmod 644 "$HOME_DIR/.$config_file"
        fi
    else
        retry_command cp "$REPO_DIR/$config_file" "$HOME_DIR/.$config_file"
        retry_command chown "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.$config_file"
        retry_command chmod 644 "$HOME_DIR/.$config_file"
    fi
done

# Copy all configuration files
echo -e "${COLOR_BLUE}Copying configuration files...${COLOR_RESET}"
config_dirs=("hypr" "waybar" "alacritty" "wlogout" "mako" "wofi" "fuzzel"
    "gtk-3.0" "Kvantum" "SpeedCrunch" "fastfetch" "pcmanfm-qt" "yazi" "xdg-desktop-portal" "qt5ct" "qt6ct" "lsfg-vk" "wiremix" "cava" "YouTube Music")

for dir in "${config_dirs[@]}"; do
    retry_command cp -r "$REPO_DIR/config/$dir" "$HOME_DIR/.config/" || exit 1
    retry_command chown -R "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.config/$dir"
done

# Create directory if it doesn't exist
create_directory "$HOME_DIR/.local/share/nwg-look"
create_directory "$HOME_DIR/.local/share/SpeedCrunch"
create_directory "$HOME_DIR/.local/share/SpeedCrunch/color-schemes"

# Special files
retry_command cp "$REPO_DIR/Xresources" "$HOME_DIR/.Xresources"
retry_command cp "$REPO_DIR/config/mimeapps.list" "$HOME_DIR/.config/"
retry_command cp "$REPO_DIR/config/gamemode.ini" "$HOME_DIR/.config/"
retry_command cp "$REPO_DIR/local/share/nwg-look/gsettings" "$HOME_DIR/.local/share/nwg-look/"
retry_command chown "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.local/share/nwg-look/gsettings"
retry_command chmod 644 "$HOME_DIR/.local/share/nwg-look/gsettings"

# SpeedCrunch color schemes
retry_command cp "$REPO_DIR/local/share/SpeedCrunch/color-schemes/"*.json "$HOME_DIR/.local/share/SpeedCrunch/color-schemes/"
retry_command chown -R "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.local/share/SpeedCrunch"
retry_command chmod 644 "$HOME_DIR/.local/share/SpeedCrunch/color-schemes/"*.json

# Desktop entries
create_directory "$HOME_DIR/.local/share/applications"
retry_command cp -r "$REPO_DIR/local/share/applications/." "$HOME_DIR/.local/share/applications"

# Cursor theme
create_directory "$HOME_DIR/.local/share/icons/ComixCursors-White"
retry_command cp -r /usr/share/icons/ComixCursors-White/* "$HOME_DIR/.local/share/icons/ComixCursors-White/"

# System-wide cursor
cat > /usr/share/icons/default/index.theme <<EOF
[Icon Theme]
Inherits=ComixCursors-White
EOF

# Flatpak cursor
command -v flatpak &>/dev/null && flatpak override --user --env=GTK_CURSOR_THEME=ComixCursors-White

# Wallpaper setup
create_directory "$HOME_DIR/Pictures/wallpapers"
create_directory "$HOME_DIR/Pictures/Screenshots"
retry_command cp "$REPO_DIR/awtarchy_geology.png" "$HOME_DIR/Pictures/wallpapers/"

# Final permissions
find "$HOME_DIR/.config" -type d -exec chmod 755 {} +
find "$HOME_DIR/.config" -type f -exec chmod 644 {} +
find "$HOME_DIR/.config/hypr/scripts" -type f -exec chmod +x {} +
find "$HOME_DIR/.config/hypr/themes" -type f -exec chmod +x {} +
find "$HOME_DIR/.config/waybar/scripts" -type f -exec chmod +x {} +

# Ownership & permission repair (fix user unable to write in $HOME)
echo -e "${COLOR_BLUE}Repairing ownership under ${COLOR_CYAN}$HOME_DIR${COLOR_BLUE}...${COLOR_RESET}"
retry_command chown "$SUDO_USER:$SUDO_USER" "$HOME_DIR"
find "$HOME_DIR" -mindepth 1 ! -user "$SUDO_USER" -exec chown -h "$SUDO_USER:$SUDO_USER" {} + 2>/dev/null
if [ -d "$HOME_DIR/.ssh" ]; then
    retry_command chown -R "$SUDO_USER:$SUDO_USER" "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    find "$HOME_DIR/.ssh" -type f -exec chmod 600 {} +
fi
echo -e "${COLOR_GREEN}Ownership repair complete.${COLOR_RESET}"

# Reboot prompt
echo -e "${COLOR_GREEN}Setup complete! Reboot recommended.${COLOR_RESET}"
read -r -n 1 -p "Reboot now? [Y/n] " reboot_choice
echo
if [[ "$reboot_choice" =~ ^[Nn]$ ]]; then
    echo -e "${COLOR_GREEN}Reboot skipped. You can reboot manually later.${COLOR_RESET}"
else
    echo -e "${COLOR_BLUE}Rebooting...${COLOR_RESET}"
    sleep 1
    reboot
fi
