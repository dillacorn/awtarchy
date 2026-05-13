-- ~/.config/hypr/hyprland.lua
-- Clean Hyprland Lua config for Hyprland 0.55+.
-- Hyprlang compatibility helpers live in ~/.config/hypr/hyprlang.lua.

dofile(os.getenv("HOME") .. "/.config/hypr/hyprlang.lua")

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

monitor(",preferred,auto,auto,vrr,0")
monitor([=[Virtual-1,1600x900@60,auto,1,vrr,0]=])


-- ───────────────────────────────────────────────────────────────────────────────
-- ENV
-- ───────────────────────────────────────────────────────────────────────────────

env("XDG_CURRENT_DESKTOP,Hyprland")
env("XDG_SESSION_DESKTOP,Hyprland")
env("XDG_SESSION_TYPE,wayland")
env([=[GDK_BACKEND,wayland,x11,*]=])
env([=[QT_QPA_PLATFORM,wayland;xcb]=])
env("CLUTTER_BACKEND,wayland")
env("QT_STYLE_OVERRIDE,kvantum")
env("QT_AUTO_SCREEN_SCALE_FACTOR,1")
env("QT_WAYLAND_DISABLE_WINDOWDECORATION,1")
env("QT_QPA_PLATFORMTHEME,qt5ct")
env("QT6CT_PLATFORM_PLUGIN,qt6ct")
env("QT_QUICK_CONTROLS_STYLE,org.hyprland.style")
env("MOZ_ENABLE_WAYLAND,1")
env("GDK_SCALE,1")
env("QT_SCALE_FACTOR,1")
env("XCURSOR_SIZE,24")
env("GTK_THEME,Materia-dark")
env("XCURSOR_THEME,ComixCursors-White")
env("GAMESCOPE_WSI,vk_wayland")

-- Optional/problem-specific environment toggles.
-- env("WLR_RENDERER_ALLOW_SOFTWARE,0")
-- env("WLR_DRM_NO_ATOMIC,1") -- Can help with some GPUs
-- env("HYPRLAND_NO_RT,1") -- Disable realtime scheduling if having issues
-- env("__GL_GSYNC_ALLOWED,1")
-- env("__GL_VRR_ALLOWED,1")

-- NVIDIA/proprietary-driver-specific toggles.
-- env("__GLX_VENDOR_LIBRARY_NAME,nvidia") -- NVIDIA GLX vendor
-- env("LIBVA_DRIVER_NAME,nvidia") -- NVIDIA VA-API driver
-- env("GBM_BACKEND,nvidia-drm") -- NVIDIA GBM backend


-- ───────────────────────────────────────────────────────────────────────────────
-- PERMISSIONS (requires Hyprland restart after edits)
-- ───────────────────────────────────────────────────────────────────────────────

-- Add future apps (getting the correct path/regex):
-- 1) Best: when Hyprland prompts, copy the binary path it shows and paste it into:
--
-- 2) If you know the command name (replace `grim` with your app):
--    readlink -f "$(command -v grim)"
--
-- 3) If the app has a window open: focus it, then run:
--
-- Keyboard device names (for `keyboard` rules):
--   hyprctl devices

    cfg({"ecosystem"}, "no_update_news", "true")
    cfg({"ecosystem"}, "enforce_permissions", "true")

-- screencopy (direct capture)
permission("/usr/bin/grim, screencopy, allow")
permission("/usr/bin/wf-recorder, screencopy, allow")
permission("/usr/bin/hyprpicker, screencopy, allow")
permission("/usr/bin/hyprlock, screencopy, allow")
permission([=[/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland, screencopy, allow]=])

-- plugin (hyprpm)
permission([=[/usr/(bin|local/bin)/hyprpm, plugin, allow]=])

-- keyboard allowlist template (default is allow)
-- permission("^(YOUR KEYBOARD NAME REGEX)$, keyboard, allow")
-- permission(".*, keyboard, deny")

-- ───────────────────────────────────────────────────────────────────────────────
-- AUTOSTART
-- ───────────────────────────────────────────────────────────────────────────────

exec_once("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")
exec_once("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")

exec_once([=[sh -lc '$HOME/.config/hypr/scripts/portal_fixup.sh']=])
exec_once("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
exec_once("gnome-keyring-daemon --start --password-store=secrets")

-- exec_once("~/.config/hypr/scripts/last_to_load_recorder.sh &")
exec_once("~/.config/hypr/scripts/waybar.sh start &")
exec_once("~/.config/hypr/scripts/waybar_ready_sound.sh &")

exec_once("hyprsunset &")
exec_once("mako &")
exec_once("nm-applet &")
exec_once("blueman-applet &")
exec_once("nwg-look -a &")
exec_once("hypridle -c ~/.config/hypr/hypridle.conf &")
exec_once("~/.config/hypr/scripts/hyprpm-auto-reload.sh &")
exec_once("~/.config/hypr/scripts/awtwall-awtarchy-init.sh &")
-- exec_once("~/.config/hypr/scripts/wallpaper_engine.sh &")
exec_once([=[sh -lc 'exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e "$HOME/.config/hypr/scripts/awtarchy-tips-tui.sh" --autostart']=])
-- exec_once("~/.config/hypr/scripts/miclock.sh &")
exec_once("wl-paste --type text --watch cliphist store &")
exec_once("wl-paste --type image --watch cliphist store &")

-- Optional: USB refresh helper
-- List USB devices:
-- lsusb
-- Map a device once:
-- ~/.config/hypr/scripts/usb_refresh_fixer.sh map 20b1:3008 ifi
--
-- Then optionally run at startup:
--
-- Non-audio USB device:
-- exec_once("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh myusb &")
--
-- USB audio device, just refresh it and wait for the audio sink to exist again:
-- exec_once("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio ifi &")
--
-- USB audio device, refresh it and force it as default sink:
-- exec_once("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio-default ifi &")

-- ───────────────────────────────────────────────────────────────────────────────
-- LOOK & FEEL
-- ───────────────────────────────────────────────────────────────────────────────

    cfg({"general"}, "gaps_in", "6")
    cfg({"general"}, "gaps_out", "9")
    cfg({"general"}, "border_size", "1")
cfg({"general"}, "col.active_border", "rgba(a0a0a0ff)")
cfg({"general"}, "col.inactive_border", "rgba(4b4b4bff)")
    cfg({"general"}, "resize_on_border", "true")
    cfg({"general"}, "allow_tearing", "true")
    cfg({"general"}, "layout", "dwindle")

    cfg({"decoration"}, "rounding", "0")
    cfg({"decoration"}, "rounding_power", "2")
    cfg({"decoration"}, "active_opacity", "1.0")
    cfg({"decoration"}, "inactive_opacity", "1.0")

    -- Shaders (uncomment only one)
    -- screen_shader = ~/.config/hypr/shaders/vibrance
    -- screen_shader = ~/.config/hypr/shaders/cathode_ray_tube_optional_vibrance
    -- screen_shader = ~/.config/hypr/shaders/subtle_crt
    -- screen_shader = ~/.config/hypr/shaders/gimmicky-crt

    -- Shaders that require debug damage_tracking = 0 or you will see config errors.
    -- screen_shader = ~/.config/hypr/shaders/vhs
    -- screen_shader = ~/.config/hypr/shaders/acid_trip

        cfg({"decoration", "shadow"}, "enabled", "true")
        cfg({"decoration", "shadow"}, "range", "4")
        cfg({"decoration", "shadow"}, "render_power", "3")
        cfg({"decoration", "shadow"}, "color", "rgba(1a1a1aee)")

        cfg({"decoration", "blur"}, "enabled", "true")
        cfg({"decoration", "blur"}, "size", "3")
        cfg({"decoration", "blur"}, "passes", "1")
        cfg({"decoration", "blur"}, "vibrancy", "0.1696")

    cfg({"debug"}, "damage_tracking", "2")

    -- Direct scanout: 0 = off, 1 = on, 2 = auto (only when content_type == "game")
    -- Reduces latency when a single fullscreen client (e.g. nested gamescope) owns the monitor.
    cfg({"render"}, "direct_scanout", "2")

    -- Non-shader color management:
    -- 2 is the “DS + passthrough only” mode, which pairs cleanly with gamescope.
    cfg({"render"}, "non_shader_cm", "2")

    -- Fullscreen HDR color-management auto-switch:
    -- cm_fs_passthrough was removed in Hyprland 0.55.
    cfg({"render"}, "cm_auto_hdr", "1")


-- opengl {
--     nvidia_anti_flicker = true
-- }

    cfg({"cursor"}, "sync_gsettings_theme", "true")
    cfg({"cursor"}, "no_hardware_cursors", "2")
    cfg({"cursor"}, "zoom_disable_aa", "true")
    cfg({"cursor"}, "no_warps", "false")
    cfg({"cursor"}, "persistent_warps", "false")
    cfg({"cursor"}, "warp_on_change_workspace", "0")
    cfg({"cursor"}, "enable_hyprcursor", "true")

    cfg({"animations"}, "enabled", "yes")
    curve("easeOutQuint, 0.23, 1, 0.32, 1")
    curve("easeInOutSlight, 0.4, 0.1, 0.2, 1")
    curve("linear, 0, 0, 1, 1")
    curve("softFade, 0.2, 0.5, 0.3, 1")
    curve("fastOut, 0.2, 0, 0.6, 1")
    animation("global, 1, 8, default")
    animation("border, 1, 3.0, easeOutQuint")
    animation("borderangle, 1, 40, linear, once")
    animation("windows, 1, 3.0, easeOutQuint")
    animation([=[windowsIn, 1, 2.0, easeOutQuint, popin 87%]=])
    animation([=[windowsOut, 1, 1.5, linear, popin 87%]=])
    animation("fadeIn, 1, 1.5, softFade")
    animation("fadeOut, 1, 1.3, softFade")
    animation("fade, 1, 2.0, softFade")
    animation("layers, 1, 2.5, easeInOutSlight")
    animation("layersIn, 1, 2.0, easeInOutSlight, fade")
    animation("layersOut, 1, 1.5, fastOut, fade")
    animation("fadeLayersIn, 1, 1.4, softFade")
    animation("fadeLayersOut, 1, 1.3, softFade")
    animation("workspaces, 1, 1.8, easeInOutSlight, fade")
    animation("workspacesIn, 1, 1.3, softFade, fade")
    animation("workspacesOut, 1, 1.4, softFade, fade")
    animation("specialWorkspace, 1, 1.9, easeInOutSlight, fade")

    cfg({"dwindle"}, "preserve_split", "true")
    cfg({"dwindle"}, "force_split", "0")
    cfg({"dwindle"}, "special_scale_factor", "0.9")
    -- cfg({"dwindle"}, "smart_split", "true")
    -- cfg({"dwindle"}, "single_window_aspect_ratio", "1 0.6852")

    cfg({"master"}, "new_status", "master")
    cfg({"master"}, "new_on_top", "1")
    cfg({"master"}, "mfact", "0.5")

    -- Visuals (startup / defaults)
    cfg({"misc"}, "force_default_wallpaper", "-1")
    cfg({"misc"}, "disable_hyprland_logo", "true")
    cfg({"misc"}, "disable_splash_rendering", "true")

    -- Rendering / display behavior
    cfg({"misc"}, "vrr", "2")
    cfg({"misc"}, "mouse_move_enables_dpms", "true")

    -- Input convenience
    cfg({"misc"}, "middle_click_paste", "false")

    -- Focus / workspace behavior
    cfg({"misc"}, "focus_on_activate", "false")
    cfg({"misc"}, "initial_workspace_tracking", "0")

    -- Swallowing (terminal -> spawned app)
    cfg({"misc"}, "enable_swallow", "off")
    cfg({"misc"}, "swallow_regex", [=[^([Aa]lacritty)$]=])

    -- Stability / UX dialogs
    cfg({"misc"}, "enable_anr_dialog", "true")
    cfg({"misc"}, "allow_session_lock_restore", "true")

    -- Suppress helper warnings/checks
    cfg({"misc"}, "disable_hyprland_guiutils_check", "true")

    cfg({"xwayland"}, "enabled", "true")
    cfg({"xwayland"}, "force_zero_scaling", "true")

        cfg({"plugin", "hyprbars"}, "bar_height", "20")

        -- bar background
        cfg({"plugin", "hyprbars"}, "bar_color", "rgb(1e1e1e)")
        cfg({"plugin", "hyprbars"}, "bar_blur", "false")

        -- title text (optional)
        cfg({"plugin", "hyprbars"}, "col.text", "rgb(d0d0d0)")

        -- layout
        cfg({"plugin", "hyprbars"}, "bar_title_enabled", "true")
        cfg({"plugin", "hyprbars"}, "bar_buttons_alignment", "right")
        cfg({"plugin", "hyprbars"}, "bar_padding", "5")
        cfg({"plugin", "hyprbars"}, "bar_button_padding", "7")
        cfg({"plugin", "hyprbars"}, "bar_text_align", "left")
        cfg({"plugin", "hyprbars"}, "bar_text_size", "10")
        cfg({"plugin", "hyprbars"}, "bar_text_font", "NotoSansM Nerd Font Mono")

        -- buttons: same as bar background; icons are light gray
        hyprbars_button("rgb(1e1e1e), 20, , hyprctl dispatch killactive")
        hyprbars_button("rgb(1e1e1e), 20, 󰨤, hyprctl dispatch fullscreen 1")
        hyprbars_button("rgb(1e1e1e), 20, , hyprctl dispatch togglefloating")

        cfg({"plugin", "hyprbars"}, "on_double_click", "hyprctl dispatch fullscreen 1")

-- ───────────────────────────────────────────────────────────────────────────────
-- INPUT
-- ───────────────────────────────────────────────────────────────────────────────

    cfg({"input"}, "kb_layout", "us")
    cfg({"input"}, "follow_mouse", "1")
    cfg({"input"}, "repeat_delay", "250")
    cfg({"input"}, "repeat_rate", "35")
    cfg({"input"}, "numlock_by_default", "true")

        cfg({"input", "touchpad"}, "natural_scroll", "true")
        cfg({"input", "touchpad"}, "disable_while_typing", "true")
        cfg({"input", "touchpad"}, "clickfinger_behavior", "true")
        cfg({"input", "touchpad"}, "scroll_factor", "0.5")

    -- Mouse: No acceleration (1:1 raw input)
    cfg({"input"}, "accel_profile", "flat")
    cfg({"input"}, "sensitivity", "0")
    cfg({"input"}, "force_no_accel", "1")

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
gesture("3, horizontal, workspace")

-- ───────────────────────────────────────────────────────────────────────────────
-- MODIFIERS
-- ───────────────────────────────────────────────────────────────────────────────

var("mod", "ALT")
var("super", "SUPER")
var("tempalt", "ALT")
var("submap_file", "/tmp/hypr-submap")

-- ───────────────────────────────────────────────────────────────────────────────
-- LAUNCHERS / COMMANDS
-- ───────────────────────────────────────────────────────────────────────────────

-- Base paths (using variables instead of repeating ~/.config/hypr/scripts everywhere)
var("hypr_dir", "~/.config/hypr")
var("hypr_scripts", "$hypr_dir/scripts")
var("launch", "$hypr_scripts/launch_handler.sh")

-- Core apps (define before anything that uses them)
var("terminal", "alacritty")
var("web-browser", "firefox")
var("calculator", "speedcrunch")
var("yazi", "$terminal -e yazi")

-- App/menu launchers
var("app-launcher", "$hypr_scripts/fuzzel_toggle.sh")
var("wlogout", "$hypr_scripts/wlogout_toggle.sh")
var("hypr_quicksettings", [=[$launch hypr_quicksettings "$terminal --class hypr_quicksettings -e $hypr_scripts/hypr_quicksettings.sh"]=])
var("awtarchy-tips-tui", [=[$launch awtarchy-tips-tui "$terminal --class awtarchy-tips-tui -e $hypr_scripts/awtarchy-tips-tui.sh"]=])

-- Audio
var("wiremix", [=[$launch wiremix "$terminal --class Wiremix -e wiremix"]=])
var("pavucontrol", [=[$launch pavucontrol "pavucontrol"]=])
var("pulsemixer", [=[$launch pulsemixer "$terminal --class Pulsemixer -e pulsemixer"]=])
var("mute_unmute", [=[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle]=])
var("play_pause", "$hypr_scripts/play_pause.sh")

-- Bars / UI toggles
var("hyprbars_toggle", "$hypr_scripts/hyprbars_toggle.sh")
var("waybar_toggle", "$hypr_scripts/waybar_toggle.sh")
var("waybar_flip", "$hypr_scripts/waybar_flip.sh")
var("waybar_rotate", "$hypr_scripts/waybar_rotate.sh")
var("toggle_animations", "$hypr_scripts/toggle_animations.sh")
var("mako_dismiss", "$hypr_scripts/mako_dismiss.sh")

-- Themes / wallpaper
var("wallpicker", [=[$launch wallpicker "$terminal --class wallpicker -e awtwall --resume"]=])
var("theme_select", "$hypr_scripts/theme_select.sh")

-- Capture / clipboard / QR
var("screenshot_select", "env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN $hypr_scripts/screenshot_area.sh")
var("screenshot_full", "$hypr_scripts/screenshot_fullscreen.sh")
var("screenshot_display", "$hypr_scripts/screenshot_display.sh")
var("gif_capture", "$hypr_scripts/gif_capture.sh")
var("clipboard_history", "$hypr_scripts/cliphist-fuzzel.sh")
var("qr_scan", "$hypr_scripts/qr_scan.sh")

-- Utilities
var("workspace_mix", "$hypr_scripts/workspace_mix.sh")
var("zoom", "$hypr_scripts/zoom.sh")
var("hyprpicker", "hyprpicker -a -f hex")
var("hypr-ddc-brightness", "$hypr_scripts/hypr-ddc-brightness.sh")
var("vibrance_shader", "$hypr_scripts/vibrance_shader.sh")
var("hyprsunset_ctl", "$hypr_scripts/hyprsunset_ctl.sh")

-- Terminal tools
var("maccel", [=[$launch maccel "$terminal --class maccel -e maccel"]=])
var("smtty", [=[$launch smtty "$terminal --class smtty -e smtty"]=])
var("btop", [=[$launch btop "$terminal --class btop -e btop"]=])

-- Complex one-off
var("smtty-O", [=[sh -lc 'if hyprctl clients | grep -q "class: smtty-O"; then hyprctl dispatch closewindow class:smtty-O; else $terminal --class smtty-O -e sh -lc '"'"'smtty -O; printf "\n[smtty -O finished]\nPress ENTER to close..."; read -r _'"'"'; fi']=])

-- Submap references (Toggle on)  [write name to file on entry]
var("noalt_on", [=[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']=])
var("mouse_on", [=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=])
var("vm_on", [=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=])

-- ───────────────────────────────────────────────────────────────────────────────
-- DEFAULT MODE (ALT is modifier; SUPER is app/meta)
-- ───────────────────────────────────────────────────────────────────────────────

-- App launchers / terminals
b("$mod", "P", "exec", "$app-launcher")
b("$super", "D", "exec", "$app-launcher")
b("$mod SHIFT", "RETURN", "exec", "$terminal")
b("$super SHIFT", "RETURN", "exec", "$terminal")
b("$super", "RETURN", "exec", "$terminal")
b("$mod SHIFT", "B", "exec", "$btop")
b("$super SHIFT", "B", "exec", "$btop")
b("$super", "B", "exec", "$web-browser")
b("$mod SHIFT", "C", "exec", "$calculator")
b("$super SHIFT", "C", "exec", "$calculator")
b("$mod SHIFT", "M", "exec", "$maccel")
b("$super SHIFT", "M", "exec", "$maccel")

-- Audio mixer
b("$mod", "V", "exec", "$wiremix")
b("$super", "V", "exec", "$wiremix")

-- Mako dismiss
b("$mod", "SPACE", "exec", "$mako_dismiss")
b("$mod CTRL", "SPACE", "exec", "$mako_dismiss")
b("$mod SHIFT", "SPACE", "exec", "$mako_dismiss")
b("$mod CTRL SHIFT", "SPACE", "exec", "$mako_dismiss")
b("$super", "SPACE", "exec", "$mako_dismiss")

-- Terminal utilities (smtty)
b("$super $mod", "G", "exec", "$smtty")
b("$super $mod", "L", "exec", "smtty -S -l")
b("$super $mod", "O", "exec", "$smtty-O")
b("$super $mod", "K", "exec", "smtty -k")

-- UI / compositor toggles
b("$super $mod", "T", "exec", "$hyprbars_toggle")
b("$super $mod", "B", "exec", "$waybar_rotate")
b("$super $mod CTRL", "B", "exec", "$waybar_toggle")
b("$super CTRL", "B", "exec", "$waybar_flip")
b("$super", "A", "exec", "$toggle_animations")

-- Brightness / color temperature
b("$super $mod", "backspace", "exec", "$hypr_quicksettings")
b("$super $mod", "equal", "exec", "$hypr-ddc-brightness up 5")
b("$super $mod", "minus", "exec", "$hypr-ddc-brightness down 5")
b("$super $mod CTRL", "equal", "exec", "$hyprsunset_ctl up")
b("$super $mod CTRL", "minus", "exec", "$hyprsunset_ctl down")
b("$super $mod CTRL", "backspace", "exec", "$hyprsunset_ctl toggle")

-- File managers / system
b("$super", "E", "exec", "pcmanfm-qt")
b("$super SHIFT", "E", "exec", "$yazi")
b("$super", "L", "exec", "hyprlock")
b("$super", "I", "exec", "$hyprpicker")
b("$super", "P", "exec", "$wlogout")

-- Themes / wallpaper
b("$super", "W", "exec", "$wallpicker")
b("$super SHIFT", "W", "exec", "awtwall --random-current")
b("$super CTRL", "W", "exec", "awtwall --random-all")
b("$super $mod", "W", "exec", "awtwall --random-all-different")
b("$super", "T", "exec", "$theme_select")

-- Capture / clipboard / misc
b("$super", "C", "exec", "$clipboard_history")
b("$super", "S", "exec", "$qr_scan")
b("$super SHIFT", "S", "exec", "$screenshot_select")
b("$super SHIFT", "F", "exec", "$screenshot_full")
b("$super SHIFT", "D", "exec", "$screenshot_display")
b("$super SHIFT", "G", "exec", "$gif_capture")

-- Window management
b("$super", "Q", "killactive", "")
b("$super SHIFT", "Q", "killactive", "")
b("$mod SHIFT", "Q", "killactive", "")
b("$mod", "F4", "killactive", "")
b("$super $mod", "Q", "exec", "hyprctl kill")
b("$mod", "Y", "pin", "")
b("$super", "Y", "pin", "")
b("$tempalt", "R", "layoutmsg", "swapsplit")
b("$tempalt SHIFT", "R", "layoutmsg", "togglesplit")
b("$super", "R", "layoutmsg", "swapsplit")
b("$super SHIFT", "R", "layoutmsg", "togglesplit")
b("$tempalt", "F", "togglefloating", "")
b("$tempalt CTRL", "F", "fullscreen", "")
b("$super", "F", "togglefloating", "")
b("$super CTRL", "F", "fullscreen", "")
b("$mod", "TAB", "cyclenext", "")
b("$mod", "TAB", "bringactivetotop", "")
b("$mod SHIFT", "TAB", "cyclenext", "prev")

-- Focus move (ALT/SUPER arrows)
b("$tempalt", "left", "movefocus", "l")
b("$tempalt", "right", "movefocus", "r")
b("$tempalt", "up", "movefocus", "u")
b("$tempalt", "down", "movefocus", "d")
b("$super", "left", "movefocus", "l")
b("$super", "right", "movefocus", "r")
b("$super", "up", "movefocus", "u")
b("$super", "down", "movefocus", "d")
-- ALT/SUPER hjkl
b("$tempalt", "h", "movefocus", "l")
b("$tempalt", "j", "movefocus", "d")
b("$tempalt", "k", "movefocus", "u")
b("$tempalt", "l", "movefocus", "r")
b("$super", "h", "movefocus", "l")
b("$super", "j", "movefocus", "d")
b("$super", "k", "movefocus", "u")
b("$super", "l", "movefocus", "r")

-- Window move (ALT/SUPER+SHIFT arrows)
b("$tempalt SHIFT", "left", "movewindow", "l")
b("$tempalt SHIFT", "right", "movewindow", "r")
b("$tempalt SHIFT", "up", "movewindow", "u")
b("$tempalt SHIFT", "down", "movewindow", "d")
b("$super SHIFT", "left", "movewindow", "l")
b("$super SHIFT", "right", "movewindow", "r")
b("$super SHIFT", "up", "movewindow", "u")
b("$super SHIFT", "down", "movewindow", "d")
-- ALT/SUPER+SHIFT hjkl
b("$tempalt SHIFT", "h", "movewindow", "l")
b("$tempalt SHIFT", "j", "movewindow", "d")
b("$tempalt SHIFT", "k", "movewindow", "u")
b("$tempalt SHIFT", "l", "movewindow", "r")
b("$super SHIFT", "h", "movewindow", "l")
b("$super SHIFT", "j", "movewindow", "d")
b("$super SHIFT", "k", "movewindow", "u")
b("$super SHIFT", "l", "movewindow", "r")

-- Send current workspace to monitor (ALT/SUPER+CTRL+SHIFT numbers)
b("$tempalt CTRL SHIFT", "left", "movecurrentworkspacetomonitor", "-1")
b("$tempalt CTRL SHIFT", "right", "movecurrentworkspacetomonitor", "+1")
b("$tempalt CTRL SHIFT", "up", "movecurrentworkspacetomonitor", "-1")
b("$tempalt CTRL SHIFT", "down", "movecurrentworkspacetomonitor", "+1")
b("$super CTRL SHIFT", "left", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "right", "movecurrentworkspacetomonitor", "+1")
b("$super CTRL SHIFT", "up", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "down", "movecurrentworkspacetomonitor", "+1")
-- ALT/SUPER+CTRL+SHIFT "[" or "]"
b("$tempalt CTRL SHIFT", "bracketleft", "movecurrentworkspacetomonitor", "-1")
b("$tempalt CTRL SHIFT", "bracketright", "movecurrentworkspacetomonitor", "+1")
b("$super CTRL SHIFT", "bracketleft", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "bracketright", "movecurrentworkspacetomonitor", "+1")

-- Workspaces (ALT/SUPER numbers)
b("$tempalt", "1", "workspace", "1")
b("$tempalt", "2", "workspace", "2")
b("$tempalt", "3", "workspace", "3")
b("$tempalt", "4", "workspace", "4")
b("$tempalt", "5", "workspace", "5")
b("$tempalt", "6", "workspace", "6")
b("$tempalt", "7", "workspace", "7")
b("$tempalt", "8", "workspace", "8")
b("$tempalt", "9", "workspace", "9")
b("$tempalt", "0", "workspace", "10")
b("$super", "1", "workspace", "1")
b("$super", "2", "workspace", "2")
b("$super", "3", "workspace", "3")
b("$super", "4", "workspace", "4")
b("$super", "5", "workspace", "5")
b("$super", "6", "workspace", "6")
b("$super", "7", "workspace", "7")
b("$super", "8", "workspace", "8")
b("$super", "9", "workspace", "9")
b("$super", "0", "workspace", "10")

-- Prev/next workspace with (ALT/SUPER "[" or "]")
b("$tempalt", "bracketleft", "workspace", "-1")
b("$tempalt", "bracketright", "workspace", "+1")
b("$super", "bracketleft", "workspace", "-1")
b("$super", "bracketright", "workspace", "+1")

-- Move window to workspace (ALT/SUPER+SHIFT numbers)
b("$tempalt SHIFT", "1", "movetoworkspacesilent", "1")
b("$tempalt SHIFT", "2", "movetoworkspacesilent", "2")
b("$tempalt SHIFT", "3", "movetoworkspacesilent", "3")
b("$tempalt SHIFT", "4", "movetoworkspacesilent", "4")
b("$tempalt SHIFT", "5", "movetoworkspacesilent", "5")
b("$tempalt SHIFT", "6", "movetoworkspacesilent", "6")
b("$tempalt SHIFT", "7", "movetoworkspacesilent", "7")
b("$tempalt SHIFT", "8", "movetoworkspacesilent", "8")
b("$tempalt SHIFT", "9", "movetoworkspacesilent", "9")
b("$tempalt SHIFT", "0", "movetoworkspacesilent", "10")
b("$super SHIFT", "1", "movetoworkspacesilent", "1")
b("$super SHIFT", "2", "movetoworkspacesilent", "2")
b("$super SHIFT", "3", "movetoworkspacesilent", "3")
b("$super SHIFT", "4", "movetoworkspacesilent", "4")
b("$super SHIFT", "5", "movetoworkspacesilent", "5")
b("$super SHIFT", "6", "movetoworkspacesilent", "6")
b("$super SHIFT", "7", "movetoworkspacesilent", "7")
b("$super SHIFT", "8", "movetoworkspacesilent", "8")
b("$super SHIFT", "9", "movetoworkspacesilent", "9")
b("$super SHIFT", "0", "movetoworkspacesilent", "10")

-- Resize (ALT/SUPER+CTRL arrows / hold)
be("$tempalt CTRL", "right", "resizeactive", "30 0")
be("$tempalt CTRL", "left", "resizeactive", "-30 0")
be("$tempalt CTRL", "up", "resizeactive", "0 -30")
be("$tempalt CTRL", "down", "resizeactive", "0 30")
be("$super CTRL", "right", "resizeactive", "30 0")
be("$super CTRL", "left", "resizeactive", "-30 0")
be("$super CTRL", "up", "resizeactive", "0 -30")
be("$super CTRL", "down", "resizeactive", "0 30")
-- ALT/SUPER+CTRL hjkl
be("$tempalt CTRL", "h", "resizeactive", "-30 0")
be("$tempalt CTRL", "j", "resizeactive", "0 30")
be("$tempalt CTRL", "k", "resizeactive", "0 -30")
be("$tempalt CTRL", "l", "resizeactive", "30 0")
be("$super CTRL", "h", "resizeactive", "-30 0")
be("$super CTRL", "j", "resizeactive", "0 30")
be("$super CTRL", "k", "resizeactive", "0 -30")
be("$super CTRL", "l", "resizeactive", "30 0")

-- Mouse (ALT/SUPER mouse-left/right / hold)
bm("$tempalt", "mouse:272", "movewindow", "")
bm("$tempalt", "mouse:273", "resizewindow", "")
bm("$super", "mouse:272", "movewindow", "")
bm("$super", "mouse:273", "resizewindow", "")

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
b("$super $mod", "bracketright", "exec", "$vibrance_shader up")
b("$super $mod", "bracketleft", "exec", "$vibrance_shader down")
b("$super $mod", "backslash", "exec", "$vibrance_shader toggle")

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
b("$super $mod CTRL", "1", "exec", "$workspace_mix toggle 1")
b("$super $mod CTRL", "2", "exec", "$workspace_mix toggle 2")
b("$super $mod CTRL", "3", "exec", "$workspace_mix toggle 3")
b("$super $mod CTRL", "4", "exec", "$workspace_mix toggle 4")
b("$super $mod CTRL", "5", "exec", "$workspace_mix toggle 5")
b("$super $mod CTRL", "6", "exec", "$workspace_mix toggle 6")
b("$super $mod CTRL", "7", "exec", "$workspace_mix toggle 7")
b("$super $mod CTRL", "8", "exec", "$workspace_mix toggle 8")
b("$super $mod CTRL", "9", "exec", "$workspace_mix toggle 9")
b("$super $mod CTRL", "0", "exec", "$workspace_mix toggle 10")
b("$super $mod CTRL", "F", "exec", "$workspace_mix focus")
b("$super $mod CTRL", "R", "exec", "$workspace_mix restore")

-- Zoom script (SUPER +/-)
be("$super", "equal", "exec", "$zoom +")
be("$super", "minus", "exec", "$zoom -")
be("$super SHIFT", "equal", "exec", "$zoom ++")
be("$super SHIFT", "minus", "exec", "$zoom --")
b("$super", "backspace", "exec", "$zoom reset")
b("$super", "backslash", "exec", "$zoom rigid")
be("$super CTRL", "equal", "exec", [=[$zoom + step:5%]=])
be("$super CTRL", "minus", "exec", [=[$zoom - step:5%]=])

-- Scratchpad (SUPER+x,X)
b("$super", "X", "togglespecialworkspace", "magic")
b("$super SHIFT", "X", "movetoworkspace", "special:magic")

-- Misc (SUPER+F12)
b("$super", "F12", "exec", [=[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']=])
b("$super CTRL", "F12", "exec", [=[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]=])

-- Media & Brightness
bel("", "XF86AudioRaiseVolume", "exec", [=[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]=])
bel("", "XF86AudioLowerVolume", "exec", [=[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]=])
bel("", "XF86AudioMute", "exec", [=[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]=])
bel("", "XF86AudioMicMute", "exec", [=[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]=])
bel("", "XF86MonBrightnessUp", "exec", [=[brightnessctl -e4 -n2 set 5%+]=])
bel("", "XF86MonBrightnessDown", "exec", [=[brightnessctl -e4 -n2 set 5%-]=])
bl("", "XF86AudioPlay", "exec", "$play_pause")
bl("", "XF86AudioNext", "exec", "playerctl next")
bl("", "XF86AudioPrev", "exec", "playerctl previous")
b("$super", "M", "exec", "$mute_unmute")

-- Submap binds                        (Toggle on/off)
b("$super $mod", "N", "exec", "$noalt_on")
b("$super $mod", "M", "exec", "$mouse_on")
b("$super $mod", "V", "exec", "$vm_on")

-- ───────────────────────────────────────────────────────────────────────────────
-- noalt SUBMAP; alt is disabled for most tasks
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("noalt", function()

-- Submap references in "noalt" (toggle off/on)  [empty file on exit]
var("noalt_off", [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=])
var("mouse_on", [=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=])
var("vm_on", [=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=])

-- App launchers / terminals in "noalt"
b("$mod", "P", "exec", "$app-launcher")
b("$super", "D", "exec", "$app-launcher")
b("$mod SHIFT", "RETURN", "exec", "$terminal")
b("$super SHIFT", "RETURN", "exec", "$terminal")
b("$super", "RETURN", "exec", "$terminal")
b("$mod SHIFT", "B", "exec", "$btop")
b("$super SHIFT", "B", "exec", "$btop")
b("$super", "B", "exec", "$web-browser")
b("$mod SHIFT", "C", "exec", "$calculator")
b("$super SHIFT", "C", "exec", "$calculator")
b("$mod SHIFT", "M", "exec", "$maccel")
b("$super SHIFT", "M", "exec", "$maccel")

-- Audio mixer in "noalt"
b("$mod", "V", "exec", "$wiremix")
b("$super", "V", "exec", "$wiremix")

-- Mako dismiss in "noalt"
b("$mod", "SPACE", "exec", "$mako_dismiss")
b("$mod CTRL", "SPACE", "exec", "$mako_dismiss")
b("$mod SHIFT", "SPACE", "exec", "$mako_dismiss")
b("$mod CTRL SHIFT", "SPACE", "exec", "$mako_dismiss")
b("$super", "SPACE", "exec", "$mako_dismiss")

-- Terminal utilities (smtty) in "noalt"
b("$super $mod", "G", "exec", "$smtty")
b("$super $mod", "L", "exec", "smtty -S -l")
b("$super $mod", "O", "exec", "$smtty-O")
b("$super $mod", "K", "exec", "smtty -k")

-- UI / compositor toggles in "noalt"
b("$super $mod", "T", "exec", "$hyprbars_toggle")
b("$super $mod", "B", "exec", "$waybar_rotate")
b("$super $mod CTRL", "B", "exec", "$waybar_toggle")
b("$super CTRL", "B", "exec", "$waybar_flip")
b("$super", "A", "exec", "$toggle_animations")

-- Brightness / color temperature in "noalt"
b("$super $mod", "backspace", "exec", "$hypr_quicksettings")
b("$super $mod", "equal", "exec", "$hypr-ddc-brightness up 5")
b("$super $mod", "minus", "exec", "$hypr-ddc-brightness down 5")
b("$super $mod CTRL", "equal", "exec", "$hyprsunset_ctl up")
b("$super $mod CTRL", "minus", "exec", "$hyprsunset_ctl down")
b("$super $mod CTRL", "backspace", "exec", "$hyprsunset_ctl toggle")

-- File managers / system in "noalt"
b("$super", "E", "exec", "pcmanfm-qt")
b("$super SHIFT", "E", "exec", "$yazi")
b("$super", "L", "exec", "hyprlock")
b("$super", "I", "exec", "$hyprpicker")
b("$super", "P", "exec", "$wlogout")

-- Themes / wallpaper
b("$super", "W", "exec", "$wallpicker")
b("$super SHIFT", "W", "exec", "awtwall --random-current")
b("$super CTRL", "W", "exec", "awtwall --random-all")
b("$super $mod", "W", "exec", "awtwall --random-all-different")
b("$super", "T", "exec", "$theme_select")

-- Capture / clipboard / misc in "noalt"
b("$super", "C", "exec", "$clipboard_history")
b("$super", "S", "exec", "$qr_scan")
b("$super SHIFT", "S", "exec", "$screenshot_select")
b("$super SHIFT", "F", "exec", "$screenshot_full")
b("$super SHIFT", "D", "exec", "$screenshot_display")
b("$super SHIFT", "G", "exec", "$gif_capture")

-- Window management in "noalt"
b("$super", "Q", "killactive", "")
b("$super SHIFT", "Q", "killactive", "")
b("$mod", "F4", "killactive", "")
b("$super $mod", "Q", "exec", "hyprctl kill")
b("$super", "Y", "pin", "")
b("$super SHIFT", "R", "layoutmsg", "togglesplit")
b("$super", "R", "layoutmsg", "swapsplit")
b("$super", "F", "togglefloating", "")
b("$super CTRL", "F", "fullscreen", "")
b("$mod", "TAB", "cyclenext", "")
b("$mod", "TAB", "bringactivetotop", "")
b("$mod SHIFT", "TAB", "cyclenext", "prev")

-- Focus move in "noalt" (SUPER arrows)
b("$super", "left", "movefocus", "l")
b("$super", "right", "movefocus", "r")
b("$super", "up", "movefocus", "u")
b("$super", "down", "movefocus", "d")
-- SUPER hjkl
b("$super", "h", "movefocus", "l")
b("$super", "j", "movefocus", "d")
b("$super", "k", "movefocus", "u")
b("$super", "l", "movefocus", "r")

-- Window move in "noalt" (SUPER+SHIFT arrows)
b("$super SHIFT", "left", "movewindow", "l")
b("$super SHIFT", "right", "movewindow", "r")
b("$super SHIFT", "up", "movewindow", "u")
b("$super SHIFT", "down", "movewindow", "d")
-- SUPER+SHIFT hjkl
b("$super SHIFT", "h", "movewindow", "l")
b("$super SHIFT", "j", "movewindow", "d")
b("$super SHIFT", "k", "movewindow", "u")
b("$super SHIFT", "l", "movewindow", "r")

-- Send current workspace to monitor in "noalt" (SUPER+CTRL+SHIFT numbers)
b("$super CTRL SHIFT", "left", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "right", "movecurrentworkspacetomonitor", "+1")
b("$super CTRL SHIFT", "up", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "down", "movecurrentworkspacetomonitor", "+1")
-- SUPER+CTRL+SHIFT "[" or "]"
b("$super CTRL SHIFT", "bracketleft", "movecurrentworkspacetomonitor", "-1")
b("$super CTRL SHIFT", "bracketright", "movecurrentworkspacetomonitor", "+1")

-- Workspaces in "noalt" (SUPER numbers)
b("$super", "1", "workspace", "1")
b("$super", "2", "workspace", "2")
b("$super", "3", "workspace", "3")
b("$super", "4", "workspace", "4")
b("$super", "5", "workspace", "5")
b("$super", "6", "workspace", "6")
b("$super", "7", "workspace", "7")
b("$super", "8", "workspace", "8")
b("$super", "9", "workspace", "9")
b("$super", "0", "workspace", "10")

-- Prev/next workspace with (SUPER "[" or "]")
b("$super", "bracketleft", "workspace", "-1")
b("$super", "bracketright", "workspace", "+1")

-- Move window to workspace in "noalt" (SUPER+SHIFT numbers)
b("$super SHIFT", "1", "movetoworkspacesilent", "1")
b("$super SHIFT", "2", "movetoworkspacesilent", "2")
b("$super SHIFT", "3", "movetoworkspacesilent", "3")
b("$super SHIFT", "4", "movetoworkspacesilent", "4")
b("$super SHIFT", "5", "movetoworkspacesilent", "5")
b("$super SHIFT", "6", "movetoworkspacesilent", "6")
b("$super SHIFT", "7", "movetoworkspacesilent", "7")
b("$super SHIFT", "8", "movetoworkspacesilent", "8")
b("$super SHIFT", "9", "movetoworkspacesilent", "9")
b("$super SHIFT", "0", "movetoworkspacesilent", "10")

-- Resize in "noalt" (SUPER+CTRL arrows / hold)
be("$super CTRL", "right", "resizeactive", "30 0")
be("$super CTRL", "left", "resizeactive", "-30 0")
be("$super CTRL", "up", "resizeactive", "0 -30")
be("$super CTRL", "down", "resizeactive", "0 30")
-- SUPER+CTRL hjkl
be("$super CTRL", "h", "resizeactive", "-30 0")
be("$super CTRL", "j", "resizeactive", "0 30")
be("$super CTRL", "k", "resizeactive", "0 -30")
be("$super CTRL", "l", "resizeactive", "30 0")

-- Mouse in "noalt" (SUPER mouse-left/right / hold)
bm("$super", "mouse:272", "movewindow", "")
bm("$super", "mouse:273", "resizewindow", "")

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
b("$super $mod", "bracketright", "exec", "$vibrance_shader up")
b("$super $mod", "bracketleft", "exec", "$vibrance_shader down")
b("$super $mod", "backslash", "exec", "$vibrance_shader toggle")

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
b("$super $mod CTRL", "1", "exec", "$workspace_mix toggle 1")
b("$super $mod CTRL", "2", "exec", "$workspace_mix toggle 2")
b("$super $mod CTRL", "3", "exec", "$workspace_mix toggle 3")
b("$super $mod CTRL", "4", "exec", "$workspace_mix toggle 4")
b("$super $mod CTRL", "5", "exec", "$workspace_mix toggle 5")
b("$super $mod CTRL", "6", "exec", "$workspace_mix toggle 6")
b("$super $mod CTRL", "7", "exec", "$workspace_mix toggle 7")
b("$super $mod CTRL", "8", "exec", "$workspace_mix toggle 8")
b("$super $mod CTRL", "9", "exec", "$workspace_mix toggle 9")
b("$super $mod CTRL", "0", "exec", "$workspace_mix toggle 10")
b("$super $mod CTRL", "F", "exec", "$workspace_mix focus")
b("$super $mod CTRL", "R", "exec", "$workspace_mix restore")

-- Zoom script in "noalt" (SUPER +/-)
be("$super", "equal", "exec", "$zoom +")
be("$super", "minus", "exec", "$zoom -")
be("$super SHIFT", "equal", "exec", "$zoom ++")
be("$super SHIFT", "minus", "exec", "$zoom --")
b("$super", "backspace", "exec", "$zoom reset")
b("$super", "backslash", "exec", "$zoom rigid")
be("$super CTRL", "equal", "exec", [=[$zoom + step:5%]=])
be("$super CTRL", "minus", "exec", [=[$zoom - step:5%]=])

-- Scratchpad in "noalt" (SUPER+x,X)
b("$super", "X", "togglespecialworkspace", "magic")
b("$super SHIFT", "X", "movetoworkspace", "special:magic")

-- Misc in "noalt" (SUPER+F12)
b("$super", "F12", "exec", [=[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']=])
b("$super CTRL", "F12", "exec", [=[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]=])

-- Media & Brightness
bel("", "XF86AudioRaiseVolume", "exec", [=[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]=])
bel("", "XF86AudioLowerVolume", "exec", [=[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]=])
bel("", "XF86AudioMute", "exec", [=[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]=])
bel("", "XF86AudioMicMute", "exec", [=[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]=])
bel("", "XF86MonBrightnessUp", "exec", [=[brightnessctl -e4 -n2 set 5%+]=])
bel("", "XF86MonBrightnessDown", "exec", [=[brightnessctl -e4 -n2 set 5%-]=])
bl("", "XF86AudioPlay", "exec", "$play_pause")
bl("", "XF86AudioNext", "exec", "playerctl next")
bl("", "XF86AudioPrev", "exec", "playerctl previous")
b("$super", "M", "exec", "$mute_unmute")

-- Submap binds in "noalt"             (Toggle off/on)
b("$super $mod", "N", "exec", "$noalt_off")
b("$super $mod", "M", "exec", "$mouse_on")
b("$super $mod", "V", "exec", "$vm_on")

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- MOUSE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("mouse", function()

-- Submap references in "mouse" (Toggle off)  [empty file on exit]
var("mouse_off", [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=])

-- Resize (MOUSE-left/right / hold)
be("", "h", "resizeactive", "-30 0")
be("", "j", "resizeactive", "0 30")
be("", "k", "resizeactive", "0 -30")
be("", "l", "resizeactive", "30 0")
be("", "left", "resizeactive", "-30 0")
be("", "down", "resizeactive", "0 30")
be("", "up", "resizeactive", "0 -30")
be("", "right", "resizeactive", "30 0")
bm("", "mouse:272", "movewindow", "")
bm("", "mouse:273", "resizewindow", "")
b("", "mouse:274", "togglefloating", "")
b("", "Escape", "exec", "$mouse_off reset")
b("", "Return", "exec", "$mouse_off reset")

-- Submap binds in "mouse"  (Toggle off/on)
b("$super $mod", "M", "exec", "$mouse_off")
b("$super $mod", "N", "exec", "$noalt_on")
b("$super $mod", "V", "exec", "$vm_on")

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- VIRTUAL MACHINE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("vm", function()

-- Submap references in "vm" (Toggle off)  [empty file on exit]
var("vm_off", [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=])

-- Binds
b("$super $mod", "Q", "killactive", "")
b("$super $mod", "F", "togglefloating", "")
b("$super $mod", "P", "exec", "$app-launcher")
b("$super $mod", "C", "exec", "$calculator")
b("$super $mod CTRL", "V", "exec", "$wiremix")
b("$super $mod CTRL", "S", "exec", "$qr_scan")
b("$super $mod", "S", "exec", "$screenshot_select")
b("$super $mod", "D", "exec", "$screenshot_display")
b("$super $mod", "G", "exec", "$gif_capture")
b("$super $mod", "RETURN", "exec", "$terminal")
be("$super $mod", "SPACE", "exec", "$mako_dismiss")
bm("$super $mod", "mouse:272", "movewindow", "")
bm("$super $mod", "mouse:273", "resizewindow", "")
b("$super $mod", "mouse:274", "togglefloating", "")

-- Workspaces (SUPER+ALT numbers)
b("$super $mod", "1", "workspace", "1")
b("$super $mod", "2", "workspace", "2")
b("$super $mod", "3", "workspace", "3")
b("$super $mod", "4", "workspace", "4")
b("$super $mod", "5", "workspace", "5")
b("$super $mod", "6", "workspace", "6")
b("$super $mod", "7", "workspace", "7")
b("$super $mod", "8", "workspace", "8")
b("$super $mod", "9", "workspace", "9")
b("$super $mod", "0", "workspace", "10")

-- Move window to workspace (SUPER+ALT+SHIFT numbers)
b("$super $mod SHIFT", "1", "movetoworkspacesilent", "1")
b("$super $mod SHIFT", "2", "movetoworkspacesilent", "2")
b("$super $mod SHIFT", "3", "movetoworkspacesilent", "3")
b("$super $mod SHIFT", "4", "movetoworkspacesilent", "4")
b("$super $mod SHIFT", "5", "movetoworkspacesilent", "5")
b("$super $mod SHIFT", "6", "movetoworkspacesilent", "6")
b("$super $mod SHIFT", "7", "movetoworkspacesilent", "7")
b("$super $mod SHIFT", "8", "movetoworkspacesilent", "8")
b("$super $mod SHIFT", "9", "movetoworkspacesilent", "9")
b("$super $mod SHIFT", "0", "movetoworkspacesilent", "10")

-- Submap binds in "vm"            (Toggle off/on)
b("$super $mod", "V", "exec", "$vm_off")
b("$super $mod", "M", "exec", "$mouse_on")
b("$super $mod", "N", "exec", "$noalt_on")

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- RULES
-- ───────────────────────────────────────────────────────────────────────────────

-- Games: send to workspace 1, strip effects, fullscreen, allow tearing, keep awake
-- Note: Proton/Wine windows often have class like "game.exe" (not "Wine"), so we also match *.exe.
var("games", [=[^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$]=])
-- Mark these windows as "game" content type so render:direct_scanout=2 can auto-engage
rule("match:class $games, content game", false)
-- other $games window rules
rule("match:class $games, workspace 1 silent", false)
rule("match:class $games, no_anim on", false)
rule("match:class $games, no_blur on", false)
rule("match:class $games, no_shadow on", false)
rule("match:class $games, decorate off", false)
rule("match:class $games, border_size 0", false)
rule("match:class $games, rounding 0", false)
rule("match:class $games, fullscreen on", false)
rule("match:class $games, immediate on", false)
rule("match:class $games, idle_inhibit always", false)

-- Workspace auto-assignments
rule([=[match:class ^(firefox|librewolf|Mullvad Browser|Cromite|brave-browser|io\.github\.ungoogled_software\.ungoogled_chromium)$, workspace 2 silent]=], false)
rule([=[match:class ^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|brave-app\.revolt\.chat__-.*|chat\.revolt\.RevoltDesktop|info\.mumble\.Mumble|fluxer|Fluxer)$, workspace 3 silent]=], false)
rule([=[match:class ^(steam|com\.valvesoftware\.Steam|SteamChat|net\.lutris\.Lutris|itch|io\.itch\.itch|heroic|com\.heroicgameslauncher\.hgl|r2modman)$, workspace 4 silent]=], false)
rule([=[match:class ^(Spotify|com\.spotify\.Client|brave-music\.youtube\.com__-.*)$, workspace 5 silent]=], false)
rule([=[match:title ^(.*YouTube Music.*)$, workspace 5 silent]=], false)
rule([=[match:class ^(org\.telegram\.desktop|brave-web\.telegram\.org__a_-.*|brave-messages\.google\.com__-.*)$, workspace 6 silent]=], false)
rule([=[match:title ^(Telegram Web)$, workspace 6 silent]=], false)
rule([=[match:class ^(Messages)$, workspace 6 silent]=], false)
rule([=[match:class ^(Telegram)$, workspace 6 silent]=], false)
rule([=[match:class ^(Vncviewer|rustdesk)$, workspace 7 silent]=], false)
rule([=[match:class ^(com\.github\.IsmaelMartinez\.teams_for_linux)$, workspace 8 silent]=], false)
rule([=[match:class ^(kdenlive|org\.kde\.kdenlive|org\.shotcut\.Shotcut|krita|org\.kde\.krita)$, workspace 9 silent]=], false)
rule([=[match:class ^(obs|com\.obsproject\.Studio|gpu-screen-recorder|gpu-screen-recorder-gtk|gpu-screen-recorder-ui|gsr-ui|com\.dec05eba\.gpu_screen_recorder)$, workspace 10 silent]=], false)

-- Global behavior / XWayland quirks
rule([=[match:class .*, suppress_event maximize]=], false)
rule([=[match:class ^$, match:title ^$, match:xwayland 1, match:float 1, match:fullscreen 0, match:pin 0, no_focus on]=], false)
rule("match:xwayland 1, no_blur on", false)
rule([=[match:class ^(steam)$, match:title ^$, stay_focused on]=], false)
rule([=[match:class ^(steam)$, match:title ^$, min_size 1 1]=], false)

-- Picture-in-Picture
var("pip", [=[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]=])
rule("match:title $pip, float on", false)
rule("match:title $pip, keep_aspect_ratio on", false)
rule([=[match:title $pip, move (monitor_w*0.73) (monitor_h*0.70)]=], false)
rule([=[match:title $pip, size (monitor_w*0.25) (monitor_h*0.25)]=], false)
rule("match:title $pip, pin on", false)

-- Dialogs float+center
var("dialogs", [=[^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload)(.*)$]=])
rule("match:title $dialogs, float on", false)
rule("match:title $dialogs, center on", false)

-- Transparency
rule([=[match:class ^(wofi)$, opacity 0.85 0.85]=], false)
rule([=[match:class ^(Spotify)$, opacity 0.85 0.85]=], false)
rule([=[match:title ^(YouTube Music|YouTube Music - .+ - YouTube Music|YouTube Music - 1\. YouTube Music)$, opacity 0.85 0.85]=], false)
rule([=[match:class ^(com\.github\.th_ch\.youtube_music|brave-music\.youtube\.com__-.*)$, opacity 0.85 0.85]=], false)
rule([=[match:class ^(pcmanfm-qt|localsend|org\.pulseaudio\.pavucontrol|org\.speedcrunch\.speedcrunch|net\.davidotek\.pupgui2|wallpicker)$, opacity 0.95 0.95]=], false)

-- Float + size + center
rule([=[match:class ^org\.speedcrunch\.speedcrunch$, float on]=], false)
rule([=[match:class ^org\.speedcrunch\.speedcrunch$, size (monitor_w*0.15) (monitor_h*0.55)]=], false)
rule([=[match:class ^org\.speedcrunch\.speedcrunch$, center on]=], false)

rule([=[match:class ^org\.pulseaudio\.pavucontrol$, float on]=], false)
rule([=[match:class ^org\.pulseaudio\.pavucontrol$, size (monitor_w*0.55) (monitor_h*0.70)]=], false)
rule([=[match:class ^org\.pulseaudio\.pavucontrol$, center on]=], false)

rule([=[match:class ^(Pulsemixer)$, float on]=], false)
rule([=[match:class ^(Pulsemixer)$, size (monitor_w*0.55) (monitor_h*0.70)]=], false)
rule([=[match:class ^(Pulsemixer)$, center on]=], false)

rule([=[match:class ^(Wiremix)$, float on]=], false)
rule([=[match:class ^(Wiremix)$, size (monitor_w*0.65) (monitor_h*0.70)]=], false)
rule([=[match:class ^(Wiremix)$, center on]=], false)

rule([=[match:class ^(hypr_quicksettings)$, float on]=], false)
rule([=[match:class ^(hypr_quicksettings)$, size (monitor_w*0.70) (monitor_h*0.40)]=], false)
rule([=[match:class ^(hypr_quicksettings)$, center on]=], false)

rule([=[match:class ^(awtarchy-tips-tui)$, float on]=], false)
rule([=[match:class ^(awtarchy-tips-tui)$, size (monitor_w*0.50) (monitor_h*0.50)]=], false)
rule([=[match:class ^(awtarchy-tips-tui)$, center on]=], false)

rule([=[match:class ^(maccel)$, float on]=], false)
rule([=[match:class ^(maccel)$, size (monitor_w*0.90) (monitor_h*0.96)]=], false)
rule([=[match:class ^(maccel)$, center on]=], false)

rule([=[match:class ^(hyprbars)$, float on]=], false)
rule([=[match:class ^(hyprbars)$, size (monitor_w*0.30) (monitor_h*0.10)]=], false)
rule([=[match:class ^(hyprbars)$, center on]=], false)

rule([=[match:class ^(smtty)$, float on]=], false)
rule([=[match:class ^(smtty)$, size (monitor_w*0.80) (monitor_h*0.88)]=], false)
rule([=[match:class ^(smtty)$, center on]=], false)

rule([=[match:class ^(smtty-O)$, float on]=], false)
rule([=[match:class ^(smtty-O)$, size (monitor_w*0.50) (monitor_h*0.50)]=], false)
rule([=[match:class ^(smtty-O)$, center on]=], false)

rule([=[match:class ^(wallpicker)$, float on]=], false)
rule([=[match:class ^(wallpicker)$, size (monitor_w*0.85) (monitor_h*0.90)]=], false)
rule([=[match:class ^(wallpicker)$, center on]=], false)

rule([=[match:class ^(nm-connection-editor)$, float on]=], false)
rule([=[match:class ^(nm-connection-editor)$, size (monitor_w*0.45) (monitor_h*0.45)]=], false)
rule([=[match:class ^(nm-connection-editor)$, center on]=], false)

rule([=[match:class ^(blueman-manager)$, float on]=], false)
rule([=[match:class ^(blueman-manager)$, size (monitor_w*0.45) (monitor_h*0.45)]=], false)
rule([=[match:class ^(blueman-manager)$, center on]=], false)

rule([=[match:class ^(net\.davidotek\.pupgui2)$, float on]=], false)
rule([=[match:class ^(net\.davidotek\.pupgui2)$, size (monitor_w*0.45) (monitor_h*0.45)]=], false)
rule([=[match:class ^(net\.davidotek\.pupgui2)$, center on]=], false)

rule([=[match:class ^(btop)$, float on]=], false)
rule([=[match:class ^(btop)$, size (monitor_w*0.80) (monitor_h*0.85)]=], false)
rule([=[match:class ^(btop)$, center on]=], false)

-- Force Tile
rule([=[match:class ^(steam|com\.valvesoftware\.Steam)$, match:title ^(Steam)$, tile on]=], false)
rule([=[match:class ^(steam|com\.valvesoftware\.Steam)$, match:title ^(Friends List)$, tile on]=], false)

-- ───────────────────────────────────────────────────────────────────────────────
-- SCREENSHARE GUARD
-- ───────────────────────────────────────────────────────────────────────────────

rule([=[no_screen_share on,      match:class ^(Bitwarden|com\.bitwarden\.desktop|KeePassXC|org\.keepassxc\.KeePassXC|1Password|com\.1password\.1password|Enpass|org\.gnome\.Secrets|org\.gnome\.seahorse\.Application|OTPClient|otpclient|org\.rasalminen\.OTPClient|Mullvad Browser|mullvad-browser|com\.mullvad\.Browser|localsend|LocalSend|org\.localsend\.localsend|io\.github\.localsend\.localsend)$]=], false)
rule([=[no_screen_share on,      match:class ^(firefox)$, match:title ^(Extension: \(Bitwarden Password Manager\).*)$]=], false)
rule([=[no_screen_share on,      match:class ^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$, match:title ^(Bitwarden Password Manager.*)$]=], false)
rule([=[no_screen_share on,      match:class ^(org\.telegram\.desktop|TelegramDesktop|telegram-desktop|Telegram)$]=], false)
rule([=[no_screen_share on,      match:class ^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$, match:title ^.*Telegram.*$]=], false)
rule([=[no_screen_share on,      match:class ^(Element|io\.element\.Element|im\.riot\.Riot|chat\.element\.desktop|SchildiChat|im\.fluffychat\.Fluffychat|Fractal|org\.gnome\.Fractal|nheko)$]=], false)
rule([=[no_screen_share on,      match:class ^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|Fluxer|fluxer)$]=], false)
rule([=[no_screen_share on,      match:class ^(com\.github\.IsmaelMartinez\.teams_for_linux)$]=], false)
rule([=[no_screen_share on,      match:class ^(Messages)$]=], false)

-- Layers (notifications/swaync are layer surfaces, not windows)
rule([=[no_screen_share on,      match:namespace ^(notifications|swaync.*)$]=], true)

-- optional
-- rule("no_screen_share on,    match:class ^(obs|com\.obsproject\.Studio|obs-studio|com\.obsproject\.Studio\.obs)$", false)
-- rule("no_screen_share on,    match:class ^(steam|com\.valvesoftware\.Steam)$", false)
-- rule("no_screen_share on,    match:class ^(rustdesk|com\.rustdesk\.RustDesk)$", false)
-- rule("no_screen_share on,    match:class ^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$", false)
-- rule("no_screen_share on,    match:class ^(wallpicker)$", false)
-- rule("no_screen_share on,    match:class ^(virt-manager)$", false)
-- rule("no_screen_share on,    match:class ^(Alacritty)$", false)
-- rule("no_screen_share on,    match:class ^(mpv)$", false)
-- rule("no_screen_share on,    match:namespace ^(ags)$", true)
-- rule("no_screen_share on,    match:namespace ^(logout_dialog)$", true)
-- rule("no_screen_share on,    match:namespace ^(waybar)$", true)

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
