#!/usr/bin/env bash
set -euo pipefail

# Optional: install and enable Ly (TUI display/login manager) on tty2.
# Ly is a lightweight terminal (TTY) greeter. It runs on a Linux virtual console and can start Wayland sessions
# by launching entries from /usr/share/wayland-sessions/*.desktop.
#
# Run: sudo ./install_ly.sh

TTY="tty2"

if [[ ${EUID:-0} -ne 0 ]]; then
  echo "Run as root (use sudo)." >&2
  exit 1
fi

echo
echo "Ly is a lightweight terminal (TTY) display/login manager (greeter)."
echo "If enabled, it replaces getty on ${TTY} and shows a login screen on that TTY after reboot."
echo "From Ly you can select a session (Hyprland, etc.) and start it."
echo
read -r -p "Install and enable Ly on ${TTY}? (y/N): " resp
case "${resp:-}" in
  [Yy]) ;;
  *) echo "Skipping Ly install."; exit 0 ;;
esac

# Ensure Hyprland shows in Ly
if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
  cat > /usr/share/wayland-sessions/hyprland.desktop <<'EOF'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland compositor
Exec=Hyprland
Type=Application
EOF
fi

# Install ly if missing
if ! command -v ly >/dev/null 2>&1; then
  pacman -S --needed --noconfirm ly
fi

# Create ly@.service if it doesn't exist anywhere
if [[ ! -f /etc/systemd/system/ly@.service && ! -f /usr/lib/systemd/system/ly@.service ]]; then
  cat > /etc/systemd/system/ly@.service <<'EOF'
[Unit]
Description=Ly TUI display manager (%I)
After=systemd-user-sessions.service
After=getty@%i.service

[Service]
Type=idle
ExecStart=/usr/bin/ly
StandardInput=tty
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes

[Install]
Alias=display-manager.service
EOF
fi

systemctl daemon-reload

# Free the tty from getty, then enable ly on that tty
systemctl disable --now "getty@${TTY}.service" 2>/dev/null || true
systemctl enable --now "ly@${TTY}.service"

# Boot to a DM
systemctl set-default graphical.target

echo "OK: enabled ly@${TTY}.service"
echo "Reboot."
