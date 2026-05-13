-- ~/.config/hypr/hyprland.lua
-- Main Hyprland Lua config.
-- Compatibility helpers live in ~/.config/hypr/lua.lua.

dofile(os.getenv("HOME") .. "/.config/hypr/lua.lua")

--  ▄▄▄       █     █░▄▄▄█████▓ ▄▄▄       ██▀███   ▄████▄   ██░ ██▓██   ██▓
-- ▒████▄    ▓█░ █ ░█░▓  ██▒ ▓▒▒████▄    ▓██ ▒ ██▒▒██▀ ▀█  ▓██░ ██▒▒██  ██▒
-- ▒██  ▀█▄  ▒█░ █ ░█ ▒ ▓██░ ▒░▒██  ▀█▄  ▓██ ░▄█ ▒▒▓█    ▄ ▒██▀▀██░ ▒██ ██░
-- ░██▄▄▄▄██ ░█░ █ ░█ ░ ▓██▓ ░ ░██▄▄▄▄██ ▒██▀▀█▄  ▒▓▓▄ ▄██▒░▓█ ░██  ░ ▐██▓░
--  ▓█   ▓██▒░░██▒██▓   ▒██▒ ░  ▓█   ▓██▒░██▓ ▒██▒▒ ▓███▀ ░░▓█▒░██▓ ░ ██▒▓░
--  ▒▒   ▓▒█░░ ▓░▒ ▒    ▒ ░░    ▒▒   ▓▒█░░ ▒▓ ░▒▓░░ ░▒ ▒  ░ ▒ ░░▒░▒  ██▒▒▒
--   ▒   ▒▒ ░  ▒ ░ ░      ░      ▒   ▒▒ ░  ░▒ ░ ▒░  ░  ▒    ▒ ░▒░ ░▓██ ░▒░
--   ░   ▒     ░   ░    ░        ░   ▒     ░░   ░ ░         ░  ░░ ░▒ ▒ ░░
--       ░  ░    ░                   ░  ░   ░     ░ ░       ░  ░  ░░ ░
--                                                 ░                ░ ░

-- github.com/dillacorn/awtarchy/tree/main/config/hypr

-- ───────────────────────────────────────────────────────────────────────────────
-- MONITORS
-- ───────────────────────────────────────────────────────────────────────────────

-- list displays: hyprctl monitors
-- example syntax: monitor=(name),(resolution@refresh),(position_0x0),(scale),(vrr,1/0 = enable/disable VRR)
-- disable display example syntax: monitor=(name),disable

monitor([[,preferred,auto,auto,vrr,0]])
monitor([[Virtual-1,1600x900@60,auto,1,vrr,0]])

-- ───────────────────────────────────────────────────────────────────────────────
-- ENV
-- ───────────────────────────────────────────────────────────────────────────────

env([[XDG_CURRENT_DESKTOP,Hyprland]])
env([[XDG_SESSION_DESKTOP,Hyprland]])
env([[XDG_SESSION_TYPE,wayland]])
env([[GDK_BACKEND,wayland,x11,*]])
env([[QT_QPA_PLATFORM,wayland;xcb]])
env([[CLUTTER_BACKEND,wayland]])
env([[QT_STYLE_OVERRIDE,kvantum]])
env([[QT_AUTO_SCREEN_SCALE_FACTOR,1]])
env([[QT_WAYLAND_DISABLE_WINDOWDECORATION,1]])
env([[QT_QPA_PLATFORMTHEME,qt5ct]])
env([[QT6CT_PLATFORM_PLUGIN,qt6ct]])
env([[QT_QUICK_CONTROLS_STYLE,org.hyprland.style]])
env([[MOZ_ENABLE_WAYLAND,1]])
env([[GDK_SCALE,1]])
env([[QT_SCALE_FACTOR,1]])
env([[XCURSOR_SIZE,24]])
env([[GTK_THEME,Materia-dark]])
env([[XCURSOR_THEME,ComixCursors-White]])
env([[GAMESCOPE_WSI,vk_wayland]])

-- Commented out section
-- env = WLR_RENDERER_ALLOW_SOFTWARE,0
-- env = WLR_DRM_NO_ATOMIC,1  # Can help with some GPUs
-- env = HYPRLAND_NO_RT,1     # Disable realtime scheduling if having issues
-- env = __GL_GSYNC_ALLOWED,1
-- env = __GL_VRR_ALLOWED,1

-- Commented out - For NVIDIA (proprietary driver recommended)
-- env = __GLX_VENDOR_LIBRARY_NAME,nvidia  # NVIDIA GLX vendor
-- env = LIBVA_DRIVER_NAME,nvidia          # NVIDIA VA-API driver

-- Wayland GBM backend
-- env = GBM_BACKEND,nvidia-drm            # NVIDIA GBM backend

-- ───────────────────────────────────────────────────────────────────────────────
-- PERMISSIONS (requires Hyprland restart after edits)
-- ───────────────────────────────────────────────────────────────────────────────

-- Add future apps (getting the correct path/regex):
-- 1) Best: when Hyprland prompts, copy the binary path it shows and paste it into:
--    permission = /full/path/to/bin, <perm>, <mode>
--
-- 2) If you know the command name (replace `grim` with your app):
--    readlink -f "$(command -v grim)"
--
-- 3) If the app has a window open: focus it, then run:
--    pid="$(hyprctl activewindow -j | jq -r .pid)"; readlink -f "/proc/$pid/exe"
--
-- Keyboard device names (for `keyboard` rules):
--   hyprctl devices

    config_set({[[ecosystem]]}, [[no_update_news]], [[true]])
    config_set({[[ecosystem]]}, [[enforce_permissions]], [[true]])

-- screencopy (direct capture)
permission([[/usr/bin/grim, screencopy, allow]])
permission([[/usr/bin/wf-recorder, screencopy, allow]])
permission([[/usr/bin/hyprpicker, screencopy, allow]])
permission([[/usr/bin/hyprlock, screencopy, allow]])
permission([[/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland, screencopy, allow]])

-- plugin (hyprpm)
permission([[/usr/(bin|local/bin)/hyprpm, plugin, allow]])

-- keyboard allowlist template (default is allow)
-- permission = ^(YOUR KEYBOARD NAME REGEX)$, keyboard, allow
-- permission = .*, keyboard, deny

-- ───────────────────────────────────────────────────────────────────────────────
-- AUTOSTART
-- ───────────────────────────────────────────────────────────────────────────────

exec_once([[dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE]])
exec_once([[systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE]])

exec_once([[sh -lc '$HOME/.config/hypr/scripts/portal_fixup.sh']])
exec_once([[/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1]])
exec_once([[gnome-keyring-daemon --start --password-store=secrets]])

-- exec-once = ~/.config/hypr/scripts/last_to_load_recorder.sh &
exec_once([[~/.config/hypr/scripts/waybar.sh start &]])
exec_once([[~/.config/hypr/scripts/waybar_ready_sound.sh &]])

exec_once([[hyprsunset &]])
exec_once([[mako &]])
exec_once([[nm-applet &]])
exec_once([[blueman-applet &]])
exec_once([[nwg-look -a &]])
exec_once([[hypridle -c ~/.config/hypr/hypridle.conf &]])
exec_once([[~/.config/hypr/scripts/hyprpm-auto-reload.sh &]])
exec_once([[~/.config/hypr/scripts/awtwall-awtarchy-init.sh &]])
-- exec-once = ~/.config/hypr/scripts/wallpaper_engine.sh &
exec_once([[sh -lc 'exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e "$HOME/.config/hypr/scripts/awtarchy-tips-tui.sh" --autostart']])
-- exec_once([[~/.config/hypr/scripts/miclock.sh &]])
exec_once([[wl-paste --type text --watch cliphist store &]])
exec_once([[wl-paste --type image --watch cliphist store &]])

-- Optional: USB refresh helper
-- List USB devices:
-- lsusb
-- Map a device once:
-- ~/.config/hypr/scripts/usb_refresh_fixer.sh map 20b1:3008 ifi
--
-- Then optionally run at startup:
--
-- Non-audio USB device:
-- exec-once = ~/.config/hypr/scripts/usb_refresh_fixer.sh refresh myusb &
--
-- USB audio device, just refresh it and wait for the audio sink to exist again:
-- exec-once = ~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio ifi &
--
-- USB audio device, refresh it and force it as default sink:
-- exec_once([[~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio-default ifi &]])

-- ───────────────────────────────────────────────────────────────────────────────
-- LOOK & FEEL
-- ───────────────────────────────────────────────────────────────────────────────

    config_set({[[general]]}, [[gaps_in]], [[6]])
    config_set({[[general]]}, [[gaps_out]], [[9]])
    config_set({[[general]]}, [[border_size]], [[1]])
config_set({[[general]]}, [[col.active_border]], [[rgba(a0a0a0ff)]])
config_set({[[general]]}, [[col.inactive_border]], [[rgba(4b4b4bff)]])
    config_set({[[general]]}, [[resize_on_border]], [[true]])
    config_set({[[general]]}, [[allow_tearing]], [[true]])
    config_set({[[general]]}, [[layout]], [[dwindle]])

    config_set({[[decoration]]}, [[rounding]], [[0]])
    config_set({[[decoration]]}, [[rounding_power]], [[2]])
    config_set({[[decoration]]}, [[active_opacity]], [[1.0]])
    config_set({[[decoration]]}, [[inactive_opacity]], [[1.0]])

    -- Shaders (uncomment only one)
    --screen_shader = ~/.config/hypr/shaders/vibrance
    --screen_shader = ~/.config/hypr/shaders/cathode_ray_tube_optional_vibrance
    --screen_shader = ~/.config/hypr/shaders/subtle_crt
    --screen_shader = ~/.config/hypr/shaders/gimmicky-crt

    -- Shaders that require `debug { damage_tracking = 0 } }` or you will see config errors.
    --screen_shader = ~/.config/hypr/shaders/vhs
    --screen_shader = ~/.config/hypr/shaders/acid_trip

        config_set({[[decoration]], [[shadow]]}, [[enabled]], [[true]])
        config_set({[[decoration]], [[shadow]]}, [[range]], [[4]])
        config_set({[[decoration]], [[shadow]]}, [[render_power]], [[3]])
        config_set({[[decoration]], [[shadow]]}, [[color]], [[rgba(1a1a1aee)]])

        config_set({[[decoration]], [[blur]]}, [[enabled]], [[true]])
        config_set({[[decoration]], [[blur]]}, [[size]], [[3]])
        config_set({[[decoration]], [[blur]]}, [[passes]], [[1]])
        config_set({[[decoration]], [[blur]]}, [[vibrancy]], [[0.1696]])

    config_set({[[debug]]}, [[damage_tracking]], [[2]])

    -- Direct scanout: 0 = off, 1 = on, 2 = auto (only when content_type == "game")
    -- Reduces latency when a single fullscreen client (e.g. nested gamescope) owns the monitor.
    config_set({[[render]]}, [[direct_scanout]], [[2]])

    -- Non-shader color management:
    -- 0 = disable
    -- 1 = whenever possible
    -- 2 = only with direct scanout & passthrough
    -- 3 = disable and ignore CM issues
    -- 2 is the “DS + passthrough only” mode, which pairs cleanly with gamescope.
    config_set({[[render]]}, [[non_shader_cm]], [[2]])

    -- Fullscreen HDR color-management auto-switch:
    -- 0 = off
    -- 1 = switch to cm,hdr
    -- 2 = switch to cm,hdredid
    -- cm_fs_passthrough was removed in Hyprland 0.55.
    config_set({[[render]]}, [[cm_auto_hdr]], [[1]])

--   nvidia_anti_flicker = true

    config_set({[[cursor]]}, [[sync_gsettings_theme]], [[true]])
    config_set({[[cursor]]}, [[no_hardware_cursors]], [[2]])
    config_set({[[cursor]]}, [[zoom_disable_aa]], [[true]])
    config_set({[[cursor]]}, [[no_warps]], [[false]])
    config_set({[[cursor]]}, [[persistent_warps]], [[false]])
    config_set({[[cursor]]}, [[warp_on_change_workspace]], [[0]])
    config_set({[[cursor]]}, [[enable_hyprcursor]], [[true]])

    config_set({[[animations]]}, [[enabled]], [[yes]])
    curve([[easeOutQuint, 0.23, 1, 0.32, 1]])
    curve([[easeInOutSlight, 0.4, 0.1, 0.2, 1]])
    curve([[linear, 0, 0, 1, 1]])
    curve([[softFade, 0.2, 0.5, 0.3, 1]])
    curve([[fastOut, 0.2, 0, 0.6, 1]])
    animation([[global, 1, 8, default]])
    animation([[border, 1, 3.0, easeOutQuint]])
    animation([[borderangle, 1, 40, linear, once]])
    animation([[windows, 1, 3.0, easeOutQuint]])
    animation([[windowsIn, 1, 2.0, easeOutQuint, popin 87%]])
    animation([[windowsOut, 1, 1.5, linear, popin 87%]])
    animation([[fadeIn, 1, 1.5, softFade]])
    animation([[fadeOut, 1, 1.3, softFade]])
    animation([[fade, 1, 2.0, softFade]])
    animation([[layers, 1, 2.5, easeInOutSlight]])
    animation([[layersIn, 1, 2.0, easeInOutSlight, fade]])
    animation([[layersOut, 1, 1.5, fastOut, fade]])
    animation([[fadeLayersIn, 1, 1.4, softFade]])
    animation([[fadeLayersOut, 1, 1.3, softFade]])
    animation([[workspaces, 1, 1.8, easeInOutSlight, fade]])
    animation([[workspacesIn, 1, 1.3, softFade, fade]])
    animation([[workspacesOut, 1, 1.4, softFade, fade]])
    animation([[specialWorkspace, 1, 1.9, easeInOutSlight, fade]])

    config_set({[[dwindle]]}, [[preserve_split]], [[true]])
    config_set({[[dwindle]]}, [[force_split]], [[0]])
    config_set({[[dwindle]]}, [[special_scale_factor]], [[0.9]])
    -- smart_split = true
    -- single_window_aspect_ratio = 1 0.6852

    config_set({[[master]]}, [[new_status]], [[master]])
    config_set({[[master]]}, [[new_on_top]], [[1]])
    config_set({[[master]]}, [[mfact]], [[0.5]])

    -- Visuals (startup / defaults)
    config_set({[[misc]]}, [[force_default_wallpaper]], [[-1]])
    config_set({[[misc]]}, [[disable_hyprland_logo]], [[true]])
    config_set({[[misc]]}, [[disable_splash_rendering]], [[true]])

    -- Rendering / display behavior
    config_set({[[misc]]}, [[vrr]], [[2]])
    config_set({[[misc]]}, [[mouse_move_enables_dpms]], [[true]])

    -- Input convenience
    config_set({[[misc]]}, [[middle_click_paste]], [[false]])

    -- Focus / workspace behavior
    config_set({[[misc]]}, [[focus_on_activate]], [[false]])
    config_set({[[misc]]}, [[initial_workspace_tracking]], [[0]])

    -- Swallowing (terminal -> spawned app)
    config_set({[[misc]]}, [[enable_swallow]], [[off]])
    config_set({[[misc]]}, [[swallow_regex]], [[^([Aa]lacritty)$]])

    -- Stability / UX dialogs
    config_set({[[misc]]}, [[enable_anr_dialog]], [[true]])
    config_set({[[misc]]}, [[allow_session_lock_restore]], [[true]])

    -- Suppress helper warnings/checks
    config_set({[[misc]]}, [[disable_hyprland_guiutils_check]], [[true]])

    config_set({[[xwayland]]}, [[enabled]], [[true]])
    config_set({[[xwayland]]}, [[force_zero_scaling]], [[true]])

        config_set({[[plugin]], [[hyprbars]]}, [[bar_height]], [[20]])

        -- bar background
        config_set({[[plugin]], [[hyprbars]]}, [[bar_color]], [[rgb(1e1e1e)]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_blur]], [[false]])

        -- title text (optional)
        config_set({[[plugin]], [[hyprbars]]}, [[col.text]], [[rgb(d0d0d0)]])

        -- layout
        config_set({[[plugin]], [[hyprbars]]}, [[bar_title_enabled]], [[true]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_buttons_alignment]], [[right]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_padding]], [[5]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_button_padding]], [[7]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_text_align]], [[left]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_text_size]], [[10]])
        config_set({[[plugin]], [[hyprbars]]}, [[bar_text_font]], [[NotoSansM Nerd Font Mono]])

        -- buttons: same as bar background; icons are light gray
        hyprbars_button([[rgb(1e1e1e), 20, , hyprctl dispatch killactive]])
        hyprbars_button([[rgb(1e1e1e), 20, 󰨤, hyprctl dispatch fullscreen 1]])
        hyprbars_button([[rgb(1e1e1e), 20, , hyprctl dispatch togglefloating]])

        config_set({[[plugin]], [[hyprbars]]}, [[on_double_click]], [[hyprctl dispatch fullscreen 1]])

-- ───────────────────────────────────────────────────────────────────────────────
-- INPUT
-- ───────────────────────────────────────────────────────────────────────────────

    config_set({[[input]]}, [[kb_layout]], [[us]])
    config_set({[[input]]}, [[follow_mouse]], [[1]])
    config_set({[[input]]}, [[repeat_delay]], [[250]])
    config_set({[[input]]}, [[repeat_rate]], [[35]])
    config_set({[[input]]}, [[numlock_by_default]], [[true]])

        config_set({[[input]], [[touchpad]]}, [[natural_scroll]], [[true]])
        config_set({[[input]], [[touchpad]]}, [[disable_while_typing]], [[true]])
        config_set({[[input]], [[touchpad]]}, [[clickfinger_behavior]], [[true]])
        config_set({[[input]], [[touchpad]]}, [[scroll_factor]], [[0.5]])

    -- Mouse: No acceleration (1:1 raw input)
    config_set({[[input]]}, [[accel_profile]], [[flat]])
    config_set({[[input]]}, [[sensitivity]], [[0]])
    config_set({[[input]]}, [[force_no_accel]], [[1]])

    -- ──────────────────────────────────────────────────────────────
    -- Game profiles @ 400 DPI w/ maccel
    -- ──────────────────────────────────────────────────────────────

    -- CS2 (Tactical - no accel)
    -- Sens: 2.0
    -- Style: Precise, consistent aim for tac shooters
    -- maccel: Use "No Accel" mode with SENS_MULT 0.40 (400 DPI)

    -- The Finals (Arena - with accel)
    -- Hardware mouse DPI:    1600           # Hardware DPI of mouse
    -- Base sens:             35             # Precise tracking
    -- Fast sens:             47             # flicks / movement
    -- Accel ratio:           47/35 = 1.34   # fast/base = ratio value
    -- maccel setup:
    --   - Mode: Linear
    --   - SENS_MULT:         0.40    # 400 DPI feel
    --   - Y/x Ratio:         1.0     # 1.2 on 4:3 stretched / 1.1 on 16:10 stretched
    --   - INPUT_DPI:         1600    # must match hardware DPI
    --   - Angle Rotation:    0.0     # personal preference
    --   - Accel:             1000    # no diff past value of 7 in graph visually but I believe increasing past 7 actually makes the jump more steep, because it does in "raw accel"
    --   - Offset:            15      # accel activation threshold (mouse speed)
    --   - OutputCap:         1.34    # example varies between games

    -- ──────────────────────────────────────────────────────────────
    -- maccel setup guide
    -- https://github.com/Gnarus-G/maccel
    --
    -- How to calculate your OutputCap: (value varies between all games)
    -- 1. Play without accel - find your comfortable "fast" sens (e.g., 47)
    -- 2. Find the "slow" sens you want for precision (e.g., 35)
    -- 3. Calculate: OutputCap = fast_sens / slow_sens
    --    Example: 47 / 35 = 1.34
    --
    -- Result: Slow movements = 35 sens, fast flicks = 47 sens
    -- (Game Example: The Finals)
    --
    -- ──────────────────────────────────────────────────────────────

-- ───────────────────────────────────────────────────────────────────────────────
-- GESTURES
-- ───────────────────────────────────────────────────────────────────────────────

-- See https://wiki.hypr.land/Configuring/Gestures
gesture([[3, horizontal, workspace]])

-- ───────────────────────────────────────────────────────────────────────────────
-- MODIFIERS
-- ───────────────────────────────────────────────────────────────────────────────

set_var([[mod]], [[ALT]])
set_var([[super]], [[SUPER]])
set_var([[tempalt]], [[ALT]])
set_var([[submap_file]], [[/tmp/hypr-submap]])

-- ───────────────────────────────────────────────────────────────────────────────
-- LAUNCHERS / COMMANDS
-- ───────────────────────────────────────────────────────────────────────────────

-- Base paths (using variables instead of repeating ~/.config/hypr/scripts everywhere)
set_var([[hypr_dir]], [[~/.config/hypr]])
set_var([[hypr_scripts]], [[$hypr_dir/scripts]])
set_var([[launch]], [[$hypr_scripts/launch_handler.sh]])

-- Core apps (define before anything that uses them)
set_var([[terminal]], [[alacritty]])
set_var([[web-browser]], [[firefox]])
set_var([[calculator]], [[speedcrunch]])
set_var([[yazi]], [[$terminal -e yazi]])

-- App/menu launchers
set_var([[app-launcher]], [[$hypr_scripts/fuzzel_toggle.sh]])
set_var([[wlogout]], [[$hypr_scripts/wlogout_toggle.sh]])
set_var([[hypr_quicksettings]], [[$launch hypr_quicksettings "$terminal --class hypr_quicksettings -e $hypr_scripts/hypr_quicksettings.sh"]])
set_var([[awtarchy-tips-tui]], [[$launch awtarchy-tips-tui "$terminal --class awtarchy-tips-tui -e $hypr_scripts/awtarchy-tips-tui.sh"]])

-- Audio
set_var([[wiremix]], [[$launch wiremix "$terminal --class Wiremix -e wiremix"]])
set_var([[pavucontrol]], [[$launch pavucontrol "pavucontrol"]])
set_var([[pulsemixer]], [[$launch pulsemixer "$terminal --class Pulsemixer -e pulsemixer"]])
set_var([[mute_unmute]], [[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle]])
set_var([[play_pause]], [[$hypr_scripts/play_pause.sh]])

-- Bars / UI toggles
set_var([[hyprbars_toggle]], [[$hypr_scripts/hyprbars_toggle.sh]])
set_var([[waybar_toggle]], [[$hypr_scripts/waybar_toggle.sh]])
set_var([[waybar_flip]], [[$hypr_scripts/waybar_flip.sh]])
set_var([[waybar_rotate]], [[$hypr_scripts/waybar_rotate.sh]])
set_var([[toggle_animations]], [[$hypr_scripts/toggle_animations.sh]])
set_var([[mako_dismiss]], [[$hypr_scripts/mako_dismiss.sh]])

-- Themes / wallpaper
set_var([[wallpicker]], [[$launch wallpicker "$terminal --class wallpicker -e awtwall --resume"]])
set_var([[theme_select]], [[$hypr_scripts/theme_select.sh]])

-- Capture / clipboard / QR
set_var([[screenshot_select]], [[env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN $hypr_scripts/screenshot_area.sh]])
set_var([[screenshot_full]], [[$hypr_scripts/screenshot_fullscreen.sh]])
set_var([[screenshot_display]], [[$hypr_scripts/screenshot_display.sh]])
set_var([[gif_capture]], [[$hypr_scripts/gif_capture.sh]])
set_var([[clipboard_history]], [[$hypr_scripts/cliphist-fuzzel.sh]])
set_var([[qr_scan]], [[$hypr_scripts/qr_scan.sh]])

-- Utilities
set_var([[workspace_mix]], [[$hypr_scripts/workspace_mix.sh]])
set_var([[zoom]], [[$hypr_scripts/zoom.sh]])
set_var([[hyprpicker]], [[hyprpicker -a -f hex]])
set_var([[hypr-ddc-brightness]], [[$hypr_scripts/hypr-ddc-brightness.sh]])
set_var([[vibrance_shader]], [[$hypr_scripts/vibrance_shader.sh]])
set_var([[hyprsunset_ctl]], [[$hypr_scripts/hyprsunset_ctl.sh]])

-- Terminal tools
set_var([[maccel]], [[$launch maccel "$terminal --class maccel -e maccel"]])
set_var([[smtty]], [[$launch smtty "$terminal --class smtty -e smtty"]])
set_var([[btop]], [[$launch btop "$terminal --class btop -e btop"]])

-- Complex one-off
set_var([[smtty-O]], [[sh -lc 'if hyprctl clients | grep -q "class: smtty-O"; then hyprctl dispatch closewindow class:smtty-O; else $terminal --class smtty-O -e sh -lc '"'"'smtty -O; printf "\n[smtty -O finished]\nPress ENTER to close..."; read -r _'"'"'; fi']])

-- Submap references (Toggle on)  [write name to file on entry]
set_var([[noalt_on]], [[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']])
set_var([[mouse_on]], [[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']])
set_var([[vm_on]], [[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']])

-- ───────────────────────────────────────────────────────────────────────────────
-- DEFAULT MODE (ALT is modifier; SUPER is app/meta)
-- ───────────────────────────────────────────────────────────────────────────────

-- App launchers / terminals
bind([[bind]], [[$mod]], [[P]], [[exec]], [[$app-launcher]])
bind([[bind]], [[$super]], [[D]], [[exec]], [[$app-launcher]])
bind([[bind]], [[$mod SHIFT]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$super SHIFT]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$super]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$mod SHIFT]], [[B]], [[exec]], [[$btop]])
bind([[bind]], [[$super SHIFT]], [[B]], [[exec]], [[$btop]])
bind([[bind]], [[$super]], [[B]], [[exec]], [[$web-browser]])
bind([[bind]], [[$mod SHIFT]], [[C]], [[exec]], [[$calculator]])
bind([[bind]], [[$super SHIFT]], [[C]], [[exec]], [[$calculator]])
bind([[bind]], [[$mod SHIFT]], [[M]], [[exec]], [[$maccel]])
bind([[bind]], [[$super SHIFT]], [[M]], [[exec]], [[$maccel]])

-- Audio mixer
bind([[bind]], [[$mod]], [[V]], [[exec]], [[$wiremix]])
bind([[bind]], [[$super]], [[V]], [[exec]], [[$wiremix]])

-- Mako dismiss
bind([[bind]], [[$mod]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod CTRL]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod SHIFT]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod CTRL SHIFT]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$super]], [[SPACE]], [[exec]], [[$mako_dismiss]])

-- Terminal utilities (smtty)
bind([[bind]], [[$super $mod]], [[G]], [[exec]], [[$smtty]])
bind([[bind]], [[$super $mod]], [[L]], [[exec]], [[smtty -S -l]])
bind([[bind]], [[$super $mod]], [[O]], [[exec]], [[$smtty-O]])
bind([[bind]], [[$super $mod]], [[K]], [[exec]], [[smtty -k]])

-- UI / compositor toggles
bind([[bind]], [[$super $mod]], [[T]], [[exec]], [[$hyprbars_toggle]])
bind([[bind]], [[$super $mod]], [[B]], [[exec]], [[$waybar_rotate]])
bind([[bind]], [[$super $mod CTRL]], [[B]], [[exec]], [[$waybar_toggle]])
bind([[bind]], [[$super CTRL]], [[B]], [[exec]], [[$waybar_flip]])
bind([[bind]], [[$super]], [[A]], [[exec]], [[$toggle_animations]])

-- Brightness / color temperature
bind([[bind]], [[$super $mod]], [[backspace]], [[exec]], [[$hypr_quicksettings]])
bind([[bind]], [[$super $mod]], [[equal]], [[exec]], [[$hypr-ddc-brightness up 5]])
bind([[bind]], [[$super $mod]], [[minus]], [[exec]], [[$hypr-ddc-brightness down 5]])
bind([[bind]], [[$super $mod CTRL]], [[equal]], [[exec]], [[$hyprsunset_ctl up]])
bind([[bind]], [[$super $mod CTRL]], [[minus]], [[exec]], [[$hyprsunset_ctl down]])
bind([[bind]], [[$super $mod CTRL]], [[backspace]], [[exec]], [[$hyprsunset_ctl toggle]])

-- File managers / system
bind([[bind]], [[$super]], [[E]], [[exec]], [[pcmanfm-qt]])
bind([[bind]], [[$super SHIFT]], [[E]], [[exec]], [[$yazi]])
bind([[bind]], [[$super]], [[L]], [[exec]], [[hyprlock]])
bind([[bind]], [[$super]], [[I]], [[exec]], [[$hyprpicker]])
bind([[bind]], [[$super]], [[P]], [[exec]], [[$wlogout]])

-- Themes / wallpaper
bind([[bind]], [[$super]], [[W]], [[exec]], [[$wallpicker]])
bind([[bind]], [[$super SHIFT]], [[W]], [[exec]], [[awtwall --random-current]])
bind([[bind]], [[$super CTRL]], [[W]], [[exec]], [[awtwall --random-all]])
bind([[bind]], [[$super $mod]], [[W]], [[exec]], [[awtwall --random-all-different]])
bind([[bind]], [[$super]], [[T]], [[exec]], [[$theme_select]])

-- Capture / clipboard / misc
bind([[bind]], [[$super]], [[C]], [[exec]], [[$clipboard_history]])
bind([[bind]], [[$super]], [[S]], [[exec]], [[$qr_scan]])
bind([[bind]], [[$super SHIFT]], [[S]], [[exec]], [[$screenshot_select]])
bind([[bind]], [[$super SHIFT]], [[F]], [[exec]], [[$screenshot_full]])
bind([[bind]], [[$super SHIFT]], [[D]], [[exec]], [[$screenshot_display]])
bind([[bind]], [[$super SHIFT]], [[G]], [[exec]], [[$gif_capture]])

-- Window management
bind([[bind]], [[$super]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$super SHIFT]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$mod SHIFT]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$mod]], [[F4]], [[killactive]], [[]])
bind([[bind]], [[$super $mod]], [[Q]], [[exec]], [[hyprctl kill]])
bind([[bind]], [[$mod]], [[Y]], [[pin]], [[]])
bind([[bind]], [[$super]], [[Y]], [[pin]], [[]])
bind([[bind]], [[$tempalt]], [[R]], [[layoutmsg]], [[swapsplit]])
bind([[bind]], [[$tempalt SHIFT]], [[R]], [[layoutmsg]], [[togglesplit]])
bind([[bind]], [[$super]], [[R]], [[layoutmsg]], [[swapsplit]])
bind([[bind]], [[$super SHIFT]], [[R]], [[layoutmsg]], [[togglesplit]])
bind([[bind]], [[$tempalt]], [[F]], [[togglefloating]], [[]])
bind([[bind]], [[$tempalt CTRL]], [[F]], [[fullscreen]], [[]])
bind([[bind]], [[$super]], [[F]], [[togglefloating]], [[]])
bind([[bind]], [[$super CTRL]], [[F]], [[fullscreen]], [[]])
bind([[bind]], [[$mod]], [[TAB]], [[cyclenext]], [[]])
bind([[bind]], [[$mod]], [[TAB]], [[bringactivetotop]], [[]])
bind([[bind]], [[$mod SHIFT]], [[TAB]], [[cyclenext]], [[prev]])

-- Focus move (ALT/SUPER arrows)
bind([[bind]], [[$tempalt]], [[left]], [[movefocus]], [[l]])
bind([[bind]], [[$tempalt]], [[right]], [[movefocus]], [[r]])
bind([[bind]], [[$tempalt]], [[up]], [[movefocus]], [[u]])
bind([[bind]], [[$tempalt]], [[down]], [[movefocus]], [[d]])
bind([[bind]], [[$super]], [[left]], [[movefocus]], [[l]])
bind([[bind]], [[$super]], [[right]], [[movefocus]], [[r]])
bind([[bind]], [[$super]], [[up]], [[movefocus]], [[u]])
bind([[bind]], [[$super]], [[down]], [[movefocus]], [[d]])
-- ALT/SUPER hjkl
bind([[bind]], [[$tempalt]], [[h]], [[movefocus]], [[l]])
bind([[bind]], [[$tempalt]], [[j]], [[movefocus]], [[d]])
bind([[bind]], [[$tempalt]], [[k]], [[movefocus]], [[u]])
bind([[bind]], [[$tempalt]], [[l]], [[movefocus]], [[r]])
bind([[bind]], [[$super]], [[h]], [[movefocus]], [[l]])
bind([[bind]], [[$super]], [[j]], [[movefocus]], [[d]])
bind([[bind]], [[$super]], [[k]], [[movefocus]], [[u]])
bind([[bind]], [[$super]], [[l]], [[movefocus]], [[r]])

-- Window move (ALT/SUPER+SHIFT arrows)
bind([[bind]], [[$tempalt SHIFT]], [[left]], [[movewindow]], [[l]])
bind([[bind]], [[$tempalt SHIFT]], [[right]], [[movewindow]], [[r]])
bind([[bind]], [[$tempalt SHIFT]], [[up]], [[movewindow]], [[u]])
bind([[bind]], [[$tempalt SHIFT]], [[down]], [[movewindow]], [[d]])
bind([[bind]], [[$super SHIFT]], [[left]], [[movewindow]], [[l]])
bind([[bind]], [[$super SHIFT]], [[right]], [[movewindow]], [[r]])
bind([[bind]], [[$super SHIFT]], [[up]], [[movewindow]], [[u]])
bind([[bind]], [[$super SHIFT]], [[down]], [[movewindow]], [[d]])
-- ALT/SUPER+SHIFT hjkl
bind([[bind]], [[$tempalt SHIFT]], [[h]], [[movewindow]], [[l]])
bind([[bind]], [[$tempalt SHIFT]], [[j]], [[movewindow]], [[d]])
bind([[bind]], [[$tempalt SHIFT]], [[k]], [[movewindow]], [[u]])
bind([[bind]], [[$tempalt SHIFT]], [[l]], [[movewindow]], [[r]])
bind([[bind]], [[$super SHIFT]], [[h]], [[movewindow]], [[l]])
bind([[bind]], [[$super SHIFT]], [[j]], [[movewindow]], [[d]])
bind([[bind]], [[$super SHIFT]], [[k]], [[movewindow]], [[u]])
bind([[bind]], [[$super SHIFT]], [[l]], [[movewindow]], [[r]])

-- Send current workspace to monitor (ALT/SUPER+CTRL+SHIFT numbers)
bind([[bind]], [[$tempalt CTRL SHIFT]], [[left]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$tempalt CTRL SHIFT]], [[right]], [[movecurrentworkspacetomonitor]], [[+1]])
bind([[bind]], [[$tempalt CTRL SHIFT]], [[up]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$tempalt CTRL SHIFT]], [[down]], [[movecurrentworkspacetomonitor]], [[+1]])
bind([[bind]], [[$super CTRL SHIFT]], [[left]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[right]], [[movecurrentworkspacetomonitor]], [[+1]])
bind([[bind]], [[$super CTRL SHIFT]], [[up]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[down]], [[movecurrentworkspacetomonitor]], [[+1]])
-- ALT/SUPER+CTRL+SHIFT "[" or "]"
bind([[bind]], [[$tempalt CTRL SHIFT]], [[bracketleft]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$tempalt CTRL SHIFT]], [[bracketright]], [[movecurrentworkspacetomonitor]], [[+1]])
bind([[bind]], [[$super CTRL SHIFT]], [[bracketleft]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[bracketright]], [[movecurrentworkspacetomonitor]], [[+1]])

-- Workspaces (ALT/SUPER numbers)
bind([[bind]], [[$tempalt]], [[1]], [[workspace]], [[1]])
bind([[bind]], [[$tempalt]], [[2]], [[workspace]], [[2]])
bind([[bind]], [[$tempalt]], [[3]], [[workspace]], [[3]])
bind([[bind]], [[$tempalt]], [[4]], [[workspace]], [[4]])
bind([[bind]], [[$tempalt]], [[5]], [[workspace]], [[5]])
bind([[bind]], [[$tempalt]], [[6]], [[workspace]], [[6]])
bind([[bind]], [[$tempalt]], [[7]], [[workspace]], [[7]])
bind([[bind]], [[$tempalt]], [[8]], [[workspace]], [[8]])
bind([[bind]], [[$tempalt]], [[9]], [[workspace]], [[9]])
bind([[bind]], [[$tempalt]], [[0]], [[workspace]], [[10]])
bind([[bind]], [[$super]], [[1]], [[workspace]], [[1]])
bind([[bind]], [[$super]], [[2]], [[workspace]], [[2]])
bind([[bind]], [[$super]], [[3]], [[workspace]], [[3]])
bind([[bind]], [[$super]], [[4]], [[workspace]], [[4]])
bind([[bind]], [[$super]], [[5]], [[workspace]], [[5]])
bind([[bind]], [[$super]], [[6]], [[workspace]], [[6]])
bind([[bind]], [[$super]], [[7]], [[workspace]], [[7]])
bind([[bind]], [[$super]], [[8]], [[workspace]], [[8]])
bind([[bind]], [[$super]], [[9]], [[workspace]], [[9]])
bind([[bind]], [[$super]], [[0]], [[workspace]], [[10]])

-- Prev/next workspace with (ALT/SUPER "[" or "]")
bind([[bind]], [[$tempalt]], [[bracketleft]], [[workspace]], [[-1]])
bind([[bind]], [[$tempalt]], [[bracketright]], [[workspace]], [[+1]])
bind([[bind]], [[$super]], [[bracketleft]], [[workspace]], [[-1]])
bind([[bind]], [[$super]], [[bracketright]], [[workspace]], [[+1]])

-- Move window to workspace (ALT/SUPER+SHIFT numbers)
bind([[bind]], [[$tempalt SHIFT]], [[1]], [[movetoworkspacesilent]], [[1]])
bind([[bind]], [[$tempalt SHIFT]], [[2]], [[movetoworkspacesilent]], [[2]])
bind([[bind]], [[$tempalt SHIFT]], [[3]], [[movetoworkspacesilent]], [[3]])
bind([[bind]], [[$tempalt SHIFT]], [[4]], [[movetoworkspacesilent]], [[4]])
bind([[bind]], [[$tempalt SHIFT]], [[5]], [[movetoworkspacesilent]], [[5]])
bind([[bind]], [[$tempalt SHIFT]], [[6]], [[movetoworkspacesilent]], [[6]])
bind([[bind]], [[$tempalt SHIFT]], [[7]], [[movetoworkspacesilent]], [[7]])
bind([[bind]], [[$tempalt SHIFT]], [[8]], [[movetoworkspacesilent]], [[8]])
bind([[bind]], [[$tempalt SHIFT]], [[9]], [[movetoworkspacesilent]], [[9]])
bind([[bind]], [[$tempalt SHIFT]], [[0]], [[movetoworkspacesilent]], [[10]])
bind([[bind]], [[$super SHIFT]], [[1]], [[movetoworkspacesilent]], [[1]])
bind([[bind]], [[$super SHIFT]], [[2]], [[movetoworkspacesilent]], [[2]])
bind([[bind]], [[$super SHIFT]], [[3]], [[movetoworkspacesilent]], [[3]])
bind([[bind]], [[$super SHIFT]], [[4]], [[movetoworkspacesilent]], [[4]])
bind([[bind]], [[$super SHIFT]], [[5]], [[movetoworkspacesilent]], [[5]])
bind([[bind]], [[$super SHIFT]], [[6]], [[movetoworkspacesilent]], [[6]])
bind([[bind]], [[$super SHIFT]], [[7]], [[movetoworkspacesilent]], [[7]])
bind([[bind]], [[$super SHIFT]], [[8]], [[movetoworkspacesilent]], [[8]])
bind([[bind]], [[$super SHIFT]], [[9]], [[movetoworkspacesilent]], [[9]])
bind([[bind]], [[$super SHIFT]], [[0]], [[movetoworkspacesilent]], [[10]])

-- Resize (ALT/SUPER+CTRL arrows / hold)
bind([[binde]], [[$tempalt CTRL]], [[right]], [[resizeactive]], [[30 0]])
bind([[binde]], [[$tempalt CTRL]], [[left]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$tempalt CTRL]], [[up]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$tempalt CTRL]], [[down]], [[resizeactive]], [[0 30]])
bind([[binde]], [[$super CTRL]], [[right]], [[resizeactive]], [[30 0]])
bind([[binde]], [[$super CTRL]], [[left]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$super CTRL]], [[up]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$super CTRL]], [[down]], [[resizeactive]], [[0 30]])
-- ALT/SUPER+CTRL hjkl
bind([[binde]], [[$tempalt CTRL]], [[h]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$tempalt CTRL]], [[j]], [[resizeactive]], [[0 30]])
bind([[binde]], [[$tempalt CTRL]], [[k]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$tempalt CTRL]], [[l]], [[resizeactive]], [[30 0]])
bind([[binde]], [[$super CTRL]], [[h]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$super CTRL]], [[j]], [[resizeactive]], [[0 30]])
bind([[binde]], [[$super CTRL]], [[k]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$super CTRL]], [[l]], [[resizeactive]], [[30 0]])

-- Mouse (ALT/SUPER mouse-left/right / hold)
bind([[bindm]], [[$tempalt]], [[mouse:272]], [[movewindow]], [[]])
bind([[bindm]], [[$tempalt]], [[mouse:273]], [[resizewindow]], [[]])
bind([[bindm]], [[$super]], [[mouse:272]], [[movewindow]], [[]])
bind([[bindm]], [[$super]], [[mouse:273]], [[resizewindow]], [[]])

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
bind([[bind]], [[$super $mod]], [[bracketright]], [[exec]], [[$vibrance_shader up]])
bind([[bind]], [[$super $mod]], [[bracketleft]], [[exec]], [[$vibrance_shader down]])
bind([[bind]], [[$super $mod]], [[backslash]], [[exec]], [[$vibrance_shader toggle]])

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
bind([[bind]], [[$super $mod CTRL]], [[1]], [[exec]], [[$workspace_mix toggle 1]])
bind([[bind]], [[$super $mod CTRL]], [[2]], [[exec]], [[$workspace_mix toggle 2]])
bind([[bind]], [[$super $mod CTRL]], [[3]], [[exec]], [[$workspace_mix toggle 3]])
bind([[bind]], [[$super $mod CTRL]], [[4]], [[exec]], [[$workspace_mix toggle 4]])
bind([[bind]], [[$super $mod CTRL]], [[5]], [[exec]], [[$workspace_mix toggle 5]])
bind([[bind]], [[$super $mod CTRL]], [[6]], [[exec]], [[$workspace_mix toggle 6]])
bind([[bind]], [[$super $mod CTRL]], [[7]], [[exec]], [[$workspace_mix toggle 7]])
bind([[bind]], [[$super $mod CTRL]], [[8]], [[exec]], [[$workspace_mix toggle 8]])
bind([[bind]], [[$super $mod CTRL]], [[9]], [[exec]], [[$workspace_mix toggle 9]])
bind([[bind]], [[$super $mod CTRL]], [[0]], [[exec]], [[$workspace_mix toggle 10]])
bind([[bind]], [[$super $mod CTRL]], [[F]], [[exec]], [[$workspace_mix focus]])
bind([[bind]], [[$super $mod CTRL]], [[R]], [[exec]], [[$workspace_mix restore]])

-- Zoom script (SUPER +/-)
bind([[binde]], [[$super]], [[equal]], [[exec]], [[$zoom +]])
bind([[binde]], [[$super]], [[minus]], [[exec]], [[$zoom -]])
bind([[binde]], [[$super SHIFT]], [[equal]], [[exec]], [[$zoom ++]])
bind([[binde]], [[$super SHIFT]], [[minus]], [[exec]], [[$zoom --]])
bind([[bind]], [[$super]], [[backspace]], [[exec]], [[$zoom reset]])
bind([[bind]], [[$super]], [[backslash]], [[exec]], [[$zoom rigid]])
bind([[binde]], [[$super CTRL]], [[equal]], [[exec]], [[$zoom + step:5%]])
bind([[binde]], [[$super CTRL]], [[minus]], [[exec]], [[$zoom - step:5%]])

-- Scratchpad (SUPER+x,X)
bind([[bind]], [[$super]], [[X]], [[togglespecialworkspace]], [[magic]])
bind([[bind]], [[$super SHIFT]], [[X]], [[movetoworkspace]], [[special:magic]])

-- Misc (SUPER+F12)
bind([[bind]], [[$super]], [[F12]], [[exec]], [[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']])
bind([[bind]], [[$super CTRL]], [[F12]], [[exec]], [[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]])

-- Media & Brightness
bind([[bindel]], [[]], [[XF86AudioRaiseVolume]], [[exec]], [[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]])
bind([[bindel]], [[]], [[XF86AudioLowerVolume]], [[exec]], [[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]])
bind([[bindel]], [[]], [[XF86AudioMute]], [[exec]], [[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]])
bind([[bindel]], [[]], [[XF86AudioMicMute]], [[exec]], [[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]])
bind([[bindel]], [[]], [[XF86MonBrightnessUp]], [[exec]], [[brightnessctl -e4 -n2 set 5%+]])
bind([[bindel]], [[]], [[XF86MonBrightnessDown]], [[exec]], [[brightnessctl -e4 -n2 set 5%-]])
bind([[bindl]], [[]], [[XF86AudioPlay]], [[exec]], [[$play_pause]])
bind([[bindl]], [[]], [[XF86AudioNext]], [[exec]], [[playerctl next]])
bind([[bindl]], [[]], [[XF86AudioPrev]], [[exec]], [[playerctl previous]])
bind([[bind]], [[$super]], [[M]], [[exec]], [[$mute_unmute]])

-- Submap binds                        (Toggle on/off)
bind([[bind]], [[$super $mod]], [[N]], [[exec]], [[$noalt_on]])
bind([[bind]], [[$super $mod]], [[M]], [[exec]], [[$mouse_on]])
bind([[bind]], [[$super $mod]], [[V]], [[exec]], [[$vm_on]])

-- ───────────────────────────────────────────────────────────────────────────────
-- noalt SUBMAP; alt is disabled for most tasks
-- ───────────────────────────────────────────────────────────────────────────────
hl.define_submap([[noalt]], function()

-- Submap references in "noalt" (toggle off/on)  [empty file on exit]
set_var([[noalt_off]], [[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']])
set_var([[mouse_on]], [[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']])
set_var([[vm_on]], [[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']])

-- App launchers / terminals in "noalt"
bind([[bind]], [[$mod]], [[P]], [[exec]], [[$app-launcher]])
bind([[bind]], [[$super]], [[D]], [[exec]], [[$app-launcher]])
bind([[bind]], [[$mod SHIFT]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$super SHIFT]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$super]], [[RETURN]], [[exec]], [[$terminal]])
bind([[bind]], [[$mod SHIFT]], [[B]], [[exec]], [[$btop]])
bind([[bind]], [[$super SHIFT]], [[B]], [[exec]], [[$btop]])
bind([[bind]], [[$super]], [[B]], [[exec]], [[$web-browser]])
bind([[bind]], [[$mod SHIFT]], [[C]], [[exec]], [[$calculator]])
bind([[bind]], [[$super SHIFT]], [[C]], [[exec]], [[$calculator]])
bind([[bind]], [[$mod SHIFT]], [[M]], [[exec]], [[$maccel]])
bind([[bind]], [[$super SHIFT]], [[M]], [[exec]], [[$maccel]])

-- Audio mixer in "noalt"
bind([[bind]], [[$mod]], [[V]], [[exec]], [[$wiremix]])
bind([[bind]], [[$super]], [[V]], [[exec]], [[$wiremix]])

-- Mako dismiss in "noalt"
bind([[bind]], [[$mod]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod CTRL]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod SHIFT]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$mod CTRL SHIFT]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bind]], [[$super]], [[SPACE]], [[exec]], [[$mako_dismiss]])

-- Terminal utilities (smtty) in "noalt"
bind([[bind]], [[$super $mod]], [[G]], [[exec]], [[$smtty]])
bind([[bind]], [[$super $mod]], [[L]], [[exec]], [[smtty -S -l]])
bind([[bind]], [[$super $mod]], [[O]], [[exec]], [[$smtty-O]])
bind([[bind]], [[$super $mod]], [[K]], [[exec]], [[smtty -k]])

-- UI / compositor toggles in "noalt"
bind([[bind]], [[$super $mod]], [[T]], [[exec]], [[$hyprbars_toggle]])
bind([[bind]], [[$super $mod]], [[B]], [[exec]], [[$waybar_rotate]])
bind([[bind]], [[$super $mod CTRL]], [[B]], [[exec]], [[$waybar_toggle]])
bind([[bind]], [[$super CTRL]], [[B]], [[exec]], [[$waybar_flip]])
bind([[bind]], [[$super]], [[A]], [[exec]], [[$toggle_animations]])

-- Brightness / color temperature in "noalt"
bind([[bind]], [[$super $mod]], [[backspace]], [[exec]], [[$hypr_quicksettings]])
bind([[bind]], [[$super $mod]], [[equal]], [[exec]], [[$hypr-ddc-brightness up 5]])
bind([[bind]], [[$super $mod]], [[minus]], [[exec]], [[$hypr-ddc-brightness down 5]])
bind([[bind]], [[$super $mod CTRL]], [[equal]], [[exec]], [[$hyprsunset_ctl up]])
bind([[bind]], [[$super $mod CTRL]], [[minus]], [[exec]], [[$hyprsunset_ctl down]])
bind([[bind]], [[$super $mod CTRL]], [[backspace]], [[exec]], [[$hyprsunset_ctl toggle]])

-- File managers / system in "noalt"
bind([[bind]], [[$super]], [[E]], [[exec]], [[pcmanfm-qt]])
bind([[bind]], [[$super SHIFT]], [[E]], [[exec]], [[$yazi]])
bind([[bind]], [[$super]], [[L]], [[exec]], [[hyprlock]])
bind([[bind]], [[$super]], [[I]], [[exec]], [[$hyprpicker]])
bind([[bind]], [[$super]], [[P]], [[exec]], [[$wlogout]])

-- Themes / wallpaper
bind([[bind]], [[$super]], [[W]], [[exec]], [[$wallpicker]])
bind([[bind]], [[$super SHIFT]], [[W]], [[exec]], [[awtwall --random-current]])
bind([[bind]], [[$super CTRL]], [[W]], [[exec]], [[awtwall --random-all]])
bind([[bind]], [[$super $mod]], [[W]], [[exec]], [[awtwall --random-all-different]])
bind([[bind]], [[$super]], [[T]], [[exec]], [[$theme_select]])

-- Capture / clipboard / misc in "noalt"
bind([[bind]], [[$super]], [[C]], [[exec]], [[$clipboard_history]])
bind([[bind]], [[$super]], [[S]], [[exec]], [[$qr_scan]])
bind([[bind]], [[$super SHIFT]], [[S]], [[exec]], [[$screenshot_select]])
bind([[bind]], [[$super SHIFT]], [[F]], [[exec]], [[$screenshot_full]])
bind([[bind]], [[$super SHIFT]], [[D]], [[exec]], [[$screenshot_display]])
bind([[bind]], [[$super SHIFT]], [[G]], [[exec]], [[$gif_capture]])

-- Window management in "noalt"
bind([[bind]], [[$super]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$super SHIFT]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$mod]], [[F4]], [[killactive]], [[]])
bind([[bind]], [[$super $mod]], [[Q]], [[exec]], [[hyprctl kill]])
bind([[bind]], [[$super]], [[Y]], [[pin]], [[]])
bind([[bind]], [[$super SHIFT]], [[R]], [[layoutmsg]], [[togglesplit]])
bind([[bind]], [[$super]], [[R]], [[layoutmsg]], [[swapsplit]])
bind([[bind]], [[$super]], [[F]], [[togglefloating]], [[]])
bind([[bind]], [[$super CTRL]], [[F]], [[fullscreen]], [[]])
bind([[bind]], [[$mod]], [[TAB]], [[cyclenext]], [[]])
bind([[bind]], [[$mod]], [[TAB]], [[bringactivetotop]], [[]])
bind([[bind]], [[$mod SHIFT]], [[TAB]], [[cyclenext]], [[prev]])

-- Focus move in "noalt" (SUPER arrows)
bind([[bind]], [[$super]], [[left]], [[movefocus]], [[l]])
bind([[bind]], [[$super]], [[right]], [[movefocus]], [[r]])
bind([[bind]], [[$super]], [[up]], [[movefocus]], [[u]])
bind([[bind]], [[$super]], [[down]], [[movefocus]], [[d]])
-- SUPER hjkl
bind([[bind]], [[$super]], [[h]], [[movefocus]], [[l]])
bind([[bind]], [[$super]], [[j]], [[movefocus]], [[d]])
bind([[bind]], [[$super]], [[k]], [[movefocus]], [[u]])
bind([[bind]], [[$super]], [[l]], [[movefocus]], [[r]])

-- Window move in "noalt" (SUPER+SHIFT arrows)
bind([[bind]], [[$super SHIFT]], [[left]], [[movewindow]], [[l]])
bind([[bind]], [[$super SHIFT]], [[right]], [[movewindow]], [[r]])
bind([[bind]], [[$super SHIFT]], [[up]], [[movewindow]], [[u]])
bind([[bind]], [[$super SHIFT]], [[down]], [[movewindow]], [[d]])
-- SUPER+SHIFT hjkl
bind([[bind]], [[$super SHIFT]], [[h]], [[movewindow]], [[l]])
bind([[bind]], [[$super SHIFT]], [[j]], [[movewindow]], [[d]])
bind([[bind]], [[$super SHIFT]], [[k]], [[movewindow]], [[u]])
bind([[bind]], [[$super SHIFT]], [[l]], [[movewindow]], [[r]])

-- Send current workspace to monitor in "noalt" (SUPER+CTRL+SHIFT numbers)
bind([[bind]], [[$super CTRL SHIFT]], [[left]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[right]], [[movecurrentworkspacetomonitor]], [[+1]])
bind([[bind]], [[$super CTRL SHIFT]], [[up]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[down]], [[movecurrentworkspacetomonitor]], [[+1]])
-- SUPER+CTRL+SHIFT "[" or "]"
bind([[bind]], [[$super CTRL SHIFT]], [[bracketleft]], [[movecurrentworkspacetomonitor]], [[-1]])
bind([[bind]], [[$super CTRL SHIFT]], [[bracketright]], [[movecurrentworkspacetomonitor]], [[+1]])

-- Workspaces in "noalt" (SUPER numbers)
bind([[bind]], [[$super]], [[1]], [[workspace]], [[1]])
bind([[bind]], [[$super]], [[2]], [[workspace]], [[2]])
bind([[bind]], [[$super]], [[3]], [[workspace]], [[3]])
bind([[bind]], [[$super]], [[4]], [[workspace]], [[4]])
bind([[bind]], [[$super]], [[5]], [[workspace]], [[5]])
bind([[bind]], [[$super]], [[6]], [[workspace]], [[6]])
bind([[bind]], [[$super]], [[7]], [[workspace]], [[7]])
bind([[bind]], [[$super]], [[8]], [[workspace]], [[8]])
bind([[bind]], [[$super]], [[9]], [[workspace]], [[9]])
bind([[bind]], [[$super]], [[0]], [[workspace]], [[10]])

-- Prev/next workspace with (SUPER "[" or "]")
bind([[bind]], [[$super]], [[bracketleft]], [[workspace]], [[-1]])
bind([[bind]], [[$super]], [[bracketright]], [[workspace]], [[+1]])

-- Move window to workspace in "noalt" (SUPER+SHIFT numbers)
bind([[bind]], [[$super SHIFT]], [[1]], [[movetoworkspacesilent]], [[1]])
bind([[bind]], [[$super SHIFT]], [[2]], [[movetoworkspacesilent]], [[2]])
bind([[bind]], [[$super SHIFT]], [[3]], [[movetoworkspacesilent]], [[3]])
bind([[bind]], [[$super SHIFT]], [[4]], [[movetoworkspacesilent]], [[4]])
bind([[bind]], [[$super SHIFT]], [[5]], [[movetoworkspacesilent]], [[5]])
bind([[bind]], [[$super SHIFT]], [[6]], [[movetoworkspacesilent]], [[6]])
bind([[bind]], [[$super SHIFT]], [[7]], [[movetoworkspacesilent]], [[7]])
bind([[bind]], [[$super SHIFT]], [[8]], [[movetoworkspacesilent]], [[8]])
bind([[bind]], [[$super SHIFT]], [[9]], [[movetoworkspacesilent]], [[9]])
bind([[bind]], [[$super SHIFT]], [[0]], [[movetoworkspacesilent]], [[10]])

-- Resize in "noalt" (SUPER+CTRL arrows / hold)
bind([[binde]], [[$super CTRL]], [[right]], [[resizeactive]], [[30 0]])
bind([[binde]], [[$super CTRL]], [[left]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$super CTRL]], [[up]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$super CTRL]], [[down]], [[resizeactive]], [[0 30]])
-- SUPER+CTRL hjkl
bind([[binde]], [[$super CTRL]], [[h]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[$super CTRL]], [[j]], [[resizeactive]], [[0 30]])
bind([[binde]], [[$super CTRL]], [[k]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[$super CTRL]], [[l]], [[resizeactive]], [[30 0]])

-- Mouse in "noalt" (SUPER mouse-left/right / hold)
bind([[bindm]], [[$super]], [[mouse:272]], [[movewindow]], [[]])
bind([[bindm]], [[$super]], [[mouse:273]], [[resizewindow]], [[]])

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
bind([[bind]], [[$super $mod]], [[bracketright]], [[exec]], [[$vibrance_shader up]])
bind([[bind]], [[$super $mod]], [[bracketleft]], [[exec]], [[$vibrance_shader down]])
bind([[bind]], [[$super $mod]], [[backslash]], [[exec]], [[$vibrance_shader toggle]])

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
bind([[bind]], [[$super $mod CTRL]], [[1]], [[exec]], [[$workspace_mix toggle 1]])
bind([[bind]], [[$super $mod CTRL]], [[2]], [[exec]], [[$workspace_mix toggle 2]])
bind([[bind]], [[$super $mod CTRL]], [[3]], [[exec]], [[$workspace_mix toggle 3]])
bind([[bind]], [[$super $mod CTRL]], [[4]], [[exec]], [[$workspace_mix toggle 4]])
bind([[bind]], [[$super $mod CTRL]], [[5]], [[exec]], [[$workspace_mix toggle 5]])
bind([[bind]], [[$super $mod CTRL]], [[6]], [[exec]], [[$workspace_mix toggle 6]])
bind([[bind]], [[$super $mod CTRL]], [[7]], [[exec]], [[$workspace_mix toggle 7]])
bind([[bind]], [[$super $mod CTRL]], [[8]], [[exec]], [[$workspace_mix toggle 8]])
bind([[bind]], [[$super $mod CTRL]], [[9]], [[exec]], [[$workspace_mix toggle 9]])
bind([[bind]], [[$super $mod CTRL]], [[0]], [[exec]], [[$workspace_mix toggle 10]])
bind([[bind]], [[$super $mod CTRL]], [[F]], [[exec]], [[$workspace_mix focus]])
bind([[bind]], [[$super $mod CTRL]], [[R]], [[exec]], [[$workspace_mix restore]])

-- Zoom script in "noalt" (SUPER +/-)
bind([[binde]], [[$super]], [[equal]], [[exec]], [[$zoom +]])
bind([[binde]], [[$super]], [[minus]], [[exec]], [[$zoom -]])
bind([[binde]], [[$super SHIFT]], [[equal]], [[exec]], [[$zoom ++]])
bind([[binde]], [[$super SHIFT]], [[minus]], [[exec]], [[$zoom --]])
bind([[bind]], [[$super]], [[backspace]], [[exec]], [[$zoom reset]])
bind([[bind]], [[$super]], [[backslash]], [[exec]], [[$zoom rigid]])
bind([[binde]], [[$super CTRL]], [[equal]], [[exec]], [[$zoom + step:5%]])
bind([[binde]], [[$super CTRL]], [[minus]], [[exec]], [[$zoom - step:5%]])

-- Scratchpad in "noalt" (SUPER+x,X)
bind([[bind]], [[$super]], [[X]], [[togglespecialworkspace]], [[magic]])
bind([[bind]], [[$super SHIFT]], [[X]], [[movetoworkspace]], [[special:magic]])

-- Misc in "noalt" (SUPER+F12)
bind([[bind]], [[$super]], [[F12]], [[exec]], [[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']])
bind([[bind]], [[$super CTRL]], [[F12]], [[exec]], [[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]])

-- Media & Brightness
bind([[bindel]], [[]], [[XF86AudioRaiseVolume]], [[exec]], [[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]])
bind([[bindel]], [[]], [[XF86AudioLowerVolume]], [[exec]], [[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]])
bind([[bindel]], [[]], [[XF86AudioMute]], [[exec]], [[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]])
bind([[bindel]], [[]], [[XF86AudioMicMute]], [[exec]], [[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]])
bind([[bindel]], [[]], [[XF86MonBrightnessUp]], [[exec]], [[brightnessctl -e4 -n2 set 5%+]])
bind([[bindel]], [[]], [[XF86MonBrightnessDown]], [[exec]], [[brightnessctl -e4 -n2 set 5%-]])
bind([[bindl]], [[]], [[XF86AudioPlay]], [[exec]], [[$play_pause]])
bind([[bindl]], [[]], [[XF86AudioNext]], [[exec]], [[playerctl next]])
bind([[bindl]], [[]], [[XF86AudioPrev]], [[exec]], [[playerctl previous]])
bind([[bind]], [[$super]], [[M]], [[exec]], [[$mute_unmute]])

-- Submap binds in "noalt"             (Toggle off/on)
bind([[bind]], [[$super $mod]], [[N]], [[exec]], [[$noalt_off]])
bind([[bind]], [[$super $mod]], [[M]], [[exec]], [[$mouse_on]])
bind([[bind]], [[$super $mod]], [[V]], [[exec]], [[$vm_on]])
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- MOUSE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────
hl.define_submap([[mouse]], function()

-- Submap references in "mouse" (Toggle off)  [empty file on exit]
set_var([[mouse_off]], [[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']])

-- Resize (MOUSE-left/right / hold)
bind([[binde]], [[]], [[h]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[]], [[j]], [[resizeactive]], [[0 30]])
bind([[binde]], [[]], [[k]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[]], [[l]], [[resizeactive]], [[30 0]])
bind([[binde]], [[]], [[left]], [[resizeactive]], [[-30 0]])
bind([[binde]], [[]], [[down]], [[resizeactive]], [[0 30]])
bind([[binde]], [[]], [[up]], [[resizeactive]], [[0 -30]])
bind([[binde]], [[]], [[right]], [[resizeactive]], [[30 0]])
bind([[bindm]], [[]], [[mouse:272]], [[movewindow]], [[]])
bind([[bindm]], [[]], [[mouse:273]], [[resizewindow]], [[]])
bind([[bind]], [[]], [[mouse:274]], [[togglefloating]], [[]])
bind([[bind]], [[]], [[Escape]], [[exec]], [[$mouse_off reset]])
bind([[bind]], [[]], [[Return]], [[exec]], [[$mouse_off reset]])

-- Submap binds in "mouse"  (Toggle off/on)
bind([[bind]], [[$super $mod]], [[M]], [[exec]], [[$mouse_off]])
bind([[bind]], [[$super $mod]], [[N]], [[exec]], [[$noalt_on]])
bind([[bind]], [[$super $mod]], [[V]], [[exec]], [[$vm_on]])
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- VIRTUAL MACHINE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────
hl.define_submap([[vm]], function()

-- Submap references in "vm" (Toggle off)  [empty file on exit]
set_var([[vm_off]], [[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']])

-- Binds
bind([[bind]], [[$super $mod]], [[Q]], [[killactive]], [[]])
bind([[bind]], [[$super $mod]], [[F]], [[togglefloating]], [[]])
bind([[bind]], [[$super $mod]], [[P]], [[exec]], [[$app-launcher]])
bind([[bind]], [[$super $mod]], [[C]], [[exec]], [[$calculator]])
bind([[bind]], [[$super $mod CTRL]], [[V]], [[exec]], [[$wiremix]])
bind([[bind]], [[$super $mod CTRL]], [[S]], [[exec]], [[$qr_scan]])
bind([[bind]], [[$super $mod]], [[S]], [[exec]], [[$screenshot_select]])
bind([[bind]], [[$super $mod]], [[D]], [[exec]], [[$screenshot_display]])
bind([[bind]], [[$super $mod]], [[G]], [[exec]], [[$gif_capture]])
bind([[bind]], [[$super $mod]], [[RETURN]], [[exec]], [[$terminal]])
bind([[binde]], [[$super $mod]], [[SPACE]], [[exec]], [[$mako_dismiss]])
bind([[bindm]], [[$super $mod]], [[mouse:272]], [[movewindow]], [[]])
bind([[bindm]], [[$super $mod]], [[mouse:273]], [[resizewindow]], [[]])
bind([[bind]], [[$super $mod]], [[mouse:274]], [[togglefloating]], [[]])

-- Workspaces (SUPER+ALT numbers)
bind([[bind]], [[$super $mod]], [[1]], [[workspace]], [[1]])
bind([[bind]], [[$super $mod]], [[2]], [[workspace]], [[2]])
bind([[bind]], [[$super $mod]], [[3]], [[workspace]], [[3]])
bind([[bind]], [[$super $mod]], [[4]], [[workspace]], [[4]])
bind([[bind]], [[$super $mod]], [[5]], [[workspace]], [[5]])
bind([[bind]], [[$super $mod]], [[6]], [[workspace]], [[6]])
bind([[bind]], [[$super $mod]], [[7]], [[workspace]], [[7]])
bind([[bind]], [[$super $mod]], [[8]], [[workspace]], [[8]])
bind([[bind]], [[$super $mod]], [[9]], [[workspace]], [[9]])
bind([[bind]], [[$super $mod]], [[0]], [[workspace]], [[10]])

-- Move window to workspace (SUPER+ALT+SHIFT numbers)
bind([[bind]], [[$super $mod SHIFT]], [[1]], [[movetoworkspacesilent]], [[1]])
bind([[bind]], [[$super $mod SHIFT]], [[2]], [[movetoworkspacesilent]], [[2]])
bind([[bind]], [[$super $mod SHIFT]], [[3]], [[movetoworkspacesilent]], [[3]])
bind([[bind]], [[$super $mod SHIFT]], [[4]], [[movetoworkspacesilent]], [[4]])
bind([[bind]], [[$super $mod SHIFT]], [[5]], [[movetoworkspacesilent]], [[5]])
bind([[bind]], [[$super $mod SHIFT]], [[6]], [[movetoworkspacesilent]], [[6]])
bind([[bind]], [[$super $mod SHIFT]], [[7]], [[movetoworkspacesilent]], [[7]])
bind([[bind]], [[$super $mod SHIFT]], [[8]], [[movetoworkspacesilent]], [[8]])
bind([[bind]], [[$super $mod SHIFT]], [[9]], [[movetoworkspacesilent]], [[9]])
bind([[bind]], [[$super $mod SHIFT]], [[0]], [[movetoworkspacesilent]], [[10]])

-- Submap binds in "vm"            (Toggle off/on)
bind([[bind]], [[$super $mod]], [[V]], [[exec]], [[$vm_off]])
bind([[bind]], [[$super $mod]], [[M]], [[exec]], [[$mouse_on]])
bind([[bind]], [[$super $mod]], [[N]], [[exec]], [[$noalt_on]])
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- RULES
-- ───────────────────────────────────────────────────────────────────────────────

-- Games: send to workspace 1, strip effects, fullscreen, allow tearing, keep awake
-- Note: Proton/Wine windows often have class like "game.exe" (not "Wine"), so we also match *.exe.
set_var([[games]], [[^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$]])
-- Mark these windows as "game" content type so render:direct_scanout=2 can auto-engage
rule([[match:class $games, content game]], false)
-- other $games window rules
rule([[match:class $games, workspace 1 silent]], false)
rule([[match:class $games, no_anim on]], false)
rule([[match:class $games, no_blur on]], false)
rule([[match:class $games, no_shadow on]], false)
rule([[match:class $games, decorate off]], false)
rule([[match:class $games, border_size 0]], false)
rule([[match:class $games, rounding 0]], false)
rule([[match:class $games, fullscreen on]], false)
rule([[match:class $games, immediate on]], false)
rule([[match:class $games, idle_inhibit always]], false)

-- Workspace auto-assignments
rule([[match:class ^(firefox|librewolf|Mullvad Browser|Cromite|brave-browser|io\.github\.ungoogled_software\.ungoogled_chromium)$, workspace 2 silent]], false)
rule([[match:class ^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|brave-app\.revolt\.chat__-.*|chat\.revolt\.RevoltDesktop|info\.mumble\.Mumble|fluxer|Fluxer)$, workspace 3 silent]], false)
rule([[match:class ^(steam|com\.valvesoftware\.Steam|SteamChat|net\.lutris\.Lutris|itch|io\.itch\.itch|heroic|com\.heroicgameslauncher\.hgl|r2modman)$, workspace 4 silent]], false)
rule([[match:class ^(Spotify|com\.spotify\.Client|brave-music\.youtube\.com__-.*)$, workspace 5 silent]], false)
rule([[match:title ^(.*YouTube Music.*)$, workspace 5 silent]], false)
rule([[match:class ^(org\.telegram\.desktop|brave-web\.telegram\.org__a_-.*|brave-messages\.google\.com__-.*)$, workspace 6 silent]], false)
rule([[match:title ^(Telegram Web)$, workspace 6 silent]], false)
rule([[match:class ^(Messages)$, workspace 6 silent]], false)
rule([[match:class ^(Telegram)$, workspace 6 silent]], false)
rule([[match:class ^(Vncviewer|rustdesk)$, workspace 7 silent]], false)
rule([[match:class ^(com\.github\.IsmaelMartinez\.teams_for_linux)$, workspace 8 silent]], false)
rule([[match:class ^(kdenlive|org\.kde\.kdenlive|org\.shotcut\.Shotcut|krita|org\.kde\.krita)$, workspace 9 silent]], false)
rule([[match:class ^(obs|com\.obsproject\.Studio|gpu-screen-recorder|gpu-screen-recorder-gtk|gpu-screen-recorder-ui|gsr-ui|com\.dec05eba\.gpu_screen_recorder)$, workspace 10 silent]], false)

-- Global behavior / XWayland quirks
rule([[match:class .*, suppress_event maximize]], false)
rule([[match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0, no_focus on]], false)
rule([[match:xwayland 1, no_blur on]], false)
rule([[match:class ^(steam)$, match:title ^$, stay_focused on]], false)
rule([[match:class ^(steam)$, match:title ^$, min_size 1 1]], false)

-- Picture-in-Picture
set_var([[pip]], [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]])
rule([[match:title $pip, float on]], false)
rule([[match:title $pip, keep_aspect_ratio on]], false)
rule([[match:title $pip, move (monitor_w*0.73) (monitor_h*0.70)]], false)
rule([[match:title $pip, size (monitor_w*0.25) (monitor_h*0.25)]], false)
rule([[match:title $pip, pin on]], false)

-- Dialogs float+center
set_var([[dialogs]], [[^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload)(.*)$]])
rule([[match:title $dialogs, float on]], false)
rule([[match:title $dialogs, center on]], false)

-- Transparency
rule([[match:class ^(wofi)$, opacity 0.85 0.85]], false)
rule([[match:class ^(Spotify)$, opacity 0.85 0.85]], false)
rule([[match:title ^(YouTube Music|YouTube Music - .+ - YouTube Music|YouTube Music - 1\. YouTube Music)$, opacity 0.85 0.85]], false)
rule([[match:class ^(com\.github\.th_ch\.youtube_music|brave-music\.youtube\.com__-.*)$, opacity 0.85 0.85]], false)
rule([[match:class ^(pcmanfm-qt|localsend|org\.pulseaudio\.pavucontrol|org\.speedcrunch\.speedcrunch|net\.davidotek\.pupgui2|wallpicker)$, opacity 0.95 0.95]], false)

-- Float + size + center
rule([[match:class ^org\.speedcrunch\.speedcrunch$, float on]], false)
rule([[match:class ^org\.speedcrunch\.speedcrunch$, size (monitor_w*0.15) (monitor_h*0.55)]], false)
rule([[match:class ^org\.speedcrunch\.speedcrunch$, center on]], false)

rule([[match:class ^org\.pulseaudio\.pavucontrol$, float on]], false)
rule([[match:class ^org\.pulseaudio\.pavucontrol$, size (monitor_w*0.55) (monitor_h*0.70)]], false)
rule([[match:class ^org\.pulseaudio\.pavucontrol$, center on]], false)

rule([[match:class ^(Pulsemixer)$, float on]], false)
rule([[match:class ^(Pulsemixer)$, size (monitor_w*0.55) (monitor_h*0.70)]], false)
rule([[match:class ^(Pulsemixer)$, center on]], false)

rule([[match:class ^(Wiremix)$, float on]], false)
rule([[match:class ^(Wiremix)$, size (monitor_w*0.65) (monitor_h*0.70)]], false)
rule([[match:class ^(Wiremix)$, center on]], false)

rule([[match:class ^(hypr_quicksettings)$, float on]], false)
rule([[match:class ^(hypr_quicksettings)$, size (monitor_w*0.70) (monitor_h*0.40)]], false)
rule([[match:class ^(hypr_quicksettings)$, center on]], false)

rule([[match:class ^(awtarchy-tips-tui)$, float on]], false)
rule([[match:class ^(awtarchy-tips-tui)$, size (monitor_w*0.50) (monitor_h*0.50)]], false)
rule([[match:class ^(awtarchy-tips-tui)$, center on]], false)

rule([[match:class ^(maccel)$, float on]], false)
rule([[match:class ^(maccel)$, size (monitor_w*0.90) (monitor_h*0.96)]], false)
rule([[match:class ^(maccel)$, center on]], false)

rule([[match:class ^(hyprbars)$, float on]], false)
rule([[match:class ^(hyprbars)$, size (monitor_w*0.30) (monitor_h*0.10)]], false)
rule([[match:class ^(hyprbars)$, center on]], false)

rule([[match:class ^(smtty)$, float on]], false)
rule([[match:class ^(smtty)$, size (monitor_w*0.80) (monitor_h*0.88)]], false)
rule([[match:class ^(smtty)$, center on]], false)

rule([[match:class ^(smtty-O)$, float on]], false)
rule([[match:class ^(smtty-O)$, size (monitor_w*0.50) (monitor_h*0.50)]], false)
rule([[match:class ^(smtty-O)$, center on]], false)

rule([[match:class ^(wallpicker)$, float on]], false)
rule([[match:class ^(wallpicker)$, size (monitor_w*0.85) (monitor_h*0.90)]], false)
rule([[match:class ^(wallpicker)$, center on]], false)

rule([[match:class ^(nm-connection-editor)$, float on]], false)
rule([[match:class ^(nm-connection-editor)$, size (monitor_w*0.45) (monitor_h*0.45)]], false)
rule([[match:class ^(nm-connection-editor)$, center on]], false)

rule([[match:class ^(blueman-manager)$, float on]], false)
rule([[match:class ^(blueman-manager)$, size (monitor_w*0.45) (monitor_h*0.45)]], false)
rule([[match:class ^(blueman-manager)$, center on]], false)

rule([[match:class ^(net\.davidotek\.pupgui2)$, float on]], false)
rule([[match:class ^(net\.davidotek\.pupgui2)$, size (monitor_w*0.45) (monitor_h*0.45)]], false)
rule([[match:class ^(net\.davidotek\.pupgui2)$, center on]], false)

rule([[match:class ^(btop)$, float on]], false)
rule([[match:class ^(btop)$, size (monitor_w*0.80) (monitor_h*0.85)]], false)
rule([[match:class ^(btop)$, center on]], false)

-- Force Tile
rule([[match:class ^(steam|com\.valvesoftware\.Steam)$, match:title ^(Steam)$, tile on]], false)
rule([[match:class ^(steam|com\.valvesoftware\.Steam)$, match:title ^(Friends List)$, tile on]], false)

-- ───────────────────────────────────────────────────────────────────────────────
-- SCREENSHARE GUARD
-- ───────────────────────────────────────────────────────────────────────────────

rule([[no_screen_share on,      match:class ^(Bitwarden|com\.bitwarden\.desktop|KeePassXC|org\.keepassxc\.KeePassXC|1Password|com\.1password\.1password|Enpass|org\.gnome\.Secrets|org\.gnome\.seahorse\.Application|OTPClient|otpclient|org\.rasalminen\.OTPClient|Mullvad Browser|mullvad-browser|com\.mullvad\.Browser|localsend|LocalSend|org\.localsend\.localsend|io\.github\.localsend\.localsend)$]], false)
rule([[no_screen_share on,      match:class ^(firefox)$, match:title ^(Extension: \(Bitwarden Password Manager\).*)$]], false)
rule([[no_screen_share on,      match:class ^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$, match:title ^(Bitwarden Password Manager.*)$]], false)
rule([[no_screen_share on,      match:class ^(org\.telegram\.desktop|TelegramDesktop|telegram-desktop|Telegram)$]], false)
rule([[no_screen_share on,      match:class ^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$, match:title ^.*Telegram.*$]], false)
rule([[no_screen_share on,      match:class ^(Element|io\.element\.Element|im\.riot\.Riot|chat\.element\.desktop|SchildiChat|im\.fluffychat\.Fluffychat|Fractal|org\.gnome\.Fractal|nheko)$]], false)
rule([[no_screen_share on,      match:class ^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|Fluxer|fluxer)$]], false)
rule([[no_screen_share on,      match:class ^(com\.github\.IsmaelMartinez\.teams_for_linux)$]], false)
rule([[no_screen_share on,      match:class ^(Messages)$]], false)

-- Layers (notifications/swaync are layer surfaces, not windows)
rule([[no_screen_share on,      match:namespace ^(notifications|swaync.*)$]], true)

-- optional
-- windowrule = no_screen_share on,    match:class ^(obs|com\.obsproject\.Studio|obs-studio|com\.obsproject\.Studio\.obs)$
-- windowrule = no_screen_share on,    match:class ^(steam|com\.valvesoftware\.Steam)$
-- windowrule = no_screen_share on,    match:class ^(rustdesk|com\.rustdesk\.RustDesk)$
-- windowrule = no_screen_share on,    match:class ^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$
-- windowrule = no_screen_share on,    match:class ^(wallpicker)$
-- windowrule = no_screen_share on,    match:class ^(virt-manager)$
-- windowrule = no_screen_share on,    match:class ^(Alacritty)$
-- windowrule = no_screen_share on,    match:class ^(mpv)$
-- layerrule  = no_screen_share on,    match:namespace ^(ags)$
-- layerrule  = no_screen_share on,    match:namespace ^(logout_dialog)$
-- layerrule  = no_screen_share on,    match:namespace ^(waybar)$

-- ───────────────────────────────────────────────────────────────────────────────
-- MANUAL SETUP
-- ───────────────────────────────────────────────────────────────────────────────

-- Sunshine / Moonlight Fix
-- Configure in Sunshine Web-UI → “Do Command” (on connect):
--   /usr/bin/env bash -lc "$HOME/.config/hypr/scripts/sunshine-moonlight-fix.sh"
-- READ SCRIPT:        cat ~/.config/hypr/scripts/sunshine-moonlight-fix.sh

-- ───────────────────────────────────────────────────────────────────────────────
-- .DESKTOP NOTES
-- ───────────────────────────────────────────────────────────────────────────────

-- ~/.local/share/applications/*

-- Steam Splitratio Script
-- Set split ratio between Steam and Friends List (runs once at startup with a timeout of 300s)
-- READ SCRIPT:        cat ~/.config/hypr/scripts/splitratio_steam.sh
-- .desktop override:  Exec=sh -lc 'pgrep -x steam >/dev/null && exit 0; /usr/bin/steam --disable-gpu "$@" & ALLOW_WAIT=1 "$HOME/.config/hypr/scripts/splitratio_steam.sh" &' _ %U
-- Check file:         cat ~/.local/share/applications/steam.desktop
