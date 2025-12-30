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
