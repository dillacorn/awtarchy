#!/usr/bin/env bash
set -eEuo pipefail

# install_GPU_dependencies.sh
# Arch-based GPU deps + NVIDIA driver selector.
# Safe for install.sh running it via sudo/root:
# - Root is allowed.
# - User-only steps (AUR builds, Hyprland config edits) run as SUDO_USER when available.
# Default behavior is NONFATAL (exit 0 even if something fails) so dotfiles installs won't abort.

ts(){ date +%F_%H%M%S; }
log(){ printf '%s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

NONFATAL=1
DO_UPGRADE=0
INSTALL_LIB32=1
INSTALL_OPENCL=0
PATCH_HYPRLAND=1
SET_MODESET=1
FORCE_NVIDIA_MODE=""   # open|legacy|skip
NO_AUR_BOOTSTRAP=0

usage(){
  cat >&2 <<'EOF'
Usage: install_GPU_dependencies.sh [options]
  --fatal                  Exit non-zero on failure (default: nonfatal exit 0)
  --upgrade                Run pacman -Syu first (default: off)
  --no-lib32               Skip multilib/lib32 packages
  --opencl                 Install OpenCL packages where applicable
  --no-hyprland             Do not patch Hyprland config for NVIDIA
  --no-modeset              Do not set nvidia_drm modeset=1
  --force-nvidia <mode>    open|legacy|skip
  --no-aur-bootstrap        Do not auto-install yay if no AUR helper is present
EOF
}

on_err(){
  local rc=$? line=${1:-?} cmd=${2:-?}
  if (( NONFATAL )); then
    warn "GPU script failed (nonfatal): rc=$rc line=$line cmd=$cmd"
    warn "Dotfiles install should continue."
    exit 0
  fi
  die "GPU script failed: rc=$rc line=$line cmd=$cmd"
}
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR

# args
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --fatal) NONFATAL=0; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-lib32) INSTALL_LIB32=0; shift ;;
    --opencl) INSTALL_OPENCL=1; shift ;;
    --no-hyprland) PATCH_HYPRLAND=0; shift ;;
    --no-modeset) SET_MODESET=0; shift ;;
    --no-aur-bootstrap) NO_AUR_BOOTSTRAP=1; shift ;;
    --force-nvidia)
      FORCE_NVIDIA_MODE="${2:-}"; shift 2 ;;
    --force-nvidia=*)
      FORCE_NVIDIA_MODE="${1#*=}"; shift ;;
    --) shift; break ;;
    *) shift ;;
  esac
done

# Who is the "real" user for user-only operations?
# If invoked via sudo from install.sh, SUDO_USER will be set.
RUN_USER="${SUDO_USER:-${USER:-}}"
if [[ "${EUID:-$(id -u)}" -eq 0 ]] && [[ "${RUN_USER:-}" == "root" ]]; then
  RUN_USER=""
fi

USER_HOME="${HOME}"
if [[ -n "${RUN_USER:-}" ]]; then
  USER_HOME="$(getent passwd "$RUN_USER" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "$USER_HOME" ]] || USER_HOME="${HOME}"
fi

as_root(){
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi
  if ! sudo -n true 2>/dev/null; then sudo -v; fi
  sudo "$@"
}

as_user(){
  # Only needed for AUR helpers/builds and user config edits.
  [[ -n "${RUN_USER:-}" ]] || die "No SUDO_USER detected. Run install.sh as a normal user (sudo as needed), not as root."
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    if have sudo; then
      sudo -u "$RUN_USER" -H env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
    elif have runuser; then
      runuser -u "$RUN_USER" -- env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
    else
      die "Need sudo or runuser to run commands as $RUN_USER."
    fi
  else
    "$@"
  fi
}

backup_root_file(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  as_root cp -a "$f" "${f}.bak.$(ts)"
}

pacman_q(){ pacman -Q "$1" >/dev/null 2>&1; }
pacman_si(){ pacman -Si "$1" >/dev/null 2>&1; }

pacman_install(){
  as_root pacman -S --needed --noconfirm "$@"
}

pacman_remove(){
  as_root pacman -Rns --noconfirm "$@" 2>/dev/null || true
}

multilib_enabled(){
  [[ -f /etc/pacman.conf ]] || return 1
  awk '
    $0 ~ /^[[:space:]]*#/{next}
    $0 ~ /^\[multilib\]/{found=1}
    found && $0 ~ /^Include[[:space:]]*=/{ok=1}
    END{exit (ok?0:1)}
  ' /etc/pacman.conf
}

bootstrap_yay(){
  have yay && return 0
  have paru && return 0
  (( NO_AUR_BOOTSTRAP )) && die "No AUR helper found (yay/paru). Install one or re-run without --no-aur-bootstrap."

  pacman_install git base-devel

  # Build yay as the real user; install the built package as root (no sudo prompt inside makepkg).
  local tmp pkg
  tmp="$(mktemp -d)"
  as_root chmod 0777 "$tmp" || true

  as_user bash -lc "cd '$tmp' && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -s --noconfirm --needed"
  pkg="$(find "$tmp/yay" -maxdepth 1 -type f -name 'yay-*.pkg.tar*' ! -name '*-debug*' | head -n1 || true)"
  [[ -n "$pkg" ]] || die "Failed to build yay package."
  as_root pacman -U --noconfirm "$pkg"

  rm -rf "$tmp"
  have yay || die "Failed to install yay."
}

aur_install(){
  local helper=""
  if have paru; then helper="paru"; fi
  if have yay; then helper="yay"; fi
  if [[ -z "$helper" ]]; then
    bootstrap_yay
    helper="yay"
  fi

  # yay/paru must run as user
  if [[ "$helper" == "paru" ]]; then
    as_user paru -S --needed --noconfirm "$@"
  else
    as_user yay -S --needed --noconfirm "$@"
  fi
}

detect_gpu_lines(){
  have lspci || pacman_install pciutils
  lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true
}

has_vendor(){
  local lines="$1" vid="$2"
  grep -qiE "\[$vid:" <<<"$lines"
}

nvidia_classify_lines(){
  # returns: modern|preturing|mixed|unknown
  local nlines="$1"

  local modern_pat='(RTX|Quadro RTX|TITAN RTX|GTX[[:space:]]*16|A[0-9]{2,4}|H[0-9]{2,4}|L[0-9]{2,4}|T4|RTX[[:space:]]*[0-9]{3,4})'
  local pret_pat='(GTX[[:space:]]*(10|9|8|7|6|5|4)|GT[[:space:]]*[0-9]{2,4}|Quadro[[:space:]]*(P|M|K)|Tesla[[:space:]]*(P|V|M|K)|NVS|ION)'

  local any_modern=0 any_pret=0
  if grep -qiE "$modern_pat" <<<"$nlines"; then any_modern=1; fi
  if grep -qiE "$pret_pat" <<<"$nlines"; then any_pret=1; fi

  if (( any_modern && any_pret )); then printf '%s\n' "mixed"; return 0; fi
  if (( any_modern )); then printf '%s\n' "modern"; return 0; fi
  if (( any_pret )); then printf '%s\n' "preturing"; return 0; fi
  printf '%s\n' "unknown"
}

detect_kernel_pkgs(){
  local all k
  all="$(pacman -Qq 2>/dev/null || true)"
  local out=()

  for k in linux linux-lts linux-zen linux-hardened linux-cachyos; do
    grep -qx "$k" <<<"$all" && out+=("$k")
  done

  while IFS= read -r k; do
    [[ "$k" == *-headers ]] && continue
    [[ "$k" == linux-firmware ]] && continue
    [[ "$k" =~ ^linux(-|$) ]] || continue
    local seen=0 x
    for x in "${out[@]}"; do [[ "$x" == "$k" ]] && seen=1; done
    (( seen )) || out+=("$k")
  done < <(grep -E '^linux([-.].+)?$' <<<"$all" || true)

  printf '%s\n' "${out[@]}"
}

headers_for_kernel(){
  local k="$1"
  case "$k" in
    linux) printf '%s\n' linux-headers ;;
    linux-lts) printf '%s\n' linux-lts-headers ;;
    linux-zen) printf '%s\n' linux-zen-headers ;;
    linux-hardened) printf '%s\n' linux-hardened-headers ;;
    linux-cachyos) printf '%s\n' linux-cachyos-headers ;;
    *) printf '%s\n' "${k}-headers" ;;
  esac
}

install_headers_for_installed_kernels(){
  pacman_install dkms
  local -a kernels
  mapfile -t kernels < <(detect_kernel_pkgs || true)
  if ((${#kernels[@]} == 0)); then
    pacman_install linux-headers || true
    return 0
  fi

  local k hp
  for k in "${kernels[@]}"; do
    hp="$(headers_for_kernel "$k")"
    if pacman_si "$hp"; then
      pacman_install "$hp"
    else
      warn "Header package not found: $hp (kernel: $k)"
    fi
  done
}

set_nvidia_modeset(){
  (( SET_MODESET )) || return 0
  local f="/etc/modprobe.d/nvidia.conf"
  backup_root_file "$f"
  as_root mkdir -p /etc/modprobe.d
  as_root bash -c "printf '%s\n' 'options nvidia_drm modeset=1' > '$f'"
}

patch_hyprland_nvidia(){
  (( PATCH_HYPRLAND )) || return 0
  # If we don't know the real user, skip safely.
  [[ -n "${USER_HOME:-}" ]] || return 0

  local conf="${USER_HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  # backup as root or user depending on perms; simplest: copy with cp -a via root
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    as_root cp -a "$conf" "${conf}.bak.$(ts)"
  else
    cp -a "$conf" "${conf}.bak.$(ts)"
  fi

  grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf" || \
    printf '%s\n' 'env = LIBVA_DRIVER_NAME,nvidia' >> "$conf"
  grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*__GLX_VENDOR_LIBRARY_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf" || \
    printf '%s\n' 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia' >> "$conf"
  grep -qE '^[[:space:]]*cursor:no_hardware_cursors[[:space:]]*=' "$conf" || \
    printf '%s\n' 'cursor:no_hardware_cursors = true' >> "$conf"
}

verify_nvidia(){
  if ! have modprobe; then pacman_install kmod; fi
  as_root modprobe -q nvidia || return 1
  as_root modprobe -q nvidia_drm || true
  have nvidia-smi || return 1
  nvidia-smi -L >/dev/null 2>&1 || return 1
  return 0
}

remove_repo_nvidia_stacks(){
  pacman_remove \
    nvidia nvidia-dkms nvidia-lts \
    nvidia-open nvidia-open-dkms nvidia-lts-open \
    nvidia-utils lib32-nvidia-utils nvidia-settings \
    opencl-nvidia lib32-opencl-nvidia \
    egl-wayland
}

install_common_graphics_base(){
  pacman_install mesa libglvnd vulkan-icd-loader
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-mesa lib32-libglvnd lib32-vulkan-icd-loader
  fi
}

install_amd(){
  pacman_install vulkan-radeon
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-vulkan-radeon
  fi
}

install_intel(){
  pacman_install vulkan-intel
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-vulkan-intel
  fi
}

install_nvidia_open_stack(){
  install_headers_for_installed_kernels
  pacman_install egl-wayland nvidia-utils nvidia-settings
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-nvidia-utils
  fi
  if (( INSTALL_OPENCL )); then
    pacman_install opencl-nvidia || true
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      pacman_install lib32-opencl-nvidia || true
    fi
  fi

  # Arch (post-590) uses nvidia-open*; older systems may still have nvidia-dkms/nvidia.
  if pacman_si nvidia-open-dkms; then
    pacman_install nvidia-open-dkms
  elif pacman_si nvidia-dkms; then
    pacman_install nvidia-dkms
  elif pacman_si nvidia; then
    pacman_install nvidia
  else
    die "No NVIDIA repo driver package found (nvidia-open-dkms / nvidia-dkms / nvidia)."
  fi

  set_nvidia_modeset
  as_root mkinitcpio -P
  patch_hyprland_nvidia
}

install_nvidia_legacy_branch(){
  local branch="$1" # 580xx|470xx|390xx|340xx
  install_headers_for_installed_kernels
  pacman_install egl-wayland git base-devel

  local pkgs=(
    "nvidia-${branch}-dkms"
    "nvidia-${branch}-utils"
    "nvidia-${branch}-settings"
  )

  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pkgs+=("lib32-nvidia-${branch}-utils")
  fi

  if (( INSTALL_OPENCL )); then
    pkgs+=("opencl-nvidia-${branch}" "lib32-opencl-nvidia-${branch}")
  fi

  aur_install "${pkgs[@]}"

  set_nvidia_modeset
  as_root mkinitcpio -P
  patch_hyprland_nvidia
}

install_nvidia_best_effort(){
  local nlines="$1"
  local mode="$2"

  if [[ "$mode" == "mixed" ]]; then
    warn "Mixed NVIDIA generations detected. Skipping NVIDIA changes."
    return 0
  fi

  if [[ -n "$FORCE_NVIDIA_MODE" ]]; then
    case "$FORCE_NVIDIA_MODE" in
      open) mode="modern" ;;
      legacy) mode="preturing" ;;
      skip) warn "Forced NVIDIA skip"; return 0 ;;
      *) warn "Unknown --force-nvidia value: $FORCE_NVIDIA_MODE (ignoring)" ;;
    esac
  fi

  local -a candidates=()
  case "$mode" in
    modern) candidates=(open) ;;
    preturing) candidates=(580xx 470xx 390xx 340xx) ;;
    unknown) candidates=(open 580xx 470xx 390xx 340xx) ;;
    *) candidates=(open 580xx 470xx 390xx 340xx) ;;
  esac

  log "NVIDIA candidate sequence: ${candidates[*]}"

  local c
  for c in "${candidates[@]}"; do
    log "Attempt NVIDIA install: $c"
    remove_repo_nvidia_stacks

    case "$c" in
      open)
        install_nvidia_open_stack
        ;;
      580xx|470xx|390xx|340xx)
        install_nvidia_legacy_branch "$c"
        ;;
      *)
        continue
        ;;
    esac

    if verify_nvidia; then
      log "NVIDIA install verified: $c"
      return 0
    fi

    warn "NVIDIA verify failed for '$c' (may require reboot). Trying next candidate."
  done

  warn "No NVIDIA candidate verified. Leaving system as-is (nonfatal)."
  return 0
}

main(){
  have pacman || exit 0

  if have systemd-detect-virt && systemd-detect-virt -q; then
    exit 0
  fi

  local gpu_lines
  gpu_lines="$(detect_gpu_lines)"
  [[ -n "$gpu_lines" ]] || exit 0

  local has_nvidia=0 has_amd=0 has_intel=0
  has_vendor "$gpu_lines" "10de" && has_nvidia=1
  has_vendor "$gpu_lines" "1002" && has_amd=1
  has_vendor "$gpu_lines" "8086" && has_intel=1

  log "GPU(s):"
  log "$gpu_lines"

  if (( DO_UPGRADE )); then
    as_root pacman -Syu --noconfirm
  else
    as_root pacman -Sy --noconfirm
  fi

  install_common_graphics_base

  (( has_amd )) && install_amd
  (( has_intel )) && install_intel

  if (( has_nvidia )); then
    local nlines mode
    nlines="$(grep -Ei '\[10de:' <<<"$gpu_lines" || true)"
    mode="$(nvidia_classify_lines "$nlines")"
    install_nvidia_best_effort "$nlines" "$mode"
  fi
}

main
