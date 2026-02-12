#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# install_GPU_dependencies.sh
# - Safe when called from a root-run install.sh (sudo)
# - Detects AMD/Intel/NVIDIA and installs correct Vulkan stack
# - NVIDIA:
#   - Uses nvidia-open* from official repos for modern GPUs (RTX/GTX16/Turing+)
#   - Uses AUR legacy branches when NVIDIA legacy page indicates (470/390/340)
#   - Uses 580xx (AUR) for pre-Turing-but-not-legacy-page GPUs (Pascal/Maxwell/Volta)
# - Removes conflicting NVIDIA packages before switching
# - Ensures modeset:
#     * modprobe:  options nvidia_drm modeset=1
#     * bootloader cmdline: nvidia-drm.modeset=1 (adds if missing)
# - Rebuilds initramfs (mkinitcpio/dracut)
# - Patches Hyprland config env for NVIDIA (best-effort)

ts(){ date +%F_%H%M%S; }
log(){ printf '%s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

DO_UPGRADE=0
INSTALL_LIB32=1
INSTALL_OPENCL=0
PATCH_BOOTLOADERS=1
WRITE_MODPROBE_MODESET=1
WRITE_BLACKLIST_NOUVEAU=1
PATCH_MKINITCPIO_MODULES=1

KPARAM_A="nvidia-drm.modeset=1"
KPARAM_B="nvidia_drm.modeset=1" # accepted if user already has it, but we add hyphen form

usage(){
  cat >&2 <<'EOF'
Usage: install_GPU_dependencies.sh [options]
  --upgrade                 pacman -Syu (default: off)
  --no-lib32                skip lib32 packages
  --opencl                  attempt OpenCL packages
  --no-bootloader-patch      do not patch systemd-boot/grub/limine cmdline
  --no-modprobe-modeset      do not write /etc/modprobe.d/nvidia-drm.conf
  --no-blacklist-nouveau     do not write /etc/modprobe.d/blacklist-nouveau.conf
  --no-mkinitcpio-modules    do not edit mkinitcpio MODULES for early NVIDIA modules
EOF
}

while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --no-lib32) INSTALL_LIB32=0; shift ;;
    --opencl) INSTALL_OPENCL=1; shift ;;
    --no-bootloader-patch) PATCH_BOOTLOADERS=0; shift ;;
    --no-modprobe-modeset) WRITE_MODPROBE_MODESET=0; shift ;;
    --no-blacklist-nouveau) WRITE_BLACKLIST_NOUVEAU=0; shift ;;
    --no-mkinitcpio-modules) PATCH_MKINITCPIO_MODULES=0; shift ;;
    *) warn "Ignoring unknown arg: $1"; shift ;;
  esac
done

# ---------- privilege + user context ----------
EUID_NOW="${EUID:-$(id -u)}"
RUN_USER=""
USER_HOME=""

pick_run_user_from_getent(){
  # first real user (uid>=1000) that isn't nologin/false
  getent passwd | awk -F: '
    $3>=1000 && $1!="nobody" && $7!~/(nologin|false)$/ {print $1; exit}
  '
}

if [[ "$EUID_NOW" -eq 0 ]]; then
  RUN_USER="${SUDO_USER:-}"
  if [[ -z "$RUN_USER" || "$RUN_USER" == "root" ]]; then
    RUN_USER="$(pick_run_user_from_getent || true)"
  fi
else
  RUN_USER="${USER:-}"
fi

[[ -n "$RUN_USER" ]] || die "Unable to determine RUN_USER (non-root user) for AUR builds."

USER_HOME="$(getent passwd "$RUN_USER" | awk -F: '{print $6}')"
[[ -n "$USER_HOME" ]] || die "Unable to determine HOME for user: $RUN_USER"

as_root(){
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    have sudo || die "sudo not found"
    sudo -v
    sudo "$@"
  fi
}

as_user(){
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    have sudo || die "sudo not found (needed to run as $RUN_USER)"
    sudo -u "$RUN_USER" -H env HOME="$USER_HOME" USER="$RUN_USER" LOGNAME="$RUN_USER" "$@"
  else
    "$@"
  fi
}

backup_root_file(){
  local f
  f="$1"
  [[ -f "$f" ]] || return 0
  as_root cp -a "$f" "${f}.bak.$(ts)"
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

pacman_install(){
  as_root pacman -S --needed --noconfirm "$@"
}

ensure_tools(){
  pacman_install git base-devel curl pciutils
}

detect_gpu_lines(){
  have lspci || pacman_install pciutils
  lspci -nn | grep -Ei 'VGA compatible controller|3D controller|Display controller|2D controller' || true
}

extract_pci_ids_for_vendor(){
  local lines vid
  lines="$1"
  vid="$2"
  grep -Eio "\[$vid:[0-9a-fA-F]{4}\]" <<<"$lines" \
    | tr -d '[]' \
    | awk -F: '{print toupper($2)}' \
    | sort -u
}

# ---------- AUR helper bootstrap ----------
have_aur_helper(){
  have yay || have paru
}

bootstrap_yay(){
  have yay && return 0
  have paru && return 0

  ensure_tools

  local tmp
  tmp="$(mktemp -d)"
  as_root chown -R "$RUN_USER:$RUN_USER" "$tmp"

  as_user bash -lc "cd '$tmp' && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -s --noconfirm --needed"

  local pkg
  pkg="$(find "$tmp/yay" -maxdepth 1 -type f -name '*.pkg.tar*' ! -name '*-debug*' | head -n1 || true)"
  [[ -n "$pkg" ]] || die "Failed to build yay from AUR."

  as_root pacman -U --noconfirm --needed "$pkg"
  have yay || die "yay bootstrap failed."
  rm -rf "$tmp"
}

aur_install(){
  if have paru; then
    as_user paru -S --needed --noconfirm "$@"
    return 0
  fi
  if have yay; then
    as_user yay -S --needed --noconfirm "$@"
    return 0
  fi
  bootstrap_yay
  as_user yay -S --needed --noconfirm "$@"
}

# ---------- kernel headers for dkms ----------
detect_kernel_pkgs(){
  pacman -Qq 2>/dev/null | grep -E '^linux($|-lts$|-zen$|-hardened$|-cachyos$)' | sort -u || true
}

headers_for_kernel(){
  local k
  k="$1"
  case "$k" in
    linux) echo linux-headers ;;
    linux-lts) echo linux-lts-headers ;;
    linux-zen) echo linux-zen-headers ;;
    linux-hardened) echo linux-hardened-headers ;;
    linux-cachyos) echo linux-cachyos-headers ;;
    *) echo "${k}-headers" ;;
  esac
}

install_headers_for_installed_kernels(){
  pacman_install dkms
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)

  if ((${#kernels[@]}==0)); then
    pacman_install linux-headers || true
    return 0
  fi

  local k hp
  for k in "${kernels[@]}"; do
    hp="$(headers_for_kernel "$k")"
    if pacman -Si "$hp" >/dev/null 2>&1; then
      pacman_install "$hp"
    else
      warn "Headers pkg not found: $hp (kernel: $k)"
    fi
  done
}

# ---------- NVIDIA conflict removal ----------
remove_all_nvidia_packages(){
  local -a pkgs=()
  mapfile -t pkgs < <(
    pacman -Qq 2>/dev/null | grep -E \
      '^(nvidia|nvidia-open|nvidia-dkms|nvidia-open-dkms|nvidia-lts|nvidia-lts-open|nvidia-utils|lib32-nvidia-utils|nvidia-settings|egl-wayland|opencl-nvidia|lib32-opencl-nvidia|libva-nvidia-driver|nvidia-[0-9]{3}xx.*|lib32-nvidia-[0-9]{3}xx.*|opencl-nvidia-[0-9]{3}xx.*|lib32-opencl-nvidia-[0-9]{3}xx.*)$' \
      || true
  )
  ((${#pkgs[@]})) || return 0
  as_root pacman -Rns --noconfirm "${pkgs[@]}"
}

# ---------- modeset configuration ----------
write_blacklist_nouveau(){
  (( WRITE_BLACKLIST_NOUVEAU )) || return 0
  local f
  f="/etc/modprobe.d/blacklist-nouveau.conf"
  backup_root_file "$f"
  as_root install -d -m 0755 /etc/modprobe.d
  as_root bash -lc "cat > '$f' <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF"
}

write_modprobe_modeset(){
  (( WRITE_MODPROBE_MODESET )) || return 0
  local f
  f="/etc/modprobe.d/nvidia-drm.conf"
  backup_root_file "$f"
  as_root install -d -m 0755 /etc/modprobe.d
  as_root bash -lc "printf '%s\n' 'options nvidia_drm modeset=1' > '$f'"
}

patch_systemd_boot_entries(){
  local dir
  dir="/boot/loader/entries"
  [[ -d "$dir" ]] || return 0

  local e tmp
  shopt -s nullglob
  for e in "$dir"/*.conf; do
    backup_root_file "$e"
    tmp="$(mktemp)"
    awk -v kpA="$KPARAM_A" -v kpB="$KPARAM_B" '
      /^[[:space:]]*options[[:space:]]+/ {
        if (index($0,kpA) || index($0,kpB)) { print; next }
        print $0 " " kpA
        next
      }
      { print }
    ' "$e" >"$tmp"
    as_root install -m 0644 "$tmp" "$e"
    rm -f "$tmp"
  done
  shopt -u nullglob
}

patch_grub_default(){
  local f
  f="/etc/default/grub"
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" == GRUB_CMDLINE_LINUX_DEFAULT=* ]]; then
      local v q
      v="${line#*=}"
      q=""
      if [[ "${v:0:1}" == "\"" && "${v: -1}" == "\"" ]]; then
        q="\""
        v="${v:1:${#v}-2}"
      elif [[ "${v:0:1}" == "'" && "${v: -1}" == "'" ]]; then
        q="'"
        v="${v:1:${#v}-2}"
      fi

      if [[ "$v" == *"$KPARAM_A"* || "$v" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        v="${v% }"
        v="$v $KPARAM_A"
        printf 'GRUB_CMDLINE_LINUX_DEFAULT=%s%s%s\n' "$q" "$v" "$q" >>"$tmp"
      fi
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"

  if have grub-mkconfig; then
    if [[ -f /boot/grub/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub/grub.cfg || true
    elif [[ -f /boot/grub2/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub2/grub.cfg || true
    fi
  fi
}

patch_limine(){
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
    [[ -f "$c" ]] || continue
    f="$c"
    break
  done
  [[ -n "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*cmdline:[[:space:]]* ]]; then
      if [[ "$line" == *"$KPARAM_A"* || "$line" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s %s\n' "$line" "$KPARAM_A" >>"$tmp"
      fi
    elif [[ "$line" =~ ^[[:space:]]*(CMDLINE|KERNEL_CMDLINE)[[:space:]]*= ]]; then
      if [[ "$line" == *"$KPARAM_A"* || "$line" == *"$KPARAM_B"* ]]; then
        printf '%s\n' "$line" >>"$tmp"
      else
        printf '%s %s\n' "$line" "$KPARAM_A" >>"$tmp"
      fi
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

patch_bootloaders(){
  (( PATCH_BOOTLOADERS )) || return 0
  patch_systemd_boot_entries
  patch_grub_default
  patch_limine
}

patch_mkinitcpio_modules(){
  (( PATCH_MKINITCPIO_MODULES )) || return 0
  local f
  f="/etc/mkinitcpio.conf"
  [[ -f "$f" ]] || return 0

  backup_root_file "$f"

  local tmp line
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" == MODULES=\(*\) ]]; then
      local inside oldifs
      inside="${line#MODULES=(}"
      inside="${inside%)}"

      local -a mods=()
      oldifs="$IFS"
      IFS=' '
      read -r -a mods <<<"$inside"
      IFS="$oldifs"

      local -a need=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
      local n
      for n in "${need[@]}"; do
        if ! printf '%s\n' "${mods[@]}" | grep -qx "$n"; then
          mods+=("$n")
        fi
      done

      local joined
      IFS=' '
      joined="${mods[*]}"
      IFS="$oldifs"

      printf 'MODULES=(%s)\n' "$joined" >>"$tmp"
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$f"

  as_root install -m 0644 "$tmp" "$f"
  rm -f "$tmp"
}

rebuild_initramfs(){
  if have mkinitcpio; then
    as_root mkinitcpio -P
    return 0
  fi
  if have dracut; then
    as_root dracut --regenerate-all --force
    return 0
  fi
  warn "No mkinitcpio/dracut found; skipping initramfs rebuild."
}

patch_hyprland_env_nvidia(){
  local conf
  conf="${USER_HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  cp -a "$conf" "${conf}.bak.$(ts)"

  grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*LIBVA_DRIVER_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf" || \
    printf '%s\n' 'env = LIBVA_DRIVER_NAME,nvidia' >>"$conf"

  grep -qE '^[[:space:]]*env[[:space:]]*=[[:space:]]*__GLX_VENDOR_LIBRARY_NAME[[:space:]]*,[[:space:]]*nvidia[[:space:]]*$' "$conf" || \
    printf '%s\n' 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia' >>"$conf"

  grep -qE '^[[:space:]]*cursor:no_hardware_cursors[[:space:]]*=' "$conf" || \
    printf '%s\n' 'cursor:no_hardware_cursors = true' >>"$conf"
}

# ---------- base GPU stacks ----------
install_common_base(){
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

# ---------- NVIDIA branch detection ----------
fetch_nvidia_legacy_html(){
  local out
  out="$1"
  curl -fsSL "https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/" -o "$out"
}

legacy_branch_for_devid(){
  # returns: 470|390|340|"" based on nvidia legacy page sections
  local devid html
  devid="$1"
  html="$2"

  local needle
  needle="0x${devid}"

  awk -v IGNORECASE=1 -v needle="$needle" '
    /470\.[0-9]+/ {b="470"}
    /390\.[0-9]+/ {b="390"}
    /340\.[0-9]+/ {b="340"}
    index($0, needle) { if (b!="") {print b; exit} }
  ' "$html"
}

nvidia_model_lines(){
  local lines
  lines="$1"
  grep -Ei 'NVIDIA' <<<"$lines" || true
}

is_modern_nvidia(){
  # Turing+ / RTX / GTX16 / Quadro RTX etc
  local s
  s="$1"
  grep -qiE '(RTX|Quadro RTX|TITAN RTX|GTX[[:space:]]*16|RTX[[:space:]]*[0-9]{3,4}|A[0-9]{2,4}|H[0-9]{2,4}|L[0-9]{2,4})' <<<"$s"
}

is_preturing_nvidia(){
  # Pascal/Maxwell/Volta style naming (best-effort)
  local s
  s="$1"
  grep -qiE '(GTX[[:space:]]*(10|9|8|7)|Quadro[[:space:]]*(P|M|K)|Tesla[[:space:]]*(P|V|M|K)|NVS|ION)' <<<"$s"
}

select_open_pkg(){
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)

  if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
    if ((${#kernels[@]} != 1)); then
      printf '%s\n' "nvidia-open-dkms"
      return 0
    fi
    case "${kernels[0]}" in
      linux)
        if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
        ;;
      linux-lts)
        if pacman -Si nvidia-lts-open >/dev/null 2>&1; then printf '%s\n' "nvidia-lts-open"; return 0; fi
        ;;
    esac
    printf '%s\n' "nvidia-open-dkms"
    return 0
  fi

  if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
  if pacman -Si nvidia-lts-open >/dev/null 2>&1; then printf '%s\n' "nvidia-lts-open"; return 0; fi
  die "No nvidia-open packages found in repos."
}

install_nvidia_open_stack(){
  install_headers_for_installed_kernels
  local modpkg
  modpkg="$(select_open_pkg)"

  pacman_install "$modpkg" nvidia-utils nvidia-settings egl-wayland
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    pacman_install lib32-nvidia-utils
  fi
  if (( INSTALL_OPENCL )); then
    pacman_install opencl-nvidia || true
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      pacman_install lib32-opencl-nvidia || true
    fi
  fi
}

install_nvidia_580xx_stack(){
  install_headers_for_installed_kernels
  ensure_tools
  bootstrap_yay

  aur_install nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings
  pacman_install egl-wayland
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    aur_install lib32-nvidia-580xx-utils
  fi
  if (( INSTALL_OPENCL )); then
    aur_install opencl-nvidia-580xx || true
    if (( INSTALL_LIB32 )) && multilib_enabled; then
      aur_install lib32-opencl-nvidia-580xx || true
    fi
  fi
}

install_nvidia_legacy_branch(){
  # branch: 470|390|340
  local branch
  branch="$1"
  install_headers_for_installed_kernels
  ensure_tools
  bootstrap_yay

  case "$branch" in
    470)
      aur_install nvidia-470xx-dkms nvidia-470xx-utils nvidia-470xx-settings
      ;;
    390)
      aur_install nvidia-390xx-dkms nvidia-390xx-utils nvidia-390xx-settings
      ;;
    340)
      aur_install nvidia-340xx nvidia-340xx-utils || die "340xx is frequently broken on modern Arch; install failed."
      ;;
    *)
      die "Unknown legacy branch: $branch"
      ;;
  esac

  pacman_install egl-wayland
}

configure_nvidia(){
  write_blacklist_nouveau
  write_modprobe_modeset
  patch_bootloaders
  patch_mkinitcpio_modules
  rebuild_initramfs
  patch_hyprland_env_nvidia

  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not present after install (nvidia-utils or legacy utils missing)."
}

install_nvidia_auto(){
  local gpu_lines
  gpu_lines="$1"

  local -a ids=()
  mapfile -t ids < <(extract_pci_ids_for_vendor "$gpu_lines" "10de")
  ((${#ids[@]})) || return 0

  local models
  models="$(nvidia_model_lines "$gpu_lines")"

  log "NVIDIA detected: ${ids[*]}"
  [[ -n "$models" ]] && log "$models"

  remove_all_nvidia_packages

  local html tmp branch=""
  tmp="$(mktemp)"
  if fetch_nvidia_legacy_html "$tmp"; then
    local id b
    for id in "${ids[@]}"; do
      b="$(legacy_branch_for_devid "$id" "$tmp" || true)"
      if [[ -n "$b" ]]; then
        if [[ -z "$branch" ]]; then
          branch="$b"
        elif [[ "$branch" != "$b" ]]; then
          rm -f "$tmp"
          die "Multiple NVIDIA GPUs require different legacy branches ($branch vs $b). Refusing to guess."
        fi
      fi
    done
  fi
  rm -f "$tmp"

  if [[ -n "$branch" ]]; then
    log "NVIDIA legacy branch selected: $branch"
    install_nvidia_legacy_branch "$branch"
    configure_nvidia
    return 0
  fi

  if is_modern_nvidia "$models"; then
    log "NVIDIA modern path: nvidia-open* (repos)"
    install_nvidia_open_stack
    configure_nvidia
    return 0
  fi

  if is_preturing_nvidia "$models"; then
    log "NVIDIA pre-Turing path: 580xx (AUR)"
    install_nvidia_580xx_stack
    configure_nvidia
    return 0
  fi

  # Unknown naming: try open first, then fail loudly if nvidia-smi missing.
  log "NVIDIA unknown model naming: trying nvidia-open* first"
  install_nvidia_open_stack
  configure_nvidia
}

main(){
  if have systemd-detect-virt && systemd-detect-virt -q; then
    log "VM detected; skipping GPU driver automation."
    exit 0
  fi

  have pacman || exit 0

  if (( DO_UPGRADE )); then
    as_root pacman -Syu --noconfirm
  else
    as_root pacman -Sy --noconfirm
  fi

  install_common_base

  local lines
  lines="$(detect_gpu_lines)"
  [[ -n "$lines" ]] || exit 0

  log "GPU(s):"
  log "$lines"

  local amd_ids intel_ids nvidia_ids
  amd_ids="$(extract_pci_ids_for_vendor "$lines" "1002" || true)"
  intel_ids="$(extract_pci_ids_for_vendor "$lines" "8086" || true)"
  nvidia_ids="$(extract_pci_ids_for_vendor "$lines" "10de" || true)"

  [[ -n "$amd_ids" ]] && install_amd
  [[ -n "$intel_ids" ]] && install_intel
  [[ -n "$nvidia_ids" ]] && install_nvidia_auto "$lines"

  log "GPU install complete. Reboot recommended after NVIDIA changes."
}

main
