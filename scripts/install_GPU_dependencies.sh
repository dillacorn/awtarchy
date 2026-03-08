#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# install_GPU_dependencies.sh
# - Safe when called from a root-run install.sh (sudo)
# - Detects AMD/Intel/NVIDIA and installs correct Vulkan stack
# - NVIDIA:
#   - Uses nvidia-open* from official repos for modern GPUs (Turing+/RTX/GTX16 and newer)
#   - Uses AUR legacy branches when NVIDIA legacy page indicates (470/390/340)
#   - Uses 580xx (AUR) for Pascal/Maxwell/Volta class GPUs (per Arch 590 transition notice)
# - Removes conflicting NVIDIA packages before switching
# - Ensures modeset:
#     * modprobe:  options nvidia_drm modeset=1
#     * bootloader cmdline: nvidia-drm.modeset=1 (adds if missing)
# - Rebuilds initramfs (mkinitcpio/dracut)
# - Patches Hyprland config NVIDIA env lines (best-effort; no cursor no_hardware_cursors edits)
# - Dry-run/testing:
#     * --dry-run/--test prints a plan + every command that would run, without changing the system
#     * --nvidia/--amd/--intel forces a GPU path (useful for testing without hardware detection)

ts(){ date +%F_%H%M%S; }
log(){ printf '%s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

DO_UPGRADE=0
INSTALL_LIB32=1
INSTALL_OPENCL=0
PATCH_BOOTLOADERS=0
WRITE_MODPROBE_MODESET=1
WRITE_BLACKLIST_NOUVEAU=1
PATCH_MKINITCPIO_MODULES=0

DRY_RUN=0
FORCE_GPU=""
NVIDIA_TOUCHED=0

KPARAM_A="nvidia-drm.modeset=1"
KPARAM_B="nvidia_drm.modeset=1" # accepted if user already has it, but we add hyphen form

usage(){
  cat >&2 <<'EOF'
Usage: install_GPU_dependencies.sh [options]
  --upgrade                  pacman -Syu (default: off)
  --no-lib32                 skip lib32 packages
  --opencl                   attempt OpenCL packages
  --dry-run, --test          print plan + actions; do not install/remove/write/rebuild
  --nvidia                   force NVIDIA path (skips lspci detection + legacy branch lookup)
  --amd                      force AMD path (skips lspci detection)
  --intel                    force Intel path (skips lspci detection)
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
    --dry-run|--test) DRY_RUN=1; shift ;;
    --nvidia) FORCE_GPU="nvidia"; shift ;;
    --amd) FORCE_GPU="amd"; shift ;;
    --intel) FORCE_GPU="intel"; shift ;;
    --no-bootloader-patch) PATCH_BOOTLOADERS=0; shift ;;
    --no-modprobe-modeset) WRITE_MODPROBE_MODESET=0; shift ;;
    --no-blacklist-nouveau) WRITE_BLACKLIST_NOUVEAU=0; shift ;;
    --no-mkinitcpio-modules) PATCH_MKINITCPIO_MODULES=0; shift ;;
    *) warn "Ignoring unknown arg: $1"; shift ;;
  esac
done

print_cmd(){
  printf 'DRY-RUN: '
  printf '%q ' "$@"
  printf '\n'
}

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
  if (( DRY_RUN )); then
    print_cmd "$@"
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    have sudo || die "sudo not found"
    sudo -v
    sudo "$@"
  fi
}

as_user(){
  if (( DRY_RUN )); then
    printf 'DRY-RUN: (as_user %s) ' "${RUN_USER:-?}"
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
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

pacman_remove(){
  as_root pacman -Rns --noconfirm "$@"
}

ensure_tools(){
  pacman_install git base-devel curl pciutils
}

detect_gpu_lines(){
  if [[ -n "${FORCE_GPU:-}" ]]; then
    return 0
  fi
  if ! have lspci; then
    if (( DRY_RUN )); then
      warn "lspci not found; in dry-run, use --nvidia/--amd/--intel for deterministic testing."
      return 0
    fi
    pacman_install pciutils
  fi
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
bootstrap_yay(){
  if (( DRY_RUN )); then
    log "DRY-RUN: would bootstrap yay (AUR helper) if needed"
    return 0
  fi

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
  if (( DRY_RUN )); then
    log "DRY-RUN: would AUR install: $*"
    return 0
  fi
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

# ---------- kernel detection (Arch + Cachy variants) ----------
detect_kernel_pkgs(){
  # Prefer real installed kernel pkgbases from /usr/lib/modules (works for Cachy variants, custom kernels).
  local -a bases=()
  if [[ -d /usr/lib/modules ]]; then
    local f b
    shopt -s nullglob
    for f in /usr/lib/modules/*/pkgbase; do
      [[ -f "$f" ]] || continue
      b="$(<"$f")"
      [[ -n "$b" ]] && bases+=("$b")
    done
    shopt -u nullglob
  fi
  if ((${#bases[@]})); then
    printf '%s\n' "${bases[@]}" | sort -u
    return 0
  fi
  # Fallback: best-effort via installed package names
  pacman -Qq 2>/dev/null | grep -E '^linux($|-lts$|-zen$|-hardened$|-cachyos($|-.*$))' | sort -u || true
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
  local want_dkms="${1:-1}"
  (( want_dkms )) && pacman_install dkms

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

try_install_linux_firmware_nvidia(){
  # Only installs if the package exists in enabled repos (safe on vanilla Arch).
  if pacman -Si linux-firmware-nvidia >/dev/null 2>&1; then
    pacman_install linux-firmware-nvidia || true
  fi
}

kernel_pkgbases_counts(){
  # prints: "<cachy_count> <other_count>"
  local cc=0 oc=0 k
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    if [[ "$k" == linux-cachyos* ]]; then
      ((cc++))
    else
      ((oc++))
    fi
  done < <(detect_kernel_pkgs)
  printf '%s %s\n' "$cc" "$oc"
}


nvidia_should_defer_boot_integration(){
  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)
  (( cc == 0 && oc > 0 ))
}

cachyos_prebuilt_nvidia_open_pkgs(){
  # If Cachy repos are enabled and per-kernel packages exist for every installed Cachy kernel,
  # return the list. Otherwise return non-zero to trigger DKMS fallback.
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs | awk '/^linux-cachyos/ {print}')
  ((${#kernels[@]})) || return 1

  local -a pkgs=()
  local k p
  for k in "${kernels[@]}"; do
    p="${k}-nvidia-open"
    pacman -Si "$p" >/dev/null 2>&1 || return 1
    pkgs+=("$p")
  done
  printf '%s\n' "${pkgs[@]}"
}

# ---------- NVIDIA conflict removal ----------
nvidia_conflict_regex(){
  # Used for both listing and removal.
  printf '%s' '^(nvidia|nvidia-lts|nvidia-dkms|nvidia-open|nvidia-open-lts|nvidia-open-dkms|nvidia-lts-open|nvidia-utils|lib32-nvidia-utils|nvidia-settings|egl-wayland|opencl-nvidia|lib32-opencl-nvidia|libva-nvidia-driver|linux-cachyos[^[:space:]]*-nvidia-open|linux-cachyos[^[:space:]]*-nvidia|nvidia-[0-9]{3}xx.*|lib32-nvidia-[0-9]{3}xx.*|opencl-nvidia-[0-9]{3}xx.*|lib32-opencl-nvidia-[0-9]{3}xx.*)$'
}

list_installed_nvidia_packages(){
  local re
  re="$(nvidia_conflict_regex)"
  pacman -Qq 2>/dev/null | grep -E "$re" | sort -u || true
}

remove_all_nvidia_packages(){
  local -a pkgs=()
  mapfile -t pkgs < <(list_installed_nvidia_packages)
  ((${#pkgs[@]})) || return 0
  pacman_remove "${pkgs[@]}"
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
  if (( DRY_RUN )); then
    log "DRY-RUN: would rebuild initramfs (mkinitcpio/dracut)"
    return 0
  fi
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

# Uncomment/enable a specific Hyprland env line if present commented, otherwise append it.
ensure_hypr_env_active(){
  local conf key val tmp
  conf="$1"
  key="$2"
  val="$3"

  if grep -qE "^[[:space:]]*env[[:space:]]*=[[:space:]]*${key}[[:space:]]*,[[:space:]]*${val}([[:space:]]*#.*)?[[:space:]]*$" "$conf"; then
    return 0
  fi

  if grep -qE "^[[:space:]]*#[[:space:]]*env[[:space:]]*=[[:space:]]*${key}[[:space:]]*,[[:space:]]*${val}([[:space:]]*#.*)?[[:space:]]*$" "$conf"; then
    tmp="$(mktemp)"
    awk -v key="$key" -v val="$val" '
      BEGIN { done=0 }
      {
        if (!done && $0 ~ "^[[:space:]]*#[[:space:]]*env[[:space:]]*=[[:space:]]*" key "[[:space:]]*,[[:space:]]*" val "([[:space:]]*#.*)?[[:space:]]*$") {
          sub(/^[[:space:]]*#[[:space:]]*/, "", $0)
          done=1
        }
        print
      }
    ' "$conf" >"$tmp"
    cat "$tmp" >"$conf"
    rm -f "$tmp"
    return 0
  fi

  printf '%s\n' "env = ${key},${val}" >>"$conf"
}

patch_hyprland_env_nvidia(){
  local conf
  conf="${USER_HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  if (( DRY_RUN )); then
    log "DRY-RUN: would patch Hyprland NVIDIA env lines in: $conf"
    return 0
  fi

  cp -a "$conf" "${conf}.bak.$(ts)"
  ensure_hypr_env_active "$conf" "__GLX_VENDOR_LIBRARY_NAME" "nvidia"
  ensure_hypr_env_active "$conf" "LIBVA_DRIVER_NAME" "nvidia"
  ensure_hypr_env_active "$conf" "GBM_BACKEND" "nvidia-drm"
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
  local s
  s="$1"
  grep -qiE '(RTX|Quadro RTX|TITAN RTX|GTX[[:space:]]*16|RTX[[:space:]]*[0-9]{3,4}|A[0-9]{2,4}|H[0-9]{2,4}|L[0-9]{2,4})' <<<"$s"
}

is_preturing_nvidia(){
  local s
  s="$1"
  grep -qiE '(GTX[[:space:]]*(10|9|8|7)|Quadro[[:space:]]*(P|M|K)|Tesla[[:space:]]*(P|V|M|K)|NVS|ION)' <<<"$s"
}

select_open_pkg(){
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)
  ((${#kernels[@]})) || die "Unable to detect installed kernels."

  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)

  # Mixed Cachy + non-Cachy kernels: avoid module-provider conflicts; prefer DKMS.
  if (( cc>0 && oc>0 )); then
    pacman -Si nvidia-open-dkms >/dev/null 2>&1 || die "Mixed Cachy/non-Cachy kernels detected but nvidia-open-dkms not available."
    printf '%s\n' "nvidia-open-dkms"
    return 0
  fi

  # Multiple kernels installed: prefer DKMS so one module provider covers all.
  if ((${#kernels[@]} != 1)); then
    pacman -Si nvidia-open-dkms >/dev/null 2>&1 || die "Multiple kernels installed but nvidia-open-dkms not available."
    printf '%s\n' "nvidia-open-dkms"
    return 0
  fi

  # No Cachy kernel installed yet: prefer DKMS so adding Cachy later does not
  # leave early NVIDIA module expectations tied to a single non-Cachy kernel.
  if (( cc == 0 )); then
    if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
      printf '%s\n' "nvidia-open-dkms"
      return 0
    fi
  fi

  case "${kernels[0]}" in
    linux)
      if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
      ;;
    linux-lts)
      if pacman -Si nvidia-open-lts >/dev/null 2>&1; then printf '%s\n' "nvidia-open-lts"; return 0; fi
      if pacman -Si nvidia-lts-open >/dev/null 2>&1; then printf '%s\n' "nvidia-lts-open"; return 0; fi
      ;;
    *)
      if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then printf '%s\n' "nvidia-open-dkms"; return 0; fi
      ;;
  esac

  if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then printf '%s\n' "nvidia-open-dkms"; return 0; fi
  if pacman -Si nvidia-open >/dev/null 2>&1; then printf '%s\n' "nvidia-open"; return 0; fi
  die "No nvidia-open packages found in enabled repos."
}

nvidia_open_install_plan(){
  # Prints a human plan to stdout:
  #   STRATEGY=<...>
  #   INSTALL=<pkg...>
  #   NEED_HEADERS=<0|1>
  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)

  if (( cc>0 && oc==0 )); then
    local -a prebuilt=()
    if mapfile -t prebuilt < <(cachyos_prebuilt_nvidia_open_pkgs 2>/dev/null); then
      if ((${#prebuilt[@]})); then
        printf 'STRATEGY=cachy-prebuilt\n'
        printf 'NEED_HEADERS=0\n'
        printf 'INSTALL=%s\n' "${prebuilt[*]}"
        return 0
      fi
    fi
    printf 'STRATEGY=cachy-dkms-fallback\n'
  fi

  local modpkg
  modpkg="$(select_open_pkg)"
  printf 'STRATEGY=arch-open\n'
  printf 'NEED_HEADERS=%s\n' "$([[ "$modpkg" == *-dkms ]] && echo 1 || echo 0)"
  printf 'INSTALL=%s\n' "$modpkg"
}

install_nvidia_open_stack(){
  local plan strategy need_headers install_line
  plan="$(nvidia_open_install_plan)"
  strategy="$(awk -F= '$1=="STRATEGY"{print $2}' <<<"$plan")"
  need_headers="$(awk -F= '$1=="NEED_HEADERS"{print $2}' <<<"$plan")"
  install_line="$(awk -F= '$1=="INSTALL"{print $2}' <<<"$plan")"

  log "NVIDIA open strategy: $strategy"

  if [[ "$strategy" == "cachy-prebuilt" ]]; then
    local -a prebuilt=()
    # shellcheck disable=SC2206
    prebuilt=($install_line)
    pacman_install "${prebuilt[@]}" nvidia-utils nvidia-settings egl-wayland
    try_install_linux_firmware_nvidia
  else
    local modpkg
    modpkg="$install_line"
    install_headers_for_installed_kernels "$need_headers"
    pacman_install "$modpkg" nvidia-utils nvidia-settings egl-wayland
    try_install_linux_firmware_nvidia
  fi

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
  install_headers_for_installed_kernels 1
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
  local branch
  branch="$1"
  install_headers_for_installed_kernels 1
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

verify_nvidia_module_for_running_kernel(){
  local kver pb
  kver="$(uname -r)"
  pb=""
  [[ -f "/usr/lib/modules/${kver}/pkgbase" ]] && pb="$(<"/usr/lib/modules/${kver}/pkgbase")"

  if have modinfo; then
    if ! modinfo -k "$kver" nvidia >/dev/null 2>&1; then
      if [[ -n "$pb" ]]; then
        warn "nvidia kernel module not found for running kernel: $kver (pkgbase: $pb)"
      else
        warn "nvidia kernel module not found for running kernel: $kver"
      fi
      return 1
    fi
  fi
  return 0
}

configure_nvidia_boot_integration(){
  if nvidia_should_defer_boot_integration; then
    warn "No Cachy kernel detected yet. Deferring NVIDIA bootloader/mkinitcpio/initramfs changes so a later-installed Cachy kernel can generate its initramfs cleanly."
    return 0
  fi

  patch_bootloaders
  patch_mkinitcpio_modules
  rebuild_initramfs
}

configure_nvidia(){
  write_blacklist_nouveau
  write_modprobe_modeset
  configure_nvidia_boot_integration
  patch_hyprland_env_nvidia

  if (( DRY_RUN )); then
    log "DRY-RUN: would verify nvidia-smi + running-kernel module presence"
    return 0
  fi

  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi not present after install (nvidia-utils or legacy utils missing)."
  verify_nvidia_module_for_running_kernel || true
}

nvidia_plan_report(){
  log "---- DRY-RUN PLAN (NVIDIA) ----"
  local -a kernels=()
  mapfile -t kernels < <(detect_kernel_pkgs)
  if ((${#kernels[@]})); then
    log "Installed kernel pkgbases: ${kernels[*]}"
  else
    log "Installed kernel pkgbases: (none detected)"
  fi

  local cc oc
  read -r cc oc < <(kernel_pkgbases_counts)
  log "Kernel mix: cachy=${cc} other=${oc}"

  local -a installed=()
  mapfile -t installed < <(list_installed_nvidia_packages)
  if ((${#installed[@]})); then
    log "Installed NVIDIA-related packages that would be removed:"
    printf '  %s\n' "${installed[@]}"
  else
    log "Installed NVIDIA-related packages that would be removed: (none)"
  fi

  local plan strategy need_headers install_line
  plan="$(nvidia_open_install_plan)"
  strategy="$(awk -F= '$1=="STRATEGY"{print $2}' <<<"$plan")"
  need_headers="$(awk -F= '$1=="NEED_HEADERS"{print $2}' <<<"$plan")"
  install_line="$(awk -F= '$1=="INSTALL"{print $2}' <<<"$plan")"

  log "Selected NVIDIA module strategy: $strategy"
  if [[ "$strategy" == "cachy-prebuilt" ]]; then
    log "Would install prebuilt per-kernel module packages: $install_line"
  else
    log "Would install module package: $install_line"
    log "Would install kernel headers + dkms: $need_headers"
  fi

  log "Would install userspace: nvidia-utils nvidia-settings egl-wayland"
  if (( INSTALL_LIB32 )) && multilib_enabled; then
    log "Would install 32-bit userspace: lib32-nvidia-utils"
  fi
  if (( INSTALL_OPENCL )); then
    log "Would install OpenCL: opencl-nvidia (and lib32-opencl-nvidia if multilib enabled)"
  fi

  if pacman -Si linux-firmware-nvidia >/dev/null 2>&1; then
    log "Would install firmware: linux-firmware-nvidia"
  fi

  log "Would write nouveau blacklist: $WRITE_BLACKLIST_NOUVEAU"
  log "Would write nvidia_drm modeset modprobe: $WRITE_MODPROBE_MODESET"
  if nvidia_should_defer_boot_integration; then
    log "Would defer bootloader/mkinitcpio/initramfs changes until a Cachy kernel is installed"
  else
    log "Would patch bootloader cmdline: $PATCH_BOOTLOADERS (adds: $KPARAM_A)"
    log "Would patch mkinitcpio MODULES: $PATCH_MKINITCPIO_MODULES (adds early nvidia modules)"
    log "Would rebuild initramfs: yes (mkinitcpio/dracut if present)"
  fi
  log "Would patch Hyprland NVIDIA env lines: yes (if hyprland.conf exists)"
  log "---- END PLAN ----"
}

# NVIDIA auto path (with legacy lookup)
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

  if (( DRY_RUN )); then
    # Dry-run should not curl/download the legacy page; print the decision tree + open strategy plan.
    local class="unknown"
    if is_modern_nvidia "$models"; then
      class="modern (Turing+/RTX/GTX16+)"
    elif is_preturing_nvidia "$models"; then
      class="older (Pascal/Maxwell/Volta-style naming)"
    fi

    log "DRY-RUN: NVIDIA classification (from model string): $class"
    log "DRY-RUN: would check NVIDIA legacy GPU list for PCI IDs to select 470/390/340 if applicable"
    log "DRY-RUN: if not legacy-branch, then:"
    log "  - modern -> install nvidia-open* (Arch/Cachy strategy below)"
    log "  - older  -> install nvidia-580xx-dkms stack from AUR"
    nvidia_plan_report
    return 0
  fi

  remove_all_nvidia_packages

  local tmp branch=""
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
    log "NVIDIA modern path: nvidia-open*"
    install_nvidia_open_stack
    configure_nvidia
    return 0
  fi

  if is_preturing_nvidia "$models"; then
    log "NVIDIA older path: 580xx (AUR)"
    install_nvidia_580xx_stack
    configure_nvidia
    return 0
  fi

  log "NVIDIA unknown model naming: trying nvidia-open* first"
  install_nvidia_open_stack
  configure_nvidia
}

# ---------- base plan output ----------
dry_run_banner(){
  log "DRY-RUN: enabled. No changes will be made."
  log "Options: upgrade=$DO_UPGRADE lib32=$INSTALL_LIB32 opencl=$INSTALL_OPENCL bootloader_patch=$PATCH_BOOTLOADERS modprobe_modeset=$WRITE_MODPROBE_MODESET blacklist_nouveau=$WRITE_BLACKLIST_NOUVEAU mkinitcpio_modules=$PATCH_MKINITCPIO_MODULES"
  if [[ -n "${FORCE_GPU:-}" ]]; then
    log "Forced GPU path: $FORCE_GPU"
  fi
}

main(){
  if have systemd-detect-virt && systemd-detect-virt -q; then
    log "VM detected; skipping GPU driver automation."
    exit 0
  fi

  have pacman || exit 0

  if (( DRY_RUN )); then
    dry_run_banner
  fi

  if (( DO_UPGRADE )); then
    as_root pacman -Syu --noconfirm
  else
    as_root pacman -Sy --noconfirm
  fi

  install_common_base

  if [[ -n "${FORCE_GPU:-}" ]]; then
    case "$FORCE_GPU" in
      nvidia)
        NVIDIA_TOUCHED=1
        if (( DRY_RUN )); then
          nvidia_plan_report
        fi
        remove_all_nvidia_packages
        install_nvidia_open_stack
        configure_nvidia
        ;;
      amd)
        install_amd
        ;;
      intel)
        install_intel
        ;;
      *)
        die "Unknown --gpu override: $FORCE_GPU"
        ;;
    esac

    if (( NVIDIA_TOUCHED )); then
      log "GPU install complete. Reboot recommended after NVIDIA changes."
    else
      log "GPU install complete."
    fi
    exit 0
  fi

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
  if [[ -n "$nvidia_ids" ]]; then
    NVIDIA_TOUCHED=1
    install_nvidia_auto "$lines"
  fi

  if (( NVIDIA_TOUCHED )); then
    log "GPU install complete. Reboot recommended after NVIDIA changes."
  else
    log "GPU install complete."
  fi
}

main
