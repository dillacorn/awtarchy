#!/usr/bin/env bash
set -euo pipefail
selection="$(printf '%s\n' 'Lock' 'Suspend' 'Reboot' 'Power off' 'End Mango session' | fuzzel --dmenu --prompt 'Power: ')" || exit 0
case "$selection" in
    'Lock') swaylock -f -c 10151c ;;
    'Suspend') swaylock -f -c 10151c && systemctl suspend ;;
    'Reboot') systemctl reboot ;;
    'Power off') systemctl poweroff ;;
    'End Mango session') mmsg dispatch quit ;;
esac
