#!/usr/bin/env bash
# Isolated Sway profile install; no Hyprland or unknown custom file overwritten.
set -euo pipefail
fail() { printf 'Sway trial setup: %s\n' "$*" >&2; return 1; }
[[ $# -eq 1 ]] || { fail 'Usage: setup.sh --check|--install'; exit 2; }
case "$1" in --check|--install) action="$1" ;; *) fail 'Unknown action'; exit 2 ;; esac
[[ "$(id -u)" != 0 && -f /etc/arch-release ]] || { fail 'Use a normal Arch/CachyOS user'; exit 1; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
src="$repo/trials/sway"
tty_source="$src/tty-launch.sh"
tty_dir="$HOME/.local/bin"
tty_launcher="$tty_dir/sway"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
trial="$config/sway/awtarchy-trial"
native_source="$src/native-config"
native_config="$config/sway/config"
shell_dir="$config/quickshell/awtarchy-sway"
portal="$config/xdg-desktop-portal/sway-portals.conf"
screencast_chooser="$config/xdg-desktop-portal-wlr/sway"
for directory in "$config" "$config/sway" "$trial" "$config/quickshell" "$shell_dir" "$config/xdg-desktop-portal" "$config/xdg-desktop-portal-wlr"; do
    [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || { fail "Unsafe directory: $directory"; exit 1; }
done
[[ -f "$native_source" && ! -L "$native_source" ]] ||
    { fail "Missing native Sway config source"; exit 1; }
[[ ! -L "$native_config" && ( ! -e "$native_config" || -f "$native_config" ) ]] ||
    { fail "Unsafe native Sway config; preserve it manually"; exit 1; }
[[ -f "$tty_source" && ! -L "$tty_source" ]] && bash -n "$tty_source" ||
    { fail "Missing or invalid Sway TTY entry"; exit 1; }
for directory in "$HOME/.local" "$tty_dir"; do
    [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] ||
        { fail "Unsafe user launcher directory: $directory"; exit 1; }
done
[[ -x /usr/bin/sway ]] || { fail "Native /usr/bin/sway is unavailable"; exit 1; }
for bin in sway swaymsg qs foot fuzzel nwg-displays python3 jq flock grim slurp wl-copy; do
    command -v "$bin" >/dev/null 2>&1 || { fail "Missing package tool $bin"; exit 1; }
done
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
python3 "$src/render-quickshell.py" --source "$repo/config/quickshell/awtarchy" --dest "$temp/awtarchy-sway" --bridge-dir "$src" || { fail 'Quickshell render failed'; exit 1; }
python3 "$src/render-manager.py" --source "$repo/config/hypr/scripts/quickshell.sh" --dest "$temp/quickshell.sh" || { fail 'Quickshell manager render failed'; exit 1; }
bash -n "$temp/quickshell.sh" || { fail 'Rendered manager syntax invalid'; exit 1; }
sway -C -c "$src/config" || { fail 'Sway configuration rejected; nothing changed'; exit 1; }
sources=(config session.sh ipc.sh launcher.sh power.sh clipboard.sh notifications.sh quick-settings.sh application-state.sh cursor-theme.sh default-apps.sh mode-state.sh mode-help.sh mode-control.sh portal-chooser.py idle-manager.py idle-action.sh swayidle.conf lock.sh lock-manager.sh lock-capture.sh sensitive-capture.sh runtime-rules.sh position.sh capture.sh keyboard-state.py mime-parity.py login-sound.sh quicksettings.sh quicksettings.py monitor-info.py workspace-state.py theme-apply.sh theme-colors.sh toggle-utility.py diagnose.sh ddc.sh sway-portals.conf focus-cycle.py screencast-chooser.conf outputs)
targets=()
for name in "${sources[@]}"; do
    [[ -f "$src/$name" && ! -L "$src/$name" ]] || { fail "Missing source $name"; exit 1; }
    case "$name" in
        sway-portals.conf) target="$portal" ;;
        screencast-chooser.conf) target="$screencast_chooser" ;;
        *) target="$trial/$name" ;;
    esac
    targets+=("$target")
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -f "$target" && ! -L "$target" ]] || { fail "Unsafe destination $target"; exit 1; }
        if [[ "$name" == config ]]; then
            grep -Fqx '# Awtarchy Sway dual-compositor trial. Does not touch Hyprland.' "$target" || { fail 'Unknown existing Sway config'; exit 1; }
        fi
    fi
done
workspace_source="$repo/trials/workspaces"
workspace_target="$config/sway/workspaces"
[[ -f "$workspace_source" && ! -L "$workspace_source" ]] || {
    fail "Missing Sway workspace source"; exit 1;
}
[[ ! -e "$workspace_target" && ! -L "$workspace_target" ||
   ( -f "$workspace_target" && ! -L "$workspace_target" ) ]] || {
    fail "Unsafe Sway workspace destination"; exit 1;
}
# Sway-only installations must receive the exact Awtarchy login MP3.
# Never depend on the user's installed Hyprland configuration.
login_audio_source="$repo/config/hypr/sounds/awtarchy-login.mp3"
login_audio_target="$trial/awtarchy-login.mp3"
[[ -f "$login_audio_source" && ! -L "$login_audio_source" ]] || {
    fail "Missing exact Awtarchy login audio source"; exit 1;
}
[[ ! -e "$login_audio_target" && ! -L "$login_audio_target" ||
   ( -f "$login_audio_target" && ! -L "$login_audio_target" ) ]] || {
    fail "Unsafe Sway login audio destination"; exit 1;
}
# Stage exact branch-matched controller sources into the isolated Sway tree.
# Never overwrite installed Hyprland helper scripts or unknown Sway files.
ddc_sources=(ddc_brightness.sh hypr-ddc-brightness.sh screenshot_sound.sh)
for name in "${ddc_sources[@]}"; do
    source="$repo/config/hypr/scripts/$name"
    target="$trial/$name"
    [[ -f "$source" && ! -L "$source" ]] || { fail "Unsafe shared helper source: $source"; exit 1; }
    [[ ! -e "$target" && ! -L "$target" || ( -f "$target" && ! -L "$target" ) ]] || {
        fail "Unsafe shared helper destination: $target"; exit 1;
    }
done
for file in "$temp/quickshell.sh" "$temp/awtarchy-sway/"*; do
    if [[ "$file" == "$temp/quickshell.sh" ]]; then target="$trial/quickshell.sh"; else target="$shell_dir/${file##*/}"; fi
    [[ ! -e "$target" && ! -L "$target" || ( -f "$target" && ! -L "$target" ) ]] || { fail "Unsafe generated destination: $target"; exit 1; }
done
if [[ "$action" == --check ]]; then
    printf 'PASS: Sway config accepted, isolated UI generated, paths checked\n'
    exit 0
fi
for directory in "$config" "$config/sway" "$trial" "$config/quickshell" "$shell_dir" "$config/xdg-desktop-portal" "$config/xdg-desktop-portal-wlr"; do
    [[ -d "$directory" ]] || mkdir -m 0700 -- "$directory"
done
for i in "${!sources[@]}"; do
    name="${sources[$i]}"
    target="${targets[$i]}"
    [[ ! -e "$target" ]] || continue
    case "$name" in *.sh) perms=0755 ;; *) perms=0644 ;; esac
    install -m "$perms" -- "$src/$name" "$target"
done
[[ -e "$workspace_target" ]] || install -m 0644 -- "$workspace_source" "$workspace_target"
# The Arch-provided Sway Ly entry reads ~/.config/sway/config. Link only
# through a plain, managed include, without replacing a personal Sway config.
if [[ ! -e "$native_config" ]]; then
    install -m 0644 -- "$native_source" "$native_config"
elif ! cmp -s -- "$native_source" "$native_config"; then
    printf 'PRESERVE: personal Sway entry config %s; native Ly session will use it.\n' "$native_config"
fi
# Leave package-owned /usr/bin/sway untouched and preserve custom commands.
[[ -d "$HOME/.local" ]] || mkdir -m 0700 -- "$HOME/.local"
[[ -d "$tty_dir" ]] || mkdir -m 0700 -- "$tty_dir"
if [[ ! -e "$tty_launcher" && ! -L "$tty_launcher" ]]; then
    install -m 0755 -- "$tty_source" "$tty_launcher"
elif [[ -f "$tty_launcher" && ! -L "$tty_launcher" ]] &&
     cmp -s -- "$tty_source" "$tty_launcher"; then
    chmod u+x -- "$tty_launcher"
else
    printf 'PRESERVE: custom user sway command at %s; not overwritten.\n' "$tty_launcher"
fi
for name in "${ddc_sources[@]}"; do
    [[ -e "$trial/$name" ]] || install -m 0755 -- "$repo/config/hypr/scripts/$name" "$trial/$name"
done
[[ -e "$login_audio_target" ]] ||
    install -m 0644 -- "$login_audio_source" "$login_audio_target"
[[ -e "$trial/quickshell.sh" ]] || install -m 0755 -- "$temp/quickshell.sh" "$trial/quickshell.sh"
for file in "$temp/awtarchy-sway/"*; do
    target="$shell_dir/${file##*/}"
    [[ -e "$target" ]] || install -m 0644 -- "$file" "$target"
done
printf 'PASS: Sway trial staged, existing compositor and personal files preserved\n'
