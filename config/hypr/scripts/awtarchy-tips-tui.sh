#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/awtarchy-tips-tui.sh
#
# Re-enable tips on login (if you disabled autostart):
#   rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/hypr/awtarchy-tips-disabled"
#
# Controls:
#   - Main menu: 1-7, Q quit
#   - Submenus:  1-n open, B back, Q quit
#   - Extra Notes:
#       Up/Down = (j/k) move
#       O open selected note
#       G open GitHub link to extra_notes folder
#       B back, Q quit
#
# Autostart behavior:
#   - Login/autostart should call:  awtarchy-tips-tui.sh --autostart
#   - Manual launches always run (even if autostart is disabled).

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
DISABLE_FILE="$STATE_DIR/awtarchy-tips-disabled"
mkdir -p "$STATE_DIR"

FOCUS_BROWSER="${AWTARCHY_TIPS_FOCUS_BROWSER:-1}"

# Static links
SMTTY_URL="https://github.com/dillacorn/smtty"
LINUX_TKG_URL="https://github.com/Frogging-Family/linux-tkg"
AWTARCHY_TKG_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/extra_notes/build%2Binstall_linux-tkg-kernal.md"

CACHYOS_LINUX_CACHYOS_URL="https://github.com/CachyOS/linux-cachyos?tab=readme-ov-file#quick-installation"
CACHYOS_KERNEL_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/extra_notes/install_cachy-kernal.md"

SYSTEMD_BOOT_WIKI_URL="https://wiki.archlinux.org/title/Systemd-boot"
BOOTCTL_MAN_URL="https://man.archlinux.org/man/bootctl.1.en"

PROTONPLUS_FLATHUB_URL="https://flathub.org/apps/com.vysp3r.ProtonPlus"

FIREFOX_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/firefox.md"
BRAVE_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/brave.md"
MULLVAD_NOTES_URL="https://github.com/dillacorn/awtarchy/blob/main/browser_notes/mullvad.md"

EXTRA_NOTES_FOLDER_URL="https://github.com/dillacorn/awtarchy/tree/main/extra_notes"
OPTIONAL_PACKAGES_URL="https://github.com/dillacorn/awtarchy/blob/main/extra_notes/optional_packages.md"

# extra_notes (hardcoded)
EXTRA_NAMES=(
  "ARCH-safe_orphaned_package_removal.md"
  "AUR-safe_orphaned_package_removal.md"
  "Add_Persistent_Drive_fstab_Directions.md"
  "Arch_LTS_kernel_fallback.md"
  "Enable_Parallel_Downloads_on_Arch.md"
  "Post-archinstall troubleshooting guide.md"
  "Pre-archinstall troubleshooting guide.md"
  "Steam_Launch_Options_Wayland_Hyprland.md"
  "VPN_wireguard_guide.md"
  "WiFi_Arch_b4_archinstall.md"
  "build+install_linux-tkg-kernal.md"
  "fragile-monitor-boot-workaround.md"
  "install_cachy-kernal.md"
  "noise_suppression.md"
  "optional_packages.md"
  "sunshine+moonlight_lag?.md"
)

EXTRA_URLS=(
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/ARCH-safe_orphaned_package_removal.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/AUR-safe_orphaned_package_removal.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Add_Persistent_Drive_fstab_Directions.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Arch_LTS_kernel_fallback.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Enable_Parallel_Downloads_on_Arch.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Post-archinstall%20troubleshooting%20guide.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Pre-archinstall%20troubleshooting%20guide.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/Steam_Launch_Options_Wayland_Hyprland.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/VPN_wireguard_guide.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/WiFi_Arch_b4_archinstall.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/build%2Binstall_linux-tkg-kernal.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/fragile-monitor-boot-workaround.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/install_cachy-kernal.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/noise_suppression.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/optional_packages.md"
  "https://github.com/dillacorn/awtarchy/blob/main/extra_notes/sunshine%2Bmoonlight_lag%3F.md"
)

TTY_IN_FD=3
TTY_OUT_FD=4
STTY_SAVED=""

say() { printf '%s\r\n' "$*" 1>&${TTY_OUT_FD}; }

clear_screen() {
  local seq=$'\033[2J\033[H'
  if command -v tput >/dev/null 2>&1 && [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    if tput clear 1>&${TTY_OUT_FD} 2>/dev/null; then
      return 0
    fi
  fi
  printf '%s' "$seq" 1>&${TTY_OUT_FD}
}

setup_tty_fds() {
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    exec {TTY_IN_FD}</dev/tty
    exec {TTY_OUT_FD}>/dev/tty
  else
    exec {TTY_IN_FD}<&0
    exec {TTY_OUT_FD}>&1
  fi
}

tui_stty_on() {
  STTY_SAVED="$(stty -g <&${TTY_IN_FD} 2>/dev/null || true)"
  stty -echo -icanon min 1 time 0 -ixon <&${TTY_IN_FD} 2>/dev/null || true
}

tui_stty_off() {
  if [[ -n "${STTY_SAVED:-}" ]]; then
    stty "$STTY_SAVED" <&${TTY_IN_FD} 2>/dev/null || true
  fi
}

read_escape_tail() {
  # Read the remainder of an escape sequence after the initial ESC.
  # Works with: ESC [ A, ESC O A, ESC [ 1 ; 5 A, etc.
  local s="" ch=""
  while IFS= read -rsn1 -t 0.05 ch <&${TTY_IN_FD}; do
    s+="$ch"
    [[ ${#s} -ge 32 ]] && break
    [[ "$ch" =~ [@-~] ]] && break
  done
  printf '%s' "$s"
}

read_key() {
  # tokens: up/down/pgup/pgdn/home/end/enter/esc/backspace or single lowercased char
  local c=""
  IFS= read -rsn1 c <&${TTY_IN_FD} || { printf ''; return 0; }

  case "$c" in
    $'\r'|$'\n') printf 'enter'; return 0 ;;
    $'\x7f')     printf 'backspace'; return 0 ;;
    $'\x1b')
      local tail
      tail="$(read_escape_tail)"

      # Treat bare ESC as esc.
      [[ -z "$tail" ]] && { printf 'esc'; return 0; }

      # Normalize: arrows are any CSI/SS3 that ends with A/B.
      case "$tail" in
        \[*A|O*A) printf 'up'; return 0 ;;
        \[*B|O*B) printf 'down'; return 0 ;;
      esac

      # Home/End variants.
      case "$tail" in
        \[*H|O*H|\[1~|\[7~) printf 'home'; return 0 ;;
        \[*F|O*F|\[4~|\[8~) printf 'end'; return 0 ;;
        \[5~) printf 'pgup'; return 0 ;;
        \[6~) printf 'pgdn'; return 0 ;;
      esac

      printf 'esc'
      return 0
      ;;
  esac

  printf '%s' "${c,,}"
}

press_any_key() {
  say ""
  say "Press any key..."
  local _k
  _k="$(read_key)"
  : "${_k}"
}

open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
    return 0
  fi
  if command -v gio >/dev/null 2>&1; then
    gio open "$url" >/dev/null 2>&1 &
    return 0
  fi
  return 1
}

focus_browser_window() {
  [[ "$FOCUS_BROWSER" == "1" ]] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  python3 - <<'PY' >/tmp/awtarchy_tips_focus_target 2>/dev/null || true
import json, subprocess, re, sys
cands = [
  r"^firefox$",
  r"^brave-browser$",
  r"^mullvad-browser$",
  r"^chromium$",
  r"^google-chrome$",
  r"^zen-browser$",
  r"^floorp$",
]
try:
  out = subprocess.check_output(["hyprctl", "-j", "clients"], text=True)
  clients = json.loads(out)
except Exception:
  sys.exit(0)

for pat in cands:
  rx = re.compile(pat, re.I)
  for c in clients:
    cls = (c.get("class") or "").strip()
    if cls and rx.search(cls):
      print(cls)
      sys.exit(0)
PY

  local cls=""
  cls="$(cat /tmp/awtarchy_tips_focus_target 2>/dev/null || true)"
  rm -f /tmp/awtarchy_tips_focus_target >/dev/null 2>&1 || true
  [[ -n "$cls" ]] || return 0

  sleep 0.05 || true
  hyprctl dispatch focuswindow "class:^(${cls})$" >/dev/null 2>&1 || true
}

status_open_or_fail() {
  local url="$1" ok_msg="$2"
  if open_url "$url"; then
    focus_browser_window
    say "$ok_msg"
  else
    say "Failed to open browser"
  fi
}

pick_terminal() {
  if [[ -n "${TERMINAL:-}" ]]; then
    local bin="${TERMINAL%% *}"
    if command -v "$bin" >/dev/null 2>&1; then
      printf '%s' "$TERMINAL"
      return 0
    fi
  fi

  local cand
  for cand in footclient foot kitty alacritty wezterm konsole gnome-terminal xfce4-terminal xterm; do
    if command -v "$cand" >/dev/null 2>&1; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

spawn_in_terminal() {
  [[ -n "${AWTARCHY_TIPS_TUI_SPAWNED:-}" ]] && return 1

  local term self
  term="$(pick_terminal)" || return 1
  self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
  export AWTARCHY_TIPS_TUI_SPAWNED=1

  case "${term%% *}" in
    foot|footclient)
      # shellcheck disable=SC2086
      exec $term -e bash -lc "\"$self\" --tui"
      ;;
    kitty)
      # shellcheck disable=SC2086
      exec $term -- bash -lc "\"$self\" --tui"
      ;;
    wezterm)
      exec wezterm start -- bash -lc "\"$self\" --tui"
      ;;
    gnome-terminal)
      exec gnome-terminal -- bash -lc "\"$self\" --tui"
      ;;
    *)
      # shellcheck disable=SC2086
      exec $term -e bash -lc "\"$self\" --tui"
      ;;
  esac
}

screen_lines() {
  if command -v tput >/dev/null 2>&1 && [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    tput lines 2>/dev/null || echo 24
  else
    echo 24
  fi
}

page_size_for_screen() {
  local lines ps
  lines="$(screen_lines)"
  ps=$(( lines - 12 ))
  (( ps < 8 )) && ps=8
  (( ps > 30 )) && ps=30
  echo "$ps"
}

# ---------- Menus ----------

menu_kernels() {
  while true; do
    clear_screen
    say "awtarchy tips > kernals"
    say ""
    say "[1]  linux-tkg (repo)"
    say "[2]  tkg notes (awtarchy)"
    say "[3]  CachyOS linux-cachyos (repo)"
    say "[4]  Cachy notes (awtarchy)"
    say ""
    say "B back    Q quit"
    say ""
    case "$(read_key)" in
      1) status_open_or_fail "$LINUX_TKG_URL" "Opened: linux-tkg"; press_any_key ;;
      2) status_open_or_fail "$AWTARCHY_TKG_NOTES_URL" "Opened: tkg notes"; press_any_key ;;
      3) status_open_or_fail "$CACHYOS_LINUX_CACHYOS_URL" "Opened: CachyOS linux-cachyos"; press_any_key ;;
      4) status_open_or_fail "$CACHYOS_KERNEL_NOTES_URL" "Opened: Cachy notes"; press_any_key ;;
      b|esc) return 0 ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

menu_boot() {
  while true; do
    clear_screen
    say "awtarchy tips > boot"
    say ""
    say "[1]  systemd-boot (ArchWiki)"
    say "[2]  bootctl (man page)"
    say ""
    say "B back    Q quit"
    say ""
    case "$(read_key)" in
      1) status_open_or_fail "$SYSTEMD_BOOT_WIKI_URL" "Opened: ArchWiki systemd-boot"; press_any_key ;;
      2) status_open_or_fail "$BOOTCTL_MAN_URL" "Opened: bootctl man"; press_any_key ;;
      b|esc) return 0 ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

menu_tools() {
  while true; do
    clear_screen
    say "awtarchy tips > tools"
    say ""
    say "[1]  ProtonPlus (Flathub)"
    say "[2]  smtty (repo)"
    say ""
    say "B back    Q quit"
    say ""
    case "$(read_key)" in
      1) status_open_or_fail "$PROTONPLUS_FLATHUB_URL" "Opened: ProtonPlus"; press_any_key ;;
      2) status_open_or_fail "$SMTTY_URL" "Opened: smtty"; press_any_key ;;
      b|esc) return 0 ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

menu_browsers() {
  while true; do
    clear_screen
    say "awtarchy tips > browsers"
    say ""
    say "[1]  Firefox notes"
    say "[2]  Brave notes"
    say "[3]  Mullvad notes"
    say ""
    say "B back    Q quit"
    say ""
    case "$(read_key)" in
      1) status_open_or_fail "$FIREFOX_NOTES_URL" "Opened: Firefox notes"; press_any_key ;;
      2) status_open_or_fail "$BRAVE_NOTES_URL" "Opened: Brave notes"; press_any_key ;;
      3) status_open_or_fail "$MULLVAD_NOTES_URL" "Opened: Mullvad notes"; press_any_key ;;
      b|esc) return 0 ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

menu_disable_toggle() {
  if [[ -f "$DISABLE_FILE" ]]; then
    rm -f "$DISABLE_FILE" || true
    clear_screen
    say "Enabled tips on login."
    press_any_key
    return 0
  fi

  : >"$DISABLE_FILE"
  clear_screen
  say "Disabled tips on login."
  say ""
  say "Re-enable:"
  say "  rm -f \"$DISABLE_FILE\""
  press_any_key
}

extra_notes_draw() {
  local cursor="$1" ps="$2" total="$3"
  local page_start=$(( (cursor / ps) * ps ))
  local page_end=$(( page_start + ps ))
  (( page_end > total )) && page_end=$total

  local page=$(( (cursor / ps) + 1 ))
  local pages=$(( (total + ps - 1) / ps ))
  (( pages < 1 )) && pages=1

  clear_screen
  say "awtarchy tips > extra_notes   (page ${page}/${pages})"
  say ""
  say "Up/Down = (j/k) move"
  say "O open selected note"
  say "G open GitHub link to extra_notes folder"
  say "B back   Q quit"
  say ""

  local i
  for (( i=page_start; i<page_end; i++ )); do
    if (( i == cursor )); then
      say "> ${EXTRA_NAMES[i]}"
    else
      say "  ${EXTRA_NAMES[i]}"
    fi
  done
}

menu_extra_notes() {
  local cursor=0 ps total
  ps="$(page_size_for_screen)"
  total="${#EXTRA_NAMES[@]}"

  while true; do
    (( cursor < 0 )) && cursor=0
    (( cursor >= total )) && cursor=$(( total - 1 ))

    extra_notes_draw "$cursor" "$ps" "$total"

    case "$(read_key)" in
      up|k)   (( cursor > 0 )) && cursor=$(( cursor - 1 )) ;;
      down|j) (( cursor < total - 1 )) && cursor=$(( cursor + 1 )) ;;
      pgup)   cursor=$(( cursor - ps )); (( cursor < 0 )) && cursor=0 ;;
      pgdn)   cursor=$(( cursor + ps )); (( cursor > total - 1 )) && cursor=$(( total - 1 )) ;;
      home)   cursor=0 ;;
      end)    cursor=$(( total - 1 )) ;;
      o)
        status_open_or_fail "${EXTRA_URLS[cursor]}" "Opened: ${EXTRA_NAMES[cursor]}"
        press_any_key
        ;;
      g)
        status_open_or_fail "$EXTRA_NOTES_FOLDER_URL" "Opened: extra_notes folder"
        press_any_key
        ;;
      b|esc) return 0 ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

main_menu() {
  while true; do
    clear_screen
    say "awtarchy tips"
    say ""
    say "[1]  Kernals"
    say "[2]  Boot"
    say "[3]  Tools"
    say "[4]  Browsers"
    say "[5]  Extra Notes"
    say "[6]  Optional"

    if [[ -f "$DISABLE_FILE" ]]; then
      say "[7]  Enable tips on login"
    else
      say "[7]  Disable tips on login"
    fi

    say ""
    say "Q quit"
    say ""

    case "$(read_key)" in
      1) menu_kernels ;;
      2) menu_boot ;;
      3) menu_tools ;;
      4) menu_browsers ;;
      5) menu_extra_notes ;;
      6) status_open_or_fail "$OPTIONAL_PACKAGES_URL" "Opened: optional_packages.md"; press_any_key ;;
      7) menu_disable_toggle ;;
      q) exit 0 ;;
      *) ;;
    esac
  done
}

main() {
  local mode="manual"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tui) mode="tui" ;;
      --autostart) mode="autostart" ;;
      -h|--help)
        printf '%s\n' "Usage: $0 [--tui] [--autostart]"
        exit 0
        ;;
      *)
        printf '%s\n' "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
    shift
  done

  if [[ "$mode" == "autostart" && -f "$DISABLE_FILE" ]]; then
    exit 0
  fi

  if [[ "$mode" != "tui" ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
      spawn_in_terminal || exit 0
    fi
  fi

  setup_tty_fds
  trap 'tui_stty_off' EXIT
  tui_stty_on
  main_menu
}

main "$@"
