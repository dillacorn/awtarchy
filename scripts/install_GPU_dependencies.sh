#!/usr/bin/env bash
set -euo pipefail

ts() { date +%F_%H%M%S; }

die(){ echo "ERROR: $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

as_root(){
  sudo -n true 2>/dev/null || sudo -v
  sudo "$@"
}

backup_file(){
  local f b
  f="$1"
  [[ -f "$f" ]] || return 0
  b="${f}.bak.$(ts)"
  as_root cp -a "$f" "$b"
}

bootstrap_yay(){
  have yay && return 0
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cd "$tmp"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm --needed --syncdeps
  have yay || die "Failed to install yay."
}

ensure_dkms_headers(){
  local krel
  krel="$(uname -r || true)"
  if [[ "$krel" == *cachy* ]] || pacman -Q linux-cachyos >/dev/null 2>&1; then
    as_root pacman -S --needed --noconfirm dkms linux-cachyos-headers
  else
    as_root pacman -S --needed --noconfirm dkms linux-headers
  fi
}

patch_systemd_boot_modeset(){
  local dir e
  dir="/boot/loader/entries"
  [[ -d "$dir" ]] || return 0

  read -r -d '' perl_prog <<'PERL' || true
if (/^\s*options\s+/) {
  chomp;
  if ($_ !~ /\bnvidia_drm\.modeset=1\b/) { $_ .= " nvidia_drm.modeset=1"; }
  $_ .= "\n";
}
PERL

  shopt -s nullglob
  for e in "$dir"/*.conf; do
    backup_file "$e"
    as_root perl -i -pe "$perl_prog" "$e"
  done
}

patch_grub_modeset(){
  local f
  f="/etc/default/grub"
  [[ -f "$f" ]] || return 0

  backup_file "$f"

  read -r -d '' perl_prog <<'PERL' || true
if (/^GRUB_CMDLINE_LINUX_DEFAULT=/) {
  my ($k,$v)=split(/=/,$_,2);
  $v =~ s/^\s*"?//; $v =~ s/"?\s*$//;
  if ($v !~ /\bnvidia_drm\.modeset=1\b/) { $v .= " nvidia_drm.modeset=1"; }
  $_ = $k . "=\"" . $v . "\"\n";
}
PERL

  as_root perl -i -pe "$perl_prog" "$f"

  if have grub-mkconfig; then
    if [[ -f /boot/grub/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub/grub.cfg
    elif [[ -f /boot/grub2/grub.cfg ]]; then
      as_root grub-mkconfig -o /boot/grub2/grub.cfg
    fi
  fi
}

patch_limine_modeset(){
  local f c
  local candidates=(
    "/boot/limine/limine.conf"
    "/boot/limine.conf"
    "/boot/EFI/limine/limine.conf"
    "/boot/limine/limine.cfg"
    "/boot/limine.cfg"
  )

  f=""
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] || continue
    f="$c"
    break
  done
  [[ -n "$f" ]] || return 0

  backup_file "$f"

  read -r -d '' perl_prog <<'PERL' || true
# Remove stray standalone modeset lines (common bad edit)
s/^\s*nvidia_drm\.modeset=1\s*\n//mg;

# "cmdline: ..." syntax
if (/^\s*cmdline:\s*(.*)$/i) {
  my $rest=$1;
  $rest =~ s/\s+$//;
  if ($rest !~ /\bnvidia_drm\.modeset=1\b/) {
    $_ = "    cmdline: " . $rest . " nvidia_drm.modeset=1\n";
  }
}

# "CMDLINE=..." syntax
if (/^\s*(CMDLINE|KERNEL_CMDLINE)\s*=\s*(.*)$/i) {
  my $k=$1; my $rest=$2;
  $rest =~ s/\s+$//;
  if ($rest !~ /\bnvidia_drm\.modeset=1\b/) {
    $_ = $k . "=" . $rest . " nvidia_drm.modeset=1\n";
  }
}
PERL

  as_root perl -i -pe "$perl_prog" "$f"
}

patch_hyprland_for_nvidia(){
  local conf
  conf="${HOME}/.config/hypr/hyprland.conf"
  [[ -f "$conf" ]] || return 0

  cp -a "$conf" "${conf}.bak.$(ts)"

  read -r -d '' perl_prog <<'PERL' || true
s/^\s*no_hardware_cursors\s*=\s*2\s*$/no_hardware_cursors = true/m;

s/^\s*#\s*env\s*=\s*__GLX_VENDOR_LIBRARY_NAME\s*,\s*nvidia\s*$/env = __GLX_VENDOR_LIBRARY_NAME,nvidia/m;
s/^\s*#\s*env\s*=\s*LIBVA_DRIVER_NAME\s*,\s*nvidia\s*$/env = LIBVA_DRIVER_NAME,nvidia/m;
PERL

  perl -i -pe "$perl_prog" "$conf"

  grep -qE '^\s*env\s*=\s*__GLX_VENDOR_LIBRARY_NAME\s*,\s*nvidia\s*$' "$conf" || \
    printf '\n%s\n' 'env = __GLX_VENDOR_LIBRARY_NAME,nvidia' >> "$conf"

  grep -qE '^\s*env\s*=\s*LIBVA_DRIVER_NAME\s*,\s*nvidia\s*$' "$conf" || \
    printf '%s\n' 'env = LIBVA_DRIVER_NAME,nvidia' >> "$conf"

  grep -qE '^\s*env\s*=\s*WLR_NO_HARDWARE_CURSORS\s*,\s*1\s*$' "$conf" || \
    printf '%s\n' 'env = WLR_NO_HARDWARE_CURSORS,1' >> "$conf"
}

# Must NOT run as root because yay/makepkg must run as user
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Run as your normal user. It will sudo when needed."
fi

if systemd-detect-virt -q; then
  exit 0
fi

gpu_line="$(lspci -nn | grep -Ei 'vga|3d|2d' | head -n1 || true)"
[[ -n "$gpu_line" ]] || die "No GPU found via lspci."

vendor="unknown"
if echo "$gpu_line" | grep -qi nvidia; then vendor="nvidia"; fi
if echo "$gpu_line" | grep -Eqi 'radeon|advanced micro devices|amd'; then vendor="amd"; fi
if echo "$gpu_line" | grep -qi intel; then vendor="intel"; fi
[[ "$vendor" != "unknown" ]] || exit 0

as_root pacman -Syu --noconfirm
as_root pacman -S --needed --noconfirm \
  mesa lib32-mesa \
  vulkan-icd-loader lib32-vulkan-icd-loader \
  libglvnd lib32-libglvnd \
  git base-devel

if [[ "$vendor" == "amd" ]]; then
  as_root pacman -S --needed --noconfirm \
    linux-firmware \
    vulkan-radeon lib32-vulkan-radeon vulkan-tools \
    libva-mesa-driver mesa-vdpau lib32-mesa-vdpau \
    libva-utils || true
fi

if [[ "$vendor" == "intel" ]]; then
  as_root pacman -S --needed --noconfirm \
    vulkan-intel lib32-vulkan-intel \
    libva-intel-driver libvdpau-va-gl \
    libva-utils || true
fi

if [[ "$vendor" == "nvidia" ]]; then
  need_legacy_580xx=0
  if echo "$gpu_line" | grep -Eiq 'GTX (7[0-9]{2}|8[0-9]{2}|9[0-9]{2}|10[0-9]{2})'; then
    need_legacy_580xx=1
  fi

  ensure_dkms_headers
  as_root pacman -S --needed --noconfirm egl-wayland

  # remove official branches + conflicting legacy dkms branches
  as_root pacman -Rns --noconfirm \
    nvidia nvidia-utils lib32-nvidia-utils nvidia-settings \
    nvidia-dkms nvidia-open nvidia-open-dkms \
    opencl-nvidia lib32-opencl-nvidia 2>/dev/null || true

  mapfile -t legacy_conflicts < <(pacman -Qq 2>/dev/null | grep -E '^nvidia-[0-9]{3}xx-dkms$' | grep -v '^nvidia-580xx-dkms$' || true)
  if ((${#legacy_conflicts[@]})); then
    as_root pacman -Rns --noconfirm "${legacy_conflicts[@]}" || true
  fi

  if [[ "$need_legacy_580xx" -eq 1 ]]; then
    bootstrap_yay
    yay -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
  else
    as_root pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
  fi

  as_root mkinitcpio -P

  patch_systemd_boot_modeset
  patch_grub_modeset
  patch_limine_modeset
  patch_hyprland_for_nvidia

  echo "Reboot. Then run: nvidia-smi"
fi