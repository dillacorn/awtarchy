#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/awtarchy-tips-dialog.sh
#
# Startup tips dialog with optional self-disable.
# Uses hyprland-dialog buttons to open links.
#
# Re-enable command (what the dialog will show/copy):
#   rm -f "/home/youruser/.local/state/hypr/awtarchy-tips-disabled"
# The script builds this from the real path on your system.

set -euo pipefail

# Disable flag (created when user chooses Disable)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
DISABLE_FILE="$STATE_DIR/awtarchy-tips-disabled"
mkdir -p "$STATE_DIR"

[[ -f "$DISABLE_FILE" ]] && exit 0

# Re-enable command shown to user and copyable (no ShellCheck SC2016)
REENABLE_CMD="rm -f \"$DISABLE_FILE\""

# Links
SMTTY_URL="https://github.com/dillacorn/smtty"
LINUX_TKG_URL="https://github.com/Frogging-Family/linux-tkg"
AWTARCHY_TKG_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/extra_notes/install_linux-tkg.md"
OPTIONAL_PACKAGES_URL="https://github.com/dillacorn/awtarchy/blob/main/extra_notes/optional_packages.md"

CACHYOS_KERNEL_AUR_URL="https://aur.archlinux.org/packages/linux-cachyos"
CACHYOS_HEADERS_AUR_URL="https://aur.archlinux.org/packages/linux-cachyos-headers"
CACHYOS_LTS_AUR_URL="https://aur.archlinux.org/packages/linux-cachyos-lts"
CACHYOS_LTS_HEADERS_AUR_URL="https://aur.archlinux.org/packages/linux-cachyos-lts-headers"

SYSTEMD_BOOT_WIKI_URL="https://wiki.archlinux.org/title/Systemd-boot"
BOOTCTL_MAN_URL="https://man.archlinux.org/man/bootctl.1.en"

PROTONPLUS_FLATHUB_URL="https://flathub.org/apps/com.vysp3r.ProtonPlus"

FIREFOX_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/firefox.md"
BRAVE_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/brave.md"
MULLVAD_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/mullvad.md"

open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  elif command -v gio >/dev/null 2>&1; then
    gio open "$url" >/dev/null 2>&1 &
  fi
}

copy_text() {
  local text="$1"
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard
    return 0
  fi
  if command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input
    return 0
  fi
  return 1
}

dialog() {
  local title="$1"
  local text="$2"
  local buttons="$3"
  local choice

  choice="$(hyprland-dialog --title "$title" --text "$text" --buttons "$buttons" 2>/dev/null || true)"
  choice="${choice//$'\n'/}"
  choice="${choice//$'\r'/}"
  printf '%s' "$choice"
}

if ! command -v hyprland-dialog >/dev/null 2>&1; then
  exit 0
fi

TITLE_MAIN="Hyprland Tips"
TEXT_MAIN=$'Pick a category.\n\nShort labels to avoid overlap.'

STATE="main"

while true; do
  case "$STATE" in
    main)
      choice="$(dialog "$TITLE_MAIN" "$TEXT_MAIN" "Kernels;Boot;Tools;Browsers;Optional;Disable;Close")"
      case "$choice" in
        "Kernels") STATE="kernels" ;;
        "Boot") STATE="boot" ;;
        "Tools") STATE="tools" ;;
        "Browsers") STATE="browsers" ;;
        "Optional") open_url "$OPTIONAL_PACKAGES_URL" ;;
        "Disable") STATE="disable_confirm" ;;
        "Close"|"" ) exit 0 ;;
        *) exit 0 ;;
      esac
      ;;

    disable_confirm)
      choice="$(dialog "Disable on startup?" "Stop showing this dialog automatically?" "Disable;Back;Close")"
      case "$choice" in
        "Disable")
          : > "$DISABLE_FILE"
          STATE="disabled_notice"
          ;;
        "Back") STATE="main" ;;
        "Close"|"" ) exit 0 ;;
        *) STATE="main" ;;
      esac
      ;;

    disabled_notice)
      TEXT_D=$'Disabled on startup.\n\nRe-enable with:\n'"$REENABLE_CMD"
      choice="$(dialog "Disabled" "$TEXT_D" "Copy command;OK")"
      case "$choice" in
        "Copy command")
          copy_text "$REENABLE_CMD" || true
          ;;
        "OK"|"" )
          exit 0
          ;;
        *)
          exit 0
          ;;
      esac
      ;;

    kernels)
      choice="$(dialog "Kernels" "Kernel links." "linux-tkg;linux-tkg notes;CachyOS AUR;Back;Close")"
      case "$choice" in
        "linux-tkg") open_url "$LINUX_TKG_URL" ;;
        "linux-tkg notes") open_url "$AWTARCHY_TKG_NOTES_URL" ;;
        "CachyOS AUR")
          open_url "$CACHYOS_KERNEL_AUR_URL"
          open_url "$CACHYOS_HEADERS_AUR_URL"
          open_url "$CACHYOS_LTS_AUR_URL"
          open_url "$CACHYOS_LTS_HEADERS_AUR_URL"
          ;;
        "Back") STATE="main" ;;
        "Close"|"" ) exit 0 ;;
        *) STATE="main" ;;
      esac
      ;;

    boot)
      choice="$(dialog "systemd-boot" "Boot resources." "ArchWiki;bootctl man;Back;Close")"
      case "$choice" in
        "ArchWiki") open_url "$SYSTEMD_BOOT_WIKI_URL" ;;
        "bootctl man") open_url "$BOOTCTL_MAN_URL" ;;
        "Back") STATE="main" ;;
        "Close"|"" ) exit 0 ;;
        *) STATE="main" ;;
      esac
      ;;

    tools)
      choice="$(dialog "Tools" "Tools links." "ProtonPlus;smtty;Back;Close")"
      case "$choice" in
        "ProtonPlus") open_url "$PROTONPLUS_FLATHUB_URL" ;;
        "smtty") open_url "$SMTTY_URL" ;;
        "Back") STATE="main" ;;
        "Close"|"" ) exit 0 ;;
        *) STATE="main" ;;
      esac
      ;;

    browsers)
      choice="$(dialog "Browsers" "Browser notes." "Firefox;Brave;Mullvad;Back;Close")"
      case "$choice" in
        "Firefox") open_url "$FIREFOX_NOTES_URL" ;;
        "Brave") open_url "$BRAVE_NOTES_URL" ;;
        "Mullvad") open_url "$MULLVAD_NOTES_URL" ;;
        "Back") STATE="main" ;;
        "Close"|"" ) exit 0 ;;
        *) STATE="main" ;;
      esac
      ;;
  esac
done
