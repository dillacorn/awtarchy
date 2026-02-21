# github.com/dillacorn/awtarchy
# ~/.bash_profile - User login configuration

# Source ~/.bashrc if it exists (common practice to keep shell settings centralized)
if [[ -f ~/.bashrc ]]; then
  . ~/.bashrc
fi

export PATH="$HOME/.local/bin:$PATH"

# Run fastfetch with a TTY-friendly config (system info tool)
fastfetch --config ~/.config/fastfetch/tty_compatible.jsonc

# Inform user how to start Hyprland (your Wayland compositor)
echo -e "\033[1;34mTo start Hyprland, type: \033[1;31mhypr\033[0m"

# --- Fun message function ---
# Randomly suggests a fun terminal command to try on login
add_random_fun_message() {
  # Array of fun commands to try
  local fun_messages=(
    "cacafire"
    "cmatrix"
    "aafire"
    "asciiquarium"
    "figlet TTY is cool"
    "termdown 10"
    "termdown -z"
    "termdown -v en 10"
    "espeak-ng -s 150 'I, love, TTY'"
  )
  
  # Pick a random command from the list
  RANDOM_FUN_MESSAGE="${fun_messages[RANDOM % ${#fun_messages[@]}]}"
  
  # Print a colorful suggestion message
  echo -e "\033[1;33mFor some fun, try running \033[1;31m$RANDOM_FUN_MESSAGE\033[1;33m!\033[0m"
}

# Call the fun message function on login
add_random_fun_message
