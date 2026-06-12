# shellcheck shell=bash
# github.com/dillacorn/awtarchy
# ~/.bashrc - User-specific Bash configuration

# Only run if shell is interactive
[[ $- != *i* ]] && return

# --- Aliases ---
# Colorize common commands for better visibility
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Flatpak alias to always use --user flag on non-Btrfs systems
alias flatpak='flatpak --user'

# Shortcut to launch Hyprland under Wayland session
alias hypr='XDG_SESSION_TYPE=wayland exec start-hyprland'

# --- Environment Variables ---
# Default editor for command line text editing
export EDITOR=/usr/bin/micro

# GTK theme for graphical apps
export GTK_THEME=Materia-dark

# --- Prompt ---
# PS1 defines the command prompt appearance
# \w = full current working directory path
# \$ = shows '#' for root, '$' for normal user
# Icon can be customized, examples: 󰞷 (penguin), , λ, etc.
PS1='󰞷 \w\$ '

# --- Functions ---

# Run a command in the background, redirecting output to a log file
background() {
  if [ $# -lt 1 ]; then
    echo "Usage: background <command> [args...]"
    return 1
  fi

  # Sanitize command name for log filename (replace '/' with '_')
  local cmd_name="${1//\//_}"

  # Run command detached from terminal, log output in ~/.cache/
  nohup "$@" > ~/.cache/"$cmd_name".log 2>&1 < /dev/null &

  echo "$1 started in background. Logs: ~/.cache/$cmd_name.log"
}

dryrun() {
    # Check if file exists and is readable
    if [[ ! -f "$1" || ! -r "$1" ]]; then
        echo -e "\033[1;31m✘ Error: '$1' is not a readable script file\033[0m" >&2
        return 1
    fi

    local script_name
    script_name=$(basename "$1")
    echo -e "\n\033[1;33m🏗️  DRY RUN: \033[1;37m${script_name}\033[0m"
    
    # Syntax & lint check using ShellCheck
    echo -e "\n\033[1;34m🔎 ShellCheck Analysis:\033[0m"
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck "$1"; then
            echo -e "\033[1;32m✓ ShellCheck passed (no issues)\033[0m"
        else
            echo -e "\n\033[1;31m✘ ShellCheck found issues\033[0m" >&2
            return 1
        fi
    else
        echo -e "\033[1;31m✘ ShellCheck is not installed. Install it first:\033[0m"
        echo "  pacman -S shellcheck   # Arch"
        echo "  apt install shellcheck # Debian/Ubuntu"
        return 1
    fi

    # Command analysis with improved detection
    echo -e "\n\033[1;34m📊 Operations Analysis:\033[0m"
    
    declare -A categories=(
        ["🔧 System Modifications"]='sudo|install|ch(mod|own)|ufw|mount'
        ["📦 Package Management"]='yay|pacman|makepkg|flatpak|dnf|apt'
        ["🗂️  File Operations"]='rm\>|mv\>|cp\>|mkdir|ln\>'
        ["🔄 Git Operations"]='git\s+(clone|push|pull|reset|checkout)'
        ["🌐 Network Operations"]='curl\>|wget\>|ssh\>|scp\>'
    )
    
    local found_operations=false
    for category in "${!categories[@]}"; do
        local matches
        matches=$(grep -E --color=always -n "${categories[$category]}" "$1")
        if [[ -n "$matches" ]]; then
            found_operations=true
            echo -e "\n\033[1;35m${category}:\033[0m"
            echo "$matches" | while read -r line; do
                echo -e "  \033[1;36mLine ${line%%:*}\033[0m: ${line#*:}"
            done
        fi
    done

    if ! $found_operations; then
        echo -e "\033[1;37mNo potentially impactful operations found\033[0m"
    fi

    echo -e "\n\033[1;33m💡 Dry run complete. To execute:\033[0m\n\033[1;32m./${script_name}\033[0m"
}

# Remove older awtarchy AUR Guard wrappers if this shell already loaded them.
unset -f yay paru 2>/dev/null

# --- AUR Guard ---
# Safe-by-default AUR workflow for interactive shells.
#
# Blocked by default:
#   yay
#   yay -Syu
#   paru
#   paru -Syu
#
# Normal intended workflow:
#   sysupdate             # update enabled pacman repo packages
#   aurcheck              # list available AUR updates
#   aurverify package     # scan PKGBUILD and verify source checksums, install nothing
#   aurup package         # verify first, then install/update one AUR package
#
# Unsafe override:
#   aurunsafe yay -Syu
#   aurunsafe paru -Syu

# Remove older awtarchy AUR wrappers if this shell already loaded them.
unset -f yay paru 2>/dev/null

_aur_guard_bad_packages='^(exodus-wallet-bin|gnome-randr-rust|minitube|ktea|librewolf-fix-bin|firefox-patch-bin|zen-browser-patched-bin|minecraft-cracked|ttf-ms-fonts-all|vesktop-bin-patched)$'

_aur_guard_block_re='atomic-lockfile|lockfile-js|js-digest|digest-js|js-lockfile|src/hooks/deps|/api/agent|hidden_pids|hidden_names|hidden_inodes|curl[[:space:]].*\|[[:space:]]*(sh|bash)|wget[[:space:]].*\|[[:space:]]*(sh|bash)|base64[[:space:]]+(-d|--decode)|eval[[:space:]]|/dev/tcp|npm[[:space:]]+(install|i|add)|bun[[:space:]]+(install|add|i)|"(preinstall|postinstall)"[[:space:]]*:'

_aur_guard_pass() {
  local msg="$1"
  printf '\n\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
  printf '\033[1;32mPASSED:\033[0m %s\n' "$msg"
  printf '\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
}

_aur_guard_fail() {
  local msg="$1"
  printf '\n\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' >&2
  printf '\033[1;31mFAILED:\033[0m %s\n' "$msg" >&2
  printf '\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n' >&2
}

_aur_guard_pick_helper() {
  if type -P yay >/dev/null 2>&1; then
    printf 'yay\n'
  elif type -P paru >/dev/null 2>&1; then
    printf 'paru\n'
  else
    return 1
  fi
}

_aur_guard_is_mass_update() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  local arg
  for arg in "$@"; do
    case "$arg" in
      -Syu|-Syyu|-Syuu|-Syyyu|-Sua|--sysupgrade)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_has_unsafe_flag() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --noconfirm|--skipreview|--mflags|--mflags=*|--answerclean*|--answerdiff*|--answeredit*|--skippgpcheck|--skipchecksums|--skipinteg)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_block_message() {
  local helper="$1"

  printf '\033[1;31mAUR Guard blocked: %s mass update\033[0m\n\n' "$helper"
  printf 'AUR packages are user-made PKGBUILDs. Do not blindly mass-update them.\n\n'
  printf 'Use this workflow instead:\n'
  printf '  sysupdate             # update enabled pacman repo packages\n'
  printf '  aurcheck              # show AUR updates\n'
  printf '  aurverify package     # verify one AUR package, install nothing\n'
  printf '  aurup package         # verify first, then install/update one AUR package\n\n'
  printf 'Example:\n'
  printf '  sysupdate\n'
  printf '  aurcheck\n'
  printf '  aurverify sunshine-bin\n'
  printf '  aurup sunshine-bin\n\n'
  printf 'Unsafe override for advanced users only:\n'
  printf '  aurunsafe %s -Syu\n\n' "$helper"
  printf 'Help:\n'
  printf '  aurhelp\n'
}

aurhelp() {
  cat <<'AUR_GUARD_HELP'
AUR Guard quick help

Blocked:
  yay
  yay -Syu
  paru
  paru -Syu

Normal safe workflow:
  sysupdate             update enabled pacman repo packages
  aurcheck              show available AUR updates
  aurverify package     scan PKGBUILD and verify source checksums, install nothing
  aurup package         run aurverify first, then install/update one AUR package

Examples:
  sysupdate
  aurcheck
  aurverify awtwall
  aurup awtwall

Unsafe override:
  aurunsafe yay -Syu
  aurunsafe paru -Syu

Important:
  AUR packages are not official.
  Checksum verification only proves downloaded sources match the PKGBUILD.
  It does not prove the PKGBUILD itself is trustworthy.
AUR_GUARD_HELP
}

sysupdate() {
  sudo pacman -Syu
}

aurcheck() {
  local helper

  helper="$(_aur_guard_pick_helper)" || {
    printf 'No yay or paru found.\n' >&2
    return 127
  }

  command "$helper" -Qua
}

aurverify() {
  local helper pkg tmp pkgdir repo_name

  if [[ $# -ne 1 ]]; then
    printf 'Usage: aurverify package_name\n' >&2
    printf 'Example: aurverify awtwall\n' >&2
    return 1
  fi

  pkg="$1"

  if [[ "$pkg" =~ $_aur_guard_bad_packages ]]; then
    _aur_guard_fail "known reported suspicious package name: $pkg"
    return 1
  fi

  repo_name="$(pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')"
  if [[ -n "$repo_name" ]]; then
    printf 'AUR Verify: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Pacman package/signature checks apply for that repo.\n'
    _aur_guard_pass "$pkg is handled by pacman. Nothing was installed."
    return 0
  fi

  helper="$(_aur_guard_pick_helper)" || {
    _aur_guard_fail "no yay or paru found"
    return 127
  }

  tmp="$(mktemp -d)"

  if ! (cd "$tmp" || exit 1; command "$helper" -G "$pkg" >/dev/null 2>&1); then
    rm -rf "$tmp"
    _aur_guard_fail "failed to fetch PKGBUILD for $pkg"
    return 1
  fi

  pkgdir="$tmp/$pkg"
  if [[ ! -d "$pkgdir" ]]; then
    pkgdir="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  fi

  if [[ ! -d "$pkgdir" || ! -f "$pkgdir/PKGBUILD" ]]; then
    rm -rf "$tmp"
    _aur_guard_fail "could not locate PKGBUILD for $pkg"
    return 1
  fi

  printf 'AUR Verify: scanning PKGBUILD for obvious risky patterns.\n'

  if grep -RInE \
    --include='PKGBUILD' \
    --include='*.install' \
    --include='*.service' \
    --include='*.timer' \
    --include='*.hook' \
    --include='package.json' \
    --include='package-lock.json' \
    --include='bun.lock' \
    --include='bun.lockb' \
    "$_aur_guard_block_re" "$pkgdir"; then
    rm -rf "$tmp"
    _aur_guard_fail "suspicious pattern found in $pkg"
    return 1
  fi

  grep -RInE --include='PKGBUILD' --include='*.install' '^[[:space:]]*install=|post_install|post_upgrade|pre_install|pre_upgrade' "$pkgdir" || true

  printf 'AUR Verify: verifying downloaded sources against PKGBUILD checksums.\n'

  if ! (cd "$pkgdir" || exit 1; makepkg --verifysource); then
    rm -rf "$tmp"
    _aur_guard_fail "source checksum or PGP verification failed for $pkg"
    return 1
  fi

  rm -rf "$tmp"
  _aur_guard_pass "$pkg passed AUR verification. Nothing was installed."
}

aurup() {
  local helper pkg repo_name

  if [[ $# -ne 1 ]]; then
    printf 'Usage: aurup package_name\n' >&2
    printf 'Example: aurup awtwall\n' >&2
    return 1
  fi

  pkg="$1"

  repo_name="$(pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')"
  if [[ -n "$repo_name" ]]; then
    printf 'AUR Guard: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Installing with pacman:\n'
    printf '  sudo pacman -S %s\n\n' "$pkg"
    sudo pacman -S "$pkg"
    return $?
  fi

  helper="$(_aur_guard_pick_helper)" || {
    printf 'No yay or paru found.\n' >&2
    return 127
  }

  aurverify "$pkg" || return 1
  command "$helper" -S "$pkg"
}

aurunsafe() {
  local helper="$1"
  shift || true

  case "$helper" in
    yay|paru)
      ;;
    *)
      printf 'Usage: aurunsafe yay|paru [args...]\n' >&2
      printf 'Example: aurunsafe yay -Syu\n' >&2
      return 1
      ;;
  esac

  if ! type -P "$helper" >/dev/null 2>&1; then
    printf '%s is not installed or not in PATH.\n' "$helper" >&2
    return 127
  fi

  printf '\033[1;31mUnsafe AUR override requested.\033[0m\n'
  printf 'This bypasses AUR Guard and runs raw %s.\n' "$helper"
  printf 'Type exactly YES to continue: '

  local answer
  read -r answer

  if [[ "$answer" != "YES" ]]; then
    printf 'Cancelled.\n'
    return 1
  fi

  command "$helper" "$@"
}

yay() {
  if _aur_guard_has_unsafe_flag "$@"; then
    printf 'AUR Guard blocked unsafe yay flags. Use aurhelp.\n' >&2
    return 1
  fi

  if _aur_guard_is_mass_update "$@"; then
    _aur_guard_block_message yay
    return 1
  fi

  command yay "$@"
}

paru() {
  if _aur_guard_has_unsafe_flag "$@"; then
    printf 'AUR Guard blocked unsafe paru flags. Use aurhelp.\n' >&2
    return 1
  fi

  if _aur_guard_is_mass_update "$@"; then
    _aur_guard_block_message paru
    return 1
  fi

  command paru "$@"
}

