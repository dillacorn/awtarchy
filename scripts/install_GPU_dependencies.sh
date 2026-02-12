#!/usr/bin/env bash
set -eEuo pipefail

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
PATCH_BOOTLOADER=1
ENABLE_EARLY_KMS=1
NO_AUR=0

# ERR trap (no intermediate vars -> no SC2154)
trap '
  if (( NONFATAL )); then
    warn "GPU script failed (nonfatal): rc=$? line=$LINENO cmd=$BASH_COMMAND"
    exit 0
  fi
  die "GPU script failed: rc=$? line=$LINENO cmd=$BASH_COMMAND"
' ERR

usage(){
  cat >&2 <<'EOF'
Usage: install_GPU_dependencies.sh [options]
  --fatal              Exit non-zero on failure (default: nonfatal exit 0)
  --upgrade            Run pacman -Syu first (default: off)
  --no-lib32           Skip lib32 packages even if multilib enabled
  --opencl             Install OpenCL where available
  --no-hyprland         Don't append Hyprland Nvidia env lines
  --no-bootloader       Don't patch systemd-boot/grub/limine cmdlines
  --no-early-kms        Don't modify mkinitcpio MODULES for early KMS
  --no-aur              Don't attempt legacy AUR build/install
EOF
}

while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --fatal) NONFATAL=0; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-lib32) INSTALL_LIB32=0; shift ;;
    --opencl) INSTALL_OPENCL=1; shift ;;
    --no-hyprland) PATCH_HYPRLAND=0; shift ;;
    --no-bootloader) PATCH_BOOTLOADER=0; shift ;;
    --no-early-kms) ENABLE_EARLY_KMS=0; shift ;;
    --no-aur) NO_AUR=1; shift ;;
    --) shift; break ;;
    *) shift ;;
  esac
done

# Make ShellCheck see NONFATAL as used outside trap (avoids SC2034)
if (( NONFATAL != 0 && NONFATAL != 1 )); then
  die "Invalid NONFATAL value: $NONFATAL"
fi

RUN_USER="${SUDO_USER:-${USER:-}}"
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  [[ "${RUN_USER:-}" == "root" ]] && RUN_USER=""
fi

USER_HOME="${HOME}"
if [[ -n "${RUN_USER:-}" ]]; then
  USER_HOME="$(getent passwd "$RUN_USER" 2>/dev/null | cut -d: -f6 || true)"
  [[ -n "$USER_HOME" ]] || USER_HOME="${HOME}"
fi

as_root(){
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return $?
  fi
  have sudo || die "sudo required"
  sudo -n true 2>/dev/null || sudo -v
  sudo "$@"
}

as_user(){
  [[ -n "${RUN_USER:-}" ]] || return 1
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    if have sudo; then
      sudo -u "$RUN_USER" -H env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
      return $?
    fi
    if have runuser; then
      runuser -u "$RUN_USER" -- env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
      return $?
    fi
    return 1
  fi
  "$@"
}

backup_root_file(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  as_root cp -a "$f" "${f}.bak.$(ts)" || true
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

pacman_si(){ pacman -Si "$1" >/dev/null 2>&1; }

pacman_install(){
  as_root pacman -S --needed --noconfirm "$@"
}

detect_gpu_lines(){
  have lspci || pacman_install pciutils
  lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true
}

has_vendor(){
  local lines="$1" vid="$2"
  grep -qiE "\[$vid:" <<<"$lines"
}

detect_kernel_pkgs(){
  local all k
  local -a out=()
  all="$(pacman -Qq 2>/dev/null || true)"
  for k in linux linux-lts linux-zen linux-hardened linux-cachyos; do
    if grep -qx "$k" <<<"$all"; then
      out+=("$k")
    fi
  done
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
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs || true)

  if ((${#kernels[@]} == 0)); then
    pacman_install linux-headers || true
    return 0
  fi

  local k hp
  for k in "${kernels[@]}"; do
    hp="$(headers_for_kernel "$k")"
    if pacman_si "$hp"; then
      if ! pacman_install "$hp"; then
        warn "Failed to install headers: $hp"
      fi
    else
      warn "Missing headers package: $hp"
    fi
  done
}

set_modeset_modprobe(){
  local f="/etc/modprobe.d/nvidia.conf"
  backup_root_file "$f"
  as_root mkdir -p /etc/modprobe.d
  as_root bash -c "printf '%s\n' 'options nvidia_drm modeset=1' > '$f'"
}

append_kparam_systemd_boot(){
  local dir f tmp line
  local -a dirs=(/boot/loader/entries /efi/loader/entries /boot/efi/loader/entries /boot/EFI/loader/entries)

  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    shopt -s nullglob
    for f in "$dir"/*.conf; do
      backup_root_file "$f"
      tmp="$(mktemp)"
      while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*options[[:space:]]+ ]]; then
          if grep -q '\bnvidia_drm\.modeset=1\b' <<<"$line"; then
            printf '%s\n' "$line" >>"$tmp"
          else
            printf '%s nvidia_drm.modeset=1\n' "$line" >>"$tmp"
          fi
        else
          printf '%s\n' "$line" >>"$tmp"
        fi
      done <"$f"
      as_root install -m 0644 "$tmp" "$f"
      rm -f "$tmp"
    done
    shopt -u nullglob
  done
}

append_kparam_grub(){
  local f="/etc/default/grub" tmp line changed=0
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"
  tmp="$(mktemp)"

  while IFS= read -r line; do
    if [[ "$line" =~ ^GRUB_CMDLINE_LINUX_DEFAULT= ]]; then
      if grep -q '\bnvidia_drm\.modeset=1\b' <<<"$line"; then
        printf '%s\n' "$line" >>"$tmp"
      else
        local v
        v="${line#*=}"
        v="${v#\"}"; v="${v%\"}"
        v="${v} nvidia_drm.modeset=1"
        printf 'GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$v" >>"$tmp"
        changed=1
      fi
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"

  if (( changed )) && have grub-mkconfig; then
    if [[ -f /boot/grub/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub/grub.cfg || true
    elif [[ -f /boot/grub2/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub2/grub.cfg || true
    fi
  fi
}

append_kparam_limine(){
  local f=""
  local -a candidates=(
    "/boot/limine/limine.conf"
    "/boot/limine.conf"
    "/boot/EFI/limine/limine.conf"
    "/boot/limine/limine.cfg"
    "/boot/limine.cfg"
  )

  local c
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      f="$c"
      break
    fi
  done
  [[ -n "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*cmdline:[[:space:]]* ]]; then
      if grep -q '\bnvidia_drm\.modeset=1\b' <<<"$line"; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s nvidia_drm.modeset=1\n' "$line" >>"$tmp"
      fi
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*(CMDLINE|KERNEL_CMDLINE)[[:space:]]*= ]]; then
      if grep -q '\bnvidia_drm\.modeset=1\b' <<<"$line"; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s nvidia_drm.modeset=1\n' "$line" >>"$tmp"
      fi
      continue
    fi

    printf '%s\n' "$line" >>"$tmp"
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

ensure_kparam_and_modeset(){
  set_modeset_modprobe
  (( PATCH_BOOTLOADER )) || return 0
  append_kparam_systemd_boot
  append_kparam_grub
  append_kparam_limine
}

patch_mkinitcpio_modules_for_early_kms(){
  (( ENABLE_EARLY_KMS )) || return 0
  local intel_present="${1:-0}"
  local f="/etc/mkinitcpio.conf"
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"

  local pref=""
  if [[ "$intel_present" == "1" ]]; then
    pref="i915"
  fi

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" =~ ^MODULES=\( ]]; then
      local inside
      inside="${line#MODULES=(}"
      inside="${inside%)}"
      inside="$(sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' <<<"$inside")"

      local -a out=()
      local tok

      if [[ -n "$pref" ]]; then
        if ! grep -qw "$pref" <<<"$inside"; then
          out+=("$pref")
        fi
      fi

      for tok in $inside; do
        [[ -n "$tok" ]] && out+=("$tok")
      done

      for tok in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        if ! grep -qw "$tok" <<<"${out[*]}"; then
          out+=("$tok")
        fi
      done

      printf 'MODULES=(%s)\n' "${out[*]}" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

patch_hyprland_nvidia_env(){
  (( PATCH_HYPRLAND )) || return 0
  [[ -n "${USER_HOME:-}" ]] || return 0

  local conf="${USER_HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    as_root cp -a "$conf" "${conf}.bak.$(ts)" || true
  else
    cp -a "$conf" "${conf}.bak.$(ts)" || true
  fi

  if ! grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf"; then
    printf '%s\n' 'env = LIBVA_DRIVER_NAME,nvidia' >>"$conf"
  fi
  if ! grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*__GLX_VENDOR_LIBRARY_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf"; then
    printf '%s\n' 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia' >>"$conf"
  fi
}

is_modern_nvidia(){
  local line="$1"
  grep -qiE '(RTX|Quadro RTX|TITAN RTX|GTX[[:space:]]*16|Tesla[[:space:]]*T4|A[0-9]{2,4}|H[0-9]{2,4}|L[0-9]{2,4})' <<<"$line"
}

install_base_graphics(){
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

install_nvidia_modern_repo(){
  local intel_present="${1:-0}"
  install_headers_for_installed_kernels

  local modpkg=""
  if pacman_si nvidia-open-dkms; then
    modpkg="nvidia-open-dkms"
  elif pacman_si nvidia-open; then
    modpkg="nvidia-open"
  elif pacman_si nvidia-dkms; then
    modpkg="nvidia-dkms"
  elif pacman_si nvidia; then
    modpkg="nvidia"
  else
    die "No NVIDIA repo module package found."
  fi

  local -a pkgs=("$modpkg" nvidia-utils egl-wayland nvidia-settings)
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pkgs+=(lib32-nvidia-utils)
  fi
  if (( INSTALL_OPENCL )); then
    pkgs+=(opencl-nvidia)
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      pkgs+=(lib32-opencl-nvidia)
    fi
  fi

  pacman_install "${pkgs[@]}"
  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi missing after install (nvidia-utils did not install)."

  ensure_kparam_and_modeset
  patch_mkinitcpio_modules_for_early_kms "$intel_present"
  as_root mkinitcpio -P || true
  patch_hyprland_nvidia_env
}

aur_build_and_install_580xx(){
  local intel_present="${1:-0}"

  (( NO_AUR )) && die "Legacy NVIDIA detected but --no-aur was set."
  [[ -n "${RUN_USER:-}" ]] || die "Legacy NVIDIA detected but no non-root RUN_USER available for AUR build."

  pacman_install git base-devel dkms
  install_headers_for_installed_kernels

  local tmp repo pkgdir
  tmp="$(mktemp -d)"
  as_root chmod 0777 "$tmp" 2>/dev/null || true

  repo="$tmp/nvidia-580xx-utils"
  as_user git clone https://aur.archlinux.org/nvidia-580xx-utils.git "$repo"
  as_user bash -lc "cd '$repo' && makepkg -s --noconfirm --needed"

  pkgdir="$repo"

  local -a built=()
  mapfile -t built < <(find "$pkgdir" -maxdepth 1 -type f -name '*.pkg.tar*' ! -name '*-debug*' | sort)
  ((${#built[@]})) || die "AUR build produced no packages."

  local -a want=()
  local f base
  for f in "${built[@]}"; do
    base="$(basename "$f")"
    case "$base" in
      nvidia-580xx-dkms-*.pkg.tar*) want+=("$f") ;;
      nvidia-580xx-utils-*.pkg.tar*) want+=("$f") ;;
      nvidia-580xx-settings-*.pkg.tar*) want+=("$f") ;;
      opencl-nvidia-580xx-*.pkg.tar*) (( INSTALL_OPENCL )) && want+=("$f") ;;
      lib32-nvidia-580xx-utils-*.pkg.tar*) (( INSTALL_LIB32 )) && multilib_enabled && want+=("$f") ;;
      lib32-opencl-nvidia-580xx-*.pkg.tar*) (( INSTALL_OPENCL )) && (( INSTALL_LIB32 )) && multilib_enabled && want+=("$f") ;;
    esac
  done

  ((${#want[@]})) || die "AUR build did not produce required 580xx packages."
  as_root pacman -U --noconfirm --needed "${want[@]}"

  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi missing after 580xx install."

  ensure_kparam_and_modeset
  patch_mkinitcpio_modules_for_early_kms "$intel_present"
  as_root mkinitcpio -P || true
  patch_hyprland_nvidia_env

  rm -rf "$tmp"
}

install_nvidia(){
  local all_lines="$1"
  local intel_present="${2:-0}"

  local nlines
  nlines="$(grep -Ei '\[10de:' <<<"$all_lines" || true)"
  [[ -n "$nlines" ]] || return 0

  if is_modern_nvidia "$nlines"; then
    log "NVIDIA: modern"
    install_nvidia_modern_repo "$intel_present"
    return 0
  fi

  log "NVIDIA: legacy"
  aur_build_and_install_580xx "$intel_present"
}

main(){
  have pacman || exit 0
  have systemd-detect-virt && systemd-detect-virt -q && exit 0

  local gpu_lines
  gpu_lines="$(detect_gpu_lines)"
  [[ -n "$gpu_lines" ]] || exit 0

  log "GPU(s):"
  log "$gpu_lines"

  if (( DO_UPGRADE )); then
    as_root pacman -Syu --noconfirm
  else
    as_root pacman -Sy --noconfirm
  fi

  install_base_graphics

  local has_nvidia=0 has_amd=0 has_intel=0
  has_vendor "$gpu_lines" "10de" && has_nvidia=1
  has_vendor "$gpu_lines" "1002" && has_amd=1
  has_vendor "$gpu_lines" "8086" && has_intel=1

  (( has_amd )) && install_amd
  (( has_intel )) && install_intel
  (( has_nvidia )) && install_nvidia "$gpu_lines" "$has_intel"

  exit 0
}

main
