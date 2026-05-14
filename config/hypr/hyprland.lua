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

hl.monitor({ output = [=[]=], mode = [=[preferred]=], position = [=[auto]=], scale = [=[auto]=], vrr = 0 })
hl.monitor({ output = [=[Virtual-1]=], mode = [=[1600x900@60]=], position = [=[auto]=], scale = 1, vrr = 0 })


-- ───────────────────────────────────────────────────────────────────────────────
-- ENV
-- ───────────────────────────────────────────────────────────────────────────────

hl.env([=[XDG_CURRENT_DESKTOP]=], [=[Hyprland]=])
hl.env([=[XDG_SESSION_DESKTOP]=], [=[Hyprland]=])
hl.env([=[XDG_SESSION_TYPE]=], [=[wayland]=])
hl.env([=[GDK_BACKEND]=], [=[wayland,x11,*]=])
hl.env([=[QT_QPA_PLATFORM]=], [=[wayland;xcb]=])
hl.env([=[CLUTTER_BACKEND]=], [=[wayland]=])
hl.env([=[QT_STYLE_OVERRIDE]=], [=[kvantum]=])
hl.env([=[QT_AUTO_SCREEN_SCALE_FACTOR]=], [=[1]=])
hl.env([=[QT_WAYLAND_DISABLE_WINDOWDECORATION]=], [=[1]=])
hl.env([=[QT_QPA_PLATFORMTHEME]=], [=[qt5ct]=])
hl.env([=[QT6CT_PLATFORM_PLUGIN]=], [=[qt6ct]=])
hl.env([=[QT_QUICK_CONTROLS_STYLE]=], [=[org.hyprland.style]=])
hl.env([=[MOZ_ENABLE_WAYLAND]=], [=[1]=])
hl.env([=[GDK_SCALE]=], [=[1]=])
hl.env([=[QT_SCALE_FACTOR]=], [=[1]=])
hl.env([=[XCURSOR_SIZE]=], [=[24]=])
hl.env([=[GTK_THEME]=], [=[Materia-dark]=])
hl.env([=[XCURSOR_THEME]=], [=[ComixCursors-White]=])
hl.env([=[GAMESCOPE_WSI]=], [=[vk_wayland]=])

-- Optional/problem-specific environment toggles.
-- hl.env([=[WLR_RENDERER_ALLOW_SOFTWARE]=], [=[0]=])
-- hl.env([=[WLR_DRM_NO_ATOMIC]=], [=[1]=]) -- Can help with some GPUs
-- hl.env([=[HYPRLAND_NO_RT]=], [=[1]=]) -- Disable realtime scheduling if having issues
-- hl.env([=[__GL_GSYNC_ALLOWED]=], [=[1]=])
-- hl.env([=[__GL_VRR_ALLOWED]=], [=[1]=])

-- NVIDIA/proprietary-driver-specific toggles.
-- hl.env([=[__GLX_VENDOR_LIBRARY_NAME]=], [=[nvidia]=]) -- NVIDIA GLX vendor
-- hl.env([=[LIBVA_DRIVER_NAME]=], [=[nvidia]=]) -- NVIDIA VA-API driver
-- hl.env([=[GBM_BACKEND]=], [=[nvidia-drm]=]) -- NVIDIA GBM backend


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

    hl.config({ ecosystem = { no_update_news = true } })
    hl.config({ ecosystem = { enforce_permissions = true } })

-- screencopy (direct capture)
hl.permission([=[/usr/bin/grim]=], [=[screencopy]=], [=[allow]=])
hl.permission([=[/usr/bin/wf-recorder]=], [=[screencopy]=], [=[allow]=])
hl.permission([=[/usr/bin/hyprpicker]=], [=[screencopy]=], [=[allow]=])
hl.permission([=[/usr/bin/hyprlock]=], [=[screencopy]=], [=[allow]=])
hl.permission([=[/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland]=], [=[screencopy]=], [=[allow]=])

-- plugin (hyprpm)
hl.permission([=[/usr/(bin|local/bin)/hyprpm]=], [=[plugin]=], [=[allow]=])

-- keyboard allowlist template (default is allow)
-- hl.permission([=[^(YOUR KEYBOARD NAME REGEX)$]=], [=[keyboard]=], [=[allow]=])
-- hl.permission([=[.*]=], [=[keyboard]=], [=[deny]=])

-- ───────────────────────────────────────────────────────────────────────────────
-- AUTOSTART
-- ───────────────────────────────────────────────────────────────────────────────

hl.on("hyprland.start", function() hl.exec_cmd([=[dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE]=]) end)

hl.on("hyprland.start", function() hl.exec_cmd([=[sh -lc '$HOME/.config/hypr/scripts/portal_fixup.sh']=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[gnome-keyring-daemon --start --password-store=secrets]=]) end)

-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/last_to_load_recorder.sh &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/waybar.sh start &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/waybar_ready_sound.sh &]=]) end)

hl.on("hyprland.start", function() hl.exec_cmd([=[hyprsunset &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[mako &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[nm-applet &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[blueman-applet &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[nwg-look -a &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[hypridle -c ~/.config/hypr/hypridle.conf &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/hyprpm-auto-reload.sh &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/awtwall-awtarchy-init.sh &]=]) end)
-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/wallpaper_engine.sh &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[sh -lc 'exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e "$HOME/.config/hypr/scripts/awtarchy-tips-tui.sh" --autostart']=]) end)
-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/miclock.sh &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[wl-paste --type text --watch cliphist store &]=]) end)
hl.on("hyprland.start", function() hl.exec_cmd([=[wl-paste --type image --watch cliphist store &]=]) end)

-- Optional: USB refresh helper
-- List USB devices:
-- lsusb
-- Map a device once:
-- ~/.config/hypr/scripts/usb_refresh_fixer.sh map 20b1:3008 ifi
--
-- Then optionally run at startup:
--
-- Non-audio USB device:
-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/usb_refresh_fixer.sh refresh myusb &]=]) end)
--
-- USB audio device, just refresh it and wait for the audio sink to exist again:
-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio ifi &]=]) end)
--
-- USB audio device, refresh it and force it as default sink:
-- hl.on("hyprland.start", function() hl.exec_cmd([=[~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio-default ifi &]=]) end)

-- ───────────────────────────────────────────────────────────────────────────────
-- LOOK & FEEL
-- ───────────────────────────────────────────────────────────────────────────────

    hl.config({ general = { gaps_in = 6 } })
    hl.config({ general = { gaps_out = 9 } })
    hl.config({ general = { border_size = 1 } })
hl.config({ general = { col = { active_border = [=[rgba(a0a0a0ff)]=] } } })
hl.config({ general = { col = { inactive_border = [=[rgba(4b4b4bff)]=] } } })
    hl.config({ general = { resize_on_border = true } })
    hl.config({ general = { allow_tearing = true } })
    hl.config({ general = { layout = [=[dwindle]=] } })

    hl.config({ decoration = { rounding = 0 } })
    hl.config({ decoration = { rounding_power = 2 } })
    hl.config({ decoration = { active_opacity = 1 } })
    hl.config({ decoration = { inactive_opacity = 1 } })

    -- Shaders (uncomment only one)
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/vibrance]=] } })
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/cathode_ray_tube_optional_vibrance]=] } })
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/subtle_crt]=] } })
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/gimmicky-crt]=] } })

    -- Shaders that require debug damage_tracking = 0 or you will see config errors.
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/vhs]=] } })
    -- hl.config({ decoration = { screen_shader = [=[~/.config/hypr/shaders/acid_trip]=] } })

        hl.config({ decoration = { shadow = { enabled = true } } })
        hl.config({ decoration = { shadow = { range = 4 } } })
        hl.config({ decoration = { shadow = { render_power = 3 } } })
        hl.config({ decoration = { shadow = { color = [=[rgba(1a1a1aee)]=] } } })

        hl.config({ decoration = { blur = { enabled = true } } })
        hl.config({ decoration = { blur = { size = 3 } } })
        hl.config({ decoration = { blur = { passes = 1 } } })
        hl.config({ decoration = { blur = { vibrancy = 0.1696 } } })

    hl.config({ debug = { damage_tracking = 2 } })

    -- Direct scanout: 0 = off, 1 = on, 2 = auto (only when content_type == "game")
    -- Reduces latency when a single fullscreen client (e.g. nested gamescope) owns the monitor.
    hl.config({ render = { direct_scanout = 2 } })

    -- Non-shader color management:
    -- 2 is the “DS + passthrough only” mode, which pairs cleanly with gamescope.
    hl.config({ render = { non_shader_cm = 2 } })

    -- Fullscreen HDR color-management auto-switch:
    -- cm_fs_passthrough was removed in Hyprland 0.55.
    hl.config({ render = { cm_auto_hdr = 1 } })


-- opengl {
--     nvidia_anti_flicker = true
-- }

    hl.config({ cursor = { sync_gsettings_theme = true } })
    hl.config({ cursor = { no_hardware_cursors = 2 } })
    hl.config({ cursor = { zoom_disable_aa = true } })
    hl.config({ cursor = { no_warps = false } })
    hl.config({ cursor = { persistent_warps = false } })
    hl.config({ cursor = { warp_on_change_workspace = 0 } })
    hl.config({ cursor = { enable_hyprcursor = true } })

    hl.config({ animations = { enabled = true } })
    hl.curve([=[easeOutQuint]=], { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.curve([=[easeInOutSlight]=], { type = "bezier", points = { { 0.4, 0.1 }, { 0.2, 1 } } })
    hl.curve([=[linear]=], { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
    hl.curve([=[softFade]=], { type = "bezier", points = { { 0.2, 0.5 }, { 0.3, 1 } } })
    hl.curve([=[fastOut]=], { type = "bezier", points = { { 0.2, 0 }, { 0.6, 1 } } })
    hl.animation({ leaf = [=[global]=], enabled = 1, speed = 8, bezier = [=[default]=] })
    hl.animation({ leaf = [=[border]=], enabled = 1, speed = 3, bezier = [=[easeOutQuint]=] })
    hl.animation({ leaf = [=[borderangle]=], enabled = 1, speed = 40, bezier = [=[linear]=], style = [=[once]=] })
    hl.animation({ leaf = [=[windows]=], enabled = 1, speed = 3, bezier = [=[easeOutQuint]=] })
    hl.animation({ leaf = [=[windowsIn]=], enabled = 1, speed = 2, bezier = [=[easeOutQuint]=], style = [=[popin 87%]=] })
    hl.animation({ leaf = [=[windowsOut]=], enabled = 1, speed = 1.5, bezier = [=[linear]=], style = [=[popin 87%]=] })
    hl.animation({ leaf = [=[fadeIn]=], enabled = 1, speed = 1.5, bezier = [=[softFade]=] })
    hl.animation({ leaf = [=[fadeOut]=], enabled = 1, speed = 1.3, bezier = [=[softFade]=] })
    hl.animation({ leaf = [=[fade]=], enabled = 1, speed = 2, bezier = [=[softFade]=] })
    hl.animation({ leaf = [=[layers]=], enabled = 1, speed = 2.5, bezier = [=[easeInOutSlight]=] })
    hl.animation({ leaf = [=[layersIn]=], enabled = 1, speed = 2, bezier = [=[easeInOutSlight]=], style = [=[fade]=] })
    hl.animation({ leaf = [=[layersOut]=], enabled = 1, speed = 1.5, bezier = [=[fastOut]=], style = [=[fade]=] })
    hl.animation({ leaf = [=[fadeLayersIn]=], enabled = 1, speed = 1.4, bezier = [=[softFade]=] })
    hl.animation({ leaf = [=[fadeLayersOut]=], enabled = 1, speed = 1.3, bezier = [=[softFade]=] })
    hl.animation({ leaf = [=[workspaces]=], enabled = 1, speed = 1.8, bezier = [=[easeInOutSlight]=], style = [=[fade]=] })
    hl.animation({ leaf = [=[workspacesIn]=], enabled = 1, speed = 1.3, bezier = [=[softFade]=], style = [=[fade]=] })
    hl.animation({ leaf = [=[workspacesOut]=], enabled = 1, speed = 1.4, bezier = [=[softFade]=], style = [=[fade]=] })
    hl.animation({ leaf = [=[specialWorkspace]=], enabled = 1, speed = 1.9, bezier = [=[easeInOutSlight]=], style = [=[fade]=] })

    hl.config({ dwindle = { preserve_split = true } })
    hl.config({ dwindle = { force_split = 0 } })
    hl.config({ dwindle = { special_scale_factor = 0.9 } })
    -- hl.config({ dwindle = { smart_split = true } })
    -- hl.config({ dwindle = { single_window_aspect_ratio = [=[1 0.6852]=] } })

    hl.config({ master = { new_status = [=[master]=] } })
    hl.config({ master = { new_on_top = 1 } })
    hl.config({ master = { mfact = 0.5 } })

    -- Visuals (startup / defaults)
    hl.config({ misc = { force_default_wallpaper = -1 } })
    hl.config({ misc = { disable_hyprland_logo = true } })
    hl.config({ misc = { disable_splash_rendering = true } })

    -- Rendering / display behavior
    hl.config({ misc = { vrr = 2 } })
    hl.config({ misc = { mouse_move_enables_dpms = true } })

    -- Input convenience
    hl.config({ misc = { middle_click_paste = false } })

    -- Focus / workspace behavior
    hl.config({ misc = { focus_on_activate = false } })
    hl.config({ misc = { initial_workspace_tracking = 0 } })

    -- Swallowing (terminal -> spawned app)
    hl.config({ misc = { enable_swallow = false } })
    hl.config({ misc = { swallow_regex = [=[^([Aa]lacritty)$]=] } })

    -- Stability / UX dialogs
    hl.config({ misc = { enable_anr_dialog = true } })
    hl.config({ misc = { allow_session_lock_restore = true } })

    -- Suppress helper warnings/checks
    hl.config({ misc = { disable_hyprland_guiutils_check = true } })

    hl.config({ xwayland = { enabled = true } })
    hl.config({ xwayland = { force_zero_scaling = true } })

        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_height = 20 } } }) end

        -- bar background
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_color = [=[rgb(1e1e1e)]=] } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_blur = false } } }) end

        -- title text (optional)
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { col = { text = [=[rgb(d0d0d0)]=] } } } }) end

        -- layout
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_title_enabled = true } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_buttons_alignment = [=[right]=] } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_padding = 5 } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_button_padding = 7 } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_text_align = [=[left]=] } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_text_size = 10 } } }) end
        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { bar_text_font = [=[NotoSansM Nerd Font Mono]=] } } }) end

        -- buttons: same as bar background; icons are light gray
        if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then hl.plugin.hyprbars.add_button({ bg_color = [=[rgb(1e1e1e)]=], fg_color = [=[rgb(d0d0d0)]=], size = 20, icon = [=[]=], action = [=[hyprctl dispatch 'hl.dsp.window.close()']=] }) end
        if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then hl.plugin.hyprbars.add_button({ bg_color = [=[rgb(1e1e1e)]=], fg_color = [=[rgb(d0d0d0)]=], size = 20, icon = [=[󰨤]=], action = [=[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']=] }) end
        if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then hl.plugin.hyprbars.add_button({ bg_color = [=[rgb(1e1e1e)]=], fg_color = [=[rgb(d0d0d0)]=], size = 20, icon = [=[]=], action = [=[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']=] }) end

        if hl.plugin and hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { on_double_click = [=[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']=] } } }) end

-- ───────────────────────────────────────────────────────────────────────────────
-- INPUT
-- ───────────────────────────────────────────────────────────────────────────────

    hl.config({ input = { kb_layout = [=[us]=] } })
    hl.config({ input = { follow_mouse = 1 } })
    hl.config({ input = { repeat_delay = 250 } })
    hl.config({ input = { repeat_rate = 35 } })
    hl.config({ input = { numlock_by_default = true } })

        hl.config({ input = { touchpad = { natural_scroll = true } } })
        hl.config({ input = { touchpad = { disable_while_typing = true } } })
        hl.config({ input = { touchpad = { clickfinger_behavior = true } } })
        hl.config({ input = { touchpad = { scroll_factor = 0.5 } } })

    -- Mouse: No acceleration (1:1 raw input)
    hl.config({ input = { accel_profile = [=[flat]=] } })
    hl.config({ input = { sensitivity = 0 } })
    hl.config({ input = { force_no_accel = 1 } })

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
hl.gesture({ fingers = 3, direction = [=[horizontal]=], action = [=[workspace]=] })

-- ───────────────────────────────────────────────────────────────────────────────
-- MODIFIERS
-- ───────────────────────────────────────────────────────────────────────────────

local mod = [=[ALT]=]
local super = [=[SUPER]=]
local tempalt = [=[ALT]=]
local submap_file = [=[/tmp/hypr-submap]=]

-- ───────────────────────────────────────────────────────────────────────────────
-- LAUNCHERS / COMMANDS
-- ───────────────────────────────────────────────────────────────────────────────

-- Base paths (using variables instead of repeating ~/.config/hypr/scripts everywhere)
local hypr_dir = [=[~/.config/hypr]=]
local hypr_scripts = [=[~/.config/hypr/scripts]=]
local launch = [=[~/.config/hypr/scripts/launch_handler.sh]=]

-- Core apps (define before anything that uses them)
local terminal = [=[alacritty]=]
local web_browser = [=[firefox]=]
local calculator = [=[speedcrunch]=]
local yazi = [=[alacritty -e yazi]=]

-- App/menu launchers
local app_launcher = [=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]
local wlogout = [=[~/.config/hypr/scripts/wlogout_toggle.sh]=]
local hypr_quicksettings = [=[~/.config/hypr/scripts/launch_handler.sh hypr_quicksettings "alacritty --class hypr_quicksettings -e ~/.config/hypr/scripts/hypr_quicksettings.sh"]=]
local awtarchy_tips_tui = [=[~/.config/hypr/scripts/launch_handler.sh awtarchy-tips-tui "alacritty --class awtarchy-tips-tui -e ~/.config/hypr/scripts/awtarchy-tips-tui.sh"]=]

-- Audio
local wiremix = [=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]
local pavucontrol = [=[~/.config/hypr/scripts/launch_handler.sh pavucontrol "pavucontrol"]=]
local pulsemixer = [=[~/.config/hypr/scripts/launch_handler.sh pulsemixer "alacritty --class Pulsemixer -e pulsemixer"]=]
local mute_unmute = [=[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle]=]
local play_pause = [=[~/.config/hypr/scripts/play_pause.sh]=]

-- Bars / UI toggles
local hyprbars_toggle = [=[~/.config/hypr/scripts/hyprbars_toggle.sh]=]
local waybar_toggle = [=[~/.config/hypr/scripts/waybar_toggle.sh]=]
local waybar_flip = [=[~/.config/hypr/scripts/waybar_flip.sh]=]
local waybar_rotate = [=[~/.config/hypr/scripts/waybar_rotate.sh]=]
local toggle_animations = [=[~/.config/hypr/scripts/toggle_animations.sh]=]
local mako_dismiss = [=[~/.config/hypr/scripts/mako_dismiss.sh]=]

-- Themes / wallpaper
local wallpicker = [=[~/.config/hypr/scripts/launch_handler.sh wallpicker "alacritty --class wallpicker -e awtwall --resume"]=]
local theme_select = [=[~/.config/hypr/scripts/theme_select.sh]=]

-- Capture / clipboard / QR
local screenshot_select = [=[env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN ~/.config/hypr/scripts/screenshot_area.sh]=]
local screenshot_full = [=[~/.config/hypr/scripts/screenshot_fullscreen.sh]=]
local screenshot_display = [=[~/.config/hypr/scripts/screenshot_display.sh]=]
local gif_capture = [=[~/.config/hypr/scripts/gif_capture.sh]=]
local clipboard_history = [=[~/.config/hypr/scripts/cliphist-fuzzel.sh]=]
local qr_scan = [=[~/.config/hypr/scripts/qr_scan.sh]=]

-- Utilities
local workspace_mix = [=[~/.config/hypr/scripts/workspace_mix.sh]=]
local zoom = [=[~/.config/hypr/scripts/zoom.sh]=]
local hyprpicker = [=[hyprpicker -a -f hex]=]
local hypr_ddc_brightness = [=[~/.config/hypr/scripts/hypr-ddc-brightness.sh]=]
local vibrance_shader = [=[~/.config/hypr/scripts/vibrance_shader.sh]=]
local hyprsunset_ctl = [=[~/.config/hypr/scripts/hyprsunset_ctl.sh]=]

-- Terminal tools
local maccel = [=[~/.config/hypr/scripts/launch_handler.sh maccel "alacritty --class maccel -e maccel"]=]
local smtty = [=[~/.config/hypr/scripts/launch_handler.sh smtty "alacritty --class smtty -e smtty"]=]
local btop = [=[~/.config/hypr/scripts/launch_handler.sh btop "alacritty --class btop -e btop"]=]

-- Complex one-off
local smtty_O = [=[sh -lc 'if hyprctl clients | grep -q "class: smtty-O"; then hyprctl dispatch closewindow class:smtty-O; else alacritty --class smtty-O -e sh -lc '"'"'smtty -O; printf "\n[smtty -O finished]\nPress ENTER to close..."; read -r _'"'"'; fi']=]

-- Submap references (Toggle on)  [write name to file on entry]
local noalt_on = [=[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']=]
local mouse_on = [=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=]
local vm_on = [=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=]

-- ───────────────────────────────────────────────────────────────────────────────
-- DEFAULT MODE (ALT is modifier; SUPER is app/meta)
-- ───────────────────────────────────────────────────────────────────────────────

-- App launchers / terminals
hl.bind([=[ALT + P]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]), {})
hl.bind([=[SUPER + D]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]), {})
hl.bind([=[ALT + SHIFT + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[SUPER + SHIFT + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[SUPER + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[ALT + SHIFT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh btop "alacritty --class btop -e btop"]=]), {})
hl.bind([=[SUPER + SHIFT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh btop "alacritty --class btop -e btop"]=]), {})
hl.bind([=[SUPER + B]=], hl.dsp.exec_cmd([=[firefox]=]), {})
hl.bind([=[ALT + SHIFT + C]=], hl.dsp.exec_cmd([=[speedcrunch]=]), {})
hl.bind([=[SUPER + SHIFT + C]=], hl.dsp.exec_cmd([=[speedcrunch]=]), {})
hl.bind([=[ALT + SHIFT + M]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh maccel "alacritty --class maccel -e maccel"]=]), {})
hl.bind([=[SUPER + SHIFT + M]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh maccel "alacritty --class maccel -e maccel"]=]), {})

-- Audio mixer
hl.bind([=[ALT + V]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]), {})
hl.bind([=[SUPER + V]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]), {})

-- Mako dismiss
hl.bind([=[ALT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + CTRL + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + SHIFT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + CTRL + SHIFT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[SUPER + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})

-- Terminal utilities (smtty)
hl.bind([=[SUPER + ALT + G]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh smtty "alacritty --class smtty -e smtty"]=]), {})
hl.bind([=[SUPER + ALT + L]=], hl.dsp.exec_cmd([=[smtty -S -l]=]), {})
hl.bind([=[SUPER + ALT + O]=], hl.dsp.exec_cmd([=[sh -lc 'if hyprctl clients | grep -q "class: smtty-O"; then hyprctl dispatch closewindow class:smtty-O; else alacritty --class smtty-O -e sh -lc '"'"'smtty -O; printf "\n[smtty -O finished]\nPress ENTER to close..."; read -r _'"'"'; fi']=]), {})
hl.bind([=[SUPER + ALT + K]=], hl.dsp.exec_cmd([=[smtty -k]=]), {})

-- UI / compositor toggles
hl.bind([=[SUPER + ALT + T]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprbars_toggle.sh]=]), {})
hl.bind([=[SUPER + ALT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_rotate.sh]=]), {})
hl.bind([=[SUPER + ALT + CTRL + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_toggle.sh]=]), {})
hl.bind([=[SUPER + CTRL + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_flip.sh]=]), {})
hl.bind([=[SUPER + A]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/toggle_animations.sh]=]), {})

-- Brightness / color temperature
hl.bind([=[SUPER + ALT + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh hypr_quicksettings "alacritty --class hypr_quicksettings -e ~/.config/hypr/scripts/hypr_quicksettings.sh"]=]), {})
hl.bind([=[SUPER + ALT + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hypr-ddc-brightness.sh up 5]=]), {})
hl.bind([=[SUPER + ALT + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hypr-ddc-brightness.sh down 5]=]), {})
hl.bind([=[SUPER + ALT + CTRL + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh up]=]), {})
hl.bind([=[SUPER + ALT + CTRL + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh down]=]), {})
hl.bind([=[SUPER + ALT + CTRL + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh toggle]=]), {})

-- File managers / system
hl.bind([=[SUPER + E]=], hl.dsp.exec_cmd([=[pcmanfm-qt]=]), {})
hl.bind([=[SUPER + SHIFT + E]=], hl.dsp.exec_cmd([=[alacritty -e yazi]=]), {})
hl.bind([=[SUPER + L]=], hl.dsp.exec_cmd([=[hyprlock]=]), {})
hl.bind([=[SUPER + I]=], hl.dsp.exec_cmd([=[hyprpicker -a -f hex]=]), {})
hl.bind([=[SUPER + P]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/wlogout_toggle.sh]=]), {})

-- Themes / wallpaper
hl.bind([=[SUPER + W]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wallpicker "alacritty --class wallpicker -e awtwall --resume"]=]), {})
hl.bind([=[SUPER + SHIFT + W]=], hl.dsp.exec_cmd([=[awtwall --random-current]=]), {})
hl.bind([=[SUPER + CTRL + W]=], hl.dsp.exec_cmd([=[awtwall --random-all]=]), {})
hl.bind([=[SUPER + ALT + W]=], hl.dsp.exec_cmd([=[awtwall --random-all-different]=]), {})
hl.bind([=[SUPER + T]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/theme_select.sh]=]), {})

-- Capture / clipboard / misc
hl.bind([=[SUPER + C]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/cliphist-fuzzel.sh]=]), {})
hl.bind([=[SUPER + S]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/qr_scan.sh]=]), {})
hl.bind([=[SUPER + SHIFT + S]=], hl.dsp.exec_cmd([=[env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN ~/.config/hypr/scripts/screenshot_area.sh]=]), {})
hl.bind([=[SUPER + SHIFT + F]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/screenshot_fullscreen.sh]=]), {})
hl.bind([=[SUPER + SHIFT + D]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/screenshot_display.sh]=]), {})
hl.bind([=[SUPER + SHIFT + G]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/gif_capture.sh]=]), {})

-- Window management
hl.bind([=[SUPER + Q]=], hl.dsp.window.close(), {})
hl.bind([=[SUPER + SHIFT + Q]=], hl.dsp.window.close(), {})
hl.bind([=[ALT + SHIFT + Q]=], hl.dsp.window.close(), {})
hl.bind([=[ALT + F4]=], hl.dsp.window.close(), {})
hl.bind([=[SUPER + ALT + Q]=], hl.dsp.exec_cmd([=[hyprctl kill]=]), {})
hl.bind([=[ALT + Y]=], hl.dsp.window.pin(), {})
hl.bind([=[SUPER + Y]=], hl.dsp.window.pin(), {})
hl.bind([=[ALT + R]=], hl.dsp.layout([=[swapsplit]=]), {})
hl.bind([=[ALT + SHIFT + R]=], hl.dsp.layout([=[togglesplit]=]), {})
hl.bind([=[SUPER + R]=], hl.dsp.layout([=[swapsplit]=]), {})
hl.bind([=[SUPER + SHIFT + R]=], hl.dsp.layout([=[togglesplit]=]), {})
hl.bind([=[ALT + F]=], hl.dsp.window.float({ action = "toggle" }), {})
hl.bind([=[ALT + CTRL + F]=], hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), {})
hl.bind([=[SUPER + F]=], hl.dsp.window.float({ action = "toggle" }), {})
hl.bind([=[SUPER + CTRL + F]=], hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), {})
hl.bind([=[ALT + TAB]=], hl.dsp.window.cycle_next({ next = true }), {})
hl.bind([=[ALT + TAB]=], (hl.dsp.window.bring_to_top and hl.dsp.window.bring_to_top() or hl.dsp.window.alter_zorder({ mode = "top" })), {})
hl.bind([=[ALT + SHIFT + TAB]=], hl.dsp.window.cycle_next({ next = false }), {})

-- Focus move (ALT/SUPER arrows)
hl.bind([=[ALT + left]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[ALT + right]=], hl.dsp.focus({ direction = [=[r]=] }), {})
hl.bind([=[ALT + up]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[ALT + down]=], hl.dsp.focus({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + left]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + right]=], hl.dsp.focus({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + up]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + down]=], hl.dsp.focus({ direction = [=[d]=] }), {})
-- ALT/SUPER hjkl
hl.bind([=[ALT + h]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[ALT + j]=], hl.dsp.focus({ direction = [=[d]=] }), {})
hl.bind([=[ALT + k]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[ALT + l]=], hl.dsp.focus({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + h]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + j]=], hl.dsp.focus({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + k]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + l]=], hl.dsp.focus({ direction = [=[r]=] }), {})

-- Window move (ALT/SUPER+SHIFT arrows)
hl.bind([=[ALT + SHIFT + left]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[ALT + SHIFT + right]=], hl.dsp.window.move({ direction = [=[r]=] }), {})
hl.bind([=[ALT + SHIFT + up]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[ALT + SHIFT + down]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + SHIFT + left]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + SHIFT + right]=], hl.dsp.window.move({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + SHIFT + up]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + SHIFT + down]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
-- ALT/SUPER+SHIFT hjkl
hl.bind([=[ALT + SHIFT + h]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[ALT + SHIFT + j]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
hl.bind([=[ALT + SHIFT + k]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[ALT + SHIFT + l]=], hl.dsp.window.move({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + SHIFT + h]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + SHIFT + j]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + SHIFT + k]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + SHIFT + l]=], hl.dsp.window.move({ direction = [=[r]=] }), {})

-- Send current workspace to monitor (ALT/SUPER+CTRL+SHIFT numbers)
hl.bind([=[ALT + CTRL + SHIFT + left]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[ALT + CTRL + SHIFT + right]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
hl.bind([=[ALT + CTRL + SHIFT + up]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[ALT + CTRL + SHIFT + down]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + left]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + right]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + up]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + down]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
-- ALT/SUPER+CTRL+SHIFT "[" or "]"
hl.bind([=[ALT + CTRL + SHIFT + bracketleft]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[ALT + CTRL + SHIFT + bracketright]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + bracketleft]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + bracketright]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})

-- Workspaces (ALT/SUPER numbers)
hl.bind([=[ALT + 1]=], hl.dsp.focus({ workspace = 1 }), {})
hl.bind([=[ALT + 2]=], hl.dsp.focus({ workspace = 2 }), {})
hl.bind([=[ALT + 3]=], hl.dsp.focus({ workspace = 3 }), {})
hl.bind([=[ALT + 4]=], hl.dsp.focus({ workspace = 4 }), {})
hl.bind([=[ALT + 5]=], hl.dsp.focus({ workspace = 5 }), {})
hl.bind([=[ALT + 6]=], hl.dsp.focus({ workspace = 6 }), {})
hl.bind([=[ALT + 7]=], hl.dsp.focus({ workspace = 7 }), {})
hl.bind([=[ALT + 8]=], hl.dsp.focus({ workspace = 8 }), {})
hl.bind([=[ALT + 9]=], hl.dsp.focus({ workspace = 9 }), {})
hl.bind([=[ALT + 0]=], hl.dsp.focus({ workspace = 10 }), {})
hl.bind([=[SUPER + 1]=], hl.dsp.focus({ workspace = 1 }), {})
hl.bind([=[SUPER + 2]=], hl.dsp.focus({ workspace = 2 }), {})
hl.bind([=[SUPER + 3]=], hl.dsp.focus({ workspace = 3 }), {})
hl.bind([=[SUPER + 4]=], hl.dsp.focus({ workspace = 4 }), {})
hl.bind([=[SUPER + 5]=], hl.dsp.focus({ workspace = 5 }), {})
hl.bind([=[SUPER + 6]=], hl.dsp.focus({ workspace = 6 }), {})
hl.bind([=[SUPER + 7]=], hl.dsp.focus({ workspace = 7 }), {})
hl.bind([=[SUPER + 8]=], hl.dsp.focus({ workspace = 8 }), {})
hl.bind([=[SUPER + 9]=], hl.dsp.focus({ workspace = 9 }), {})
hl.bind([=[SUPER + 0]=], hl.dsp.focus({ workspace = 10 }), {})

-- Prev/next workspace with (ALT/SUPER "[" or "]")
hl.bind([=[ALT + bracketleft]=], hl.dsp.focus({ workspace = [=[-1]=] }), {})
hl.bind([=[ALT + bracketright]=], hl.dsp.focus({ workspace = [=[+1]=] }), {})
hl.bind([=[SUPER + bracketleft]=], hl.dsp.focus({ workspace = [=[-1]=] }), {})
hl.bind([=[SUPER + bracketright]=], hl.dsp.focus({ workspace = [=[+1]=] }), {})

-- Move window to workspace (ALT/SUPER+SHIFT numbers)
hl.bind([=[ALT + SHIFT + 1]=], hl.dsp.window.move({ workspace = 1, follow = false }), {})
hl.bind([=[ALT + SHIFT + 2]=], hl.dsp.window.move({ workspace = 2, follow = false }), {})
hl.bind([=[ALT + SHIFT + 3]=], hl.dsp.window.move({ workspace = 3, follow = false }), {})
hl.bind([=[ALT + SHIFT + 4]=], hl.dsp.window.move({ workspace = 4, follow = false }), {})
hl.bind([=[ALT + SHIFT + 5]=], hl.dsp.window.move({ workspace = 5, follow = false }), {})
hl.bind([=[ALT + SHIFT + 6]=], hl.dsp.window.move({ workspace = 6, follow = false }), {})
hl.bind([=[ALT + SHIFT + 7]=], hl.dsp.window.move({ workspace = 7, follow = false }), {})
hl.bind([=[ALT + SHIFT + 8]=], hl.dsp.window.move({ workspace = 8, follow = false }), {})
hl.bind([=[ALT + SHIFT + 9]=], hl.dsp.window.move({ workspace = 9, follow = false }), {})
hl.bind([=[ALT + SHIFT + 0]=], hl.dsp.window.move({ workspace = 10, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 1]=], hl.dsp.window.move({ workspace = 1, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 2]=], hl.dsp.window.move({ workspace = 2, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 3]=], hl.dsp.window.move({ workspace = 3, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 4]=], hl.dsp.window.move({ workspace = 4, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 5]=], hl.dsp.window.move({ workspace = 5, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 6]=], hl.dsp.window.move({ workspace = 6, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 7]=], hl.dsp.window.move({ workspace = 7, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 8]=], hl.dsp.window.move({ workspace = 8, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 9]=], hl.dsp.window.move({ workspace = 9, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 0]=], hl.dsp.window.move({ workspace = 10, follow = false }), {})

-- Resize (ALT/SUPER+CTRL arrows / hold)
hl.bind([=[ALT + CTRL + right]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + left]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + up]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + down]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + right]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + left]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + up]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + down]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
-- ALT/SUPER+CTRL hjkl
hl.bind([=[ALT + CTRL + h]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + j]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + k]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[ALT + CTRL + l]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + h]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + j]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + k]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + l]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })

-- Mouse (ALT/SUPER mouse-left/right / hold)
hl.bind([=[ALT + mouse:272]=], hl.dsp.window.drag(), { mouse = true })
hl.bind([=[ALT + mouse:273]=], hl.dsp.window.resize(), { mouse = true })
hl.bind([=[SUPER + mouse:272]=], hl.dsp.window.drag(), { mouse = true })
hl.bind([=[SUPER + mouse:273]=], hl.dsp.window.resize(), { mouse = true })

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
hl.bind([=[SUPER + ALT + bracketright]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh up]=]), {})
hl.bind([=[SUPER + ALT + bracketleft]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh down]=]), {})
hl.bind([=[SUPER + ALT + backslash]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh toggle]=]), {})

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
hl.bind([=[SUPER + ALT + CTRL + 1]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 1]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 2]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 2]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 3]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 3]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 4]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 4]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 5]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 5]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 6]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 6]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 7]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 7]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 8]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 8]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 9]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 9]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 0]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 10]=]), {})
hl.bind([=[SUPER + ALT + CTRL + F]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh focus]=]), {})
hl.bind([=[SUPER + ALT + CTRL + R]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh restore]=]), {})

-- Zoom script (SUPER +/-)
hl.bind([=[SUPER + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh +]=]), { repeating = true })
hl.bind([=[SUPER + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh -]=]), { repeating = true })
hl.bind([=[SUPER + SHIFT + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh ++]=]), { repeating = true })
hl.bind([=[SUPER + SHIFT + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh --]=]), { repeating = true })
hl.bind([=[SUPER + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh reset]=]), {})
hl.bind([=[SUPER + backslash]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh rigid]=]), {})
hl.bind([=[SUPER + CTRL + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh + step:5%]=]), { repeating = true })
hl.bind([=[SUPER + CTRL + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh - step:5%]=]), { repeating = true })

-- Scratchpad (SUPER+x,X)
hl.bind([=[SUPER + X]=], hl.dsp.workspace.toggle_special([=[magic]=]), {})
hl.bind([=[SUPER + SHIFT + X]=], hl.dsp.window.move({ workspace = [=[special:magic]=], follow = true }), {})

-- Misc (SUPER+F12)
hl.bind([=[SUPER + F12]=], hl.dsp.exec_cmd([=[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']=]), {})
hl.bind([=[SUPER + CTRL + F12]=], hl.dsp.exec_cmd([=[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]=]), {})

-- Media & Brightness
hl.bind([=[XF86AudioRaiseVolume]=], hl.dsp.exec_cmd([=[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioLowerVolume]=], hl.dsp.exec_cmd([=[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioMute]=], hl.dsp.exec_cmd([=[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioMicMute]=], hl.dsp.exec_cmd([=[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]=]), { repeating = true, locked = true })
hl.bind([=[XF86MonBrightnessUp]=], hl.dsp.exec_cmd([=[brightnessctl -e4 -n2 set 5%+]=]), { repeating = true, locked = true })
hl.bind([=[XF86MonBrightnessDown]=], hl.dsp.exec_cmd([=[brightnessctl -e4 -n2 set 5%-]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioPlay]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/play_pause.sh]=]), { locked = true })
hl.bind([=[XF86AudioNext]=], hl.dsp.exec_cmd([=[playerctl next]=]), { locked = true })
hl.bind([=[XF86AudioPrev]=], hl.dsp.exec_cmd([=[playerctl previous]=]), { locked = true })
hl.bind([=[SUPER + M]=], hl.dsp.exec_cmd([=[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle]=]), {})

-- Submap binds                        (Toggle on/off)
hl.bind([=[SUPER + ALT + N]=], hl.dsp.exec_cmd([=[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']=]), {})
hl.bind([=[SUPER + ALT + M]=], hl.dsp.exec_cmd([=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=]), {})
hl.bind([=[SUPER + ALT + V]=], hl.dsp.exec_cmd([=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=]), {})

-- ───────────────────────────────────────────────────────────────────────────────
-- noalt SUBMAP; alt is disabled for most tasks
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("noalt", function()

-- Submap references in "noalt" (toggle off/on)  [empty file on exit]
local noalt_off = [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]
local mouse_on = [=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=]
local vm_on = [=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=]

-- App launchers / terminals in "noalt"
hl.bind([=[ALT + P]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]), {})
hl.bind([=[SUPER + D]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]), {})
hl.bind([=[ALT + SHIFT + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[SUPER + SHIFT + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[SUPER + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[ALT + SHIFT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh btop "alacritty --class btop -e btop"]=]), {})
hl.bind([=[SUPER + SHIFT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh btop "alacritty --class btop -e btop"]=]), {})
hl.bind([=[SUPER + B]=], hl.dsp.exec_cmd([=[firefox]=]), {})
hl.bind([=[ALT + SHIFT + C]=], hl.dsp.exec_cmd([=[speedcrunch]=]), {})
hl.bind([=[SUPER + SHIFT + C]=], hl.dsp.exec_cmd([=[speedcrunch]=]), {})
hl.bind([=[ALT + SHIFT + M]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh maccel "alacritty --class maccel -e maccel"]=]), {})
hl.bind([=[SUPER + SHIFT + M]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh maccel "alacritty --class maccel -e maccel"]=]), {})

-- Audio mixer in "noalt"
hl.bind([=[ALT + V]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]), {})
hl.bind([=[SUPER + V]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]), {})

-- Mako dismiss in "noalt"
hl.bind([=[ALT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + CTRL + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + SHIFT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[ALT + CTRL + SHIFT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})
hl.bind([=[SUPER + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), {})

-- Terminal utilities (smtty) in "noalt"
hl.bind([=[SUPER + ALT + G]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh smtty "alacritty --class smtty -e smtty"]=]), {})
hl.bind([=[SUPER + ALT + L]=], hl.dsp.exec_cmd([=[smtty -S -l]=]), {})
hl.bind([=[SUPER + ALT + O]=], hl.dsp.exec_cmd([=[sh -lc 'if hyprctl clients | grep -q "class: smtty-O"; then hyprctl dispatch closewindow class:smtty-O; else alacritty --class smtty-O -e sh -lc '"'"'smtty -O; printf "\n[smtty -O finished]\nPress ENTER to close..."; read -r _'"'"'; fi']=]), {})
hl.bind([=[SUPER + ALT + K]=], hl.dsp.exec_cmd([=[smtty -k]=]), {})

-- UI / compositor toggles in "noalt"
hl.bind([=[SUPER + ALT + T]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprbars_toggle.sh]=]), {})
hl.bind([=[SUPER + ALT + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_rotate.sh]=]), {})
hl.bind([=[SUPER + ALT + CTRL + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_toggle.sh]=]), {})
hl.bind([=[SUPER + CTRL + B]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/waybar_flip.sh]=]), {})
hl.bind([=[SUPER + A]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/toggle_animations.sh]=]), {})

-- Brightness / color temperature in "noalt"
hl.bind([=[SUPER + ALT + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh hypr_quicksettings "alacritty --class hypr_quicksettings -e ~/.config/hypr/scripts/hypr_quicksettings.sh"]=]), {})
hl.bind([=[SUPER + ALT + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hypr-ddc-brightness.sh up 5]=]), {})
hl.bind([=[SUPER + ALT + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hypr-ddc-brightness.sh down 5]=]), {})
hl.bind([=[SUPER + ALT + CTRL + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh up]=]), {})
hl.bind([=[SUPER + ALT + CTRL + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh down]=]), {})
hl.bind([=[SUPER + ALT + CTRL + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/hyprsunset_ctl.sh toggle]=]), {})

-- File managers / system in "noalt"
hl.bind([=[SUPER + E]=], hl.dsp.exec_cmd([=[pcmanfm-qt]=]), {})
hl.bind([=[SUPER + SHIFT + E]=], hl.dsp.exec_cmd([=[alacritty -e yazi]=]), {})
hl.bind([=[SUPER + L]=], hl.dsp.exec_cmd([=[hyprlock]=]), {})
hl.bind([=[SUPER + I]=], hl.dsp.exec_cmd([=[hyprpicker -a -f hex]=]), {})
hl.bind([=[SUPER + P]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/wlogout_toggle.sh]=]), {})

-- Themes / wallpaper
hl.bind([=[SUPER + W]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wallpicker "alacritty --class wallpicker -e awtwall --resume"]=]), {})
hl.bind([=[SUPER + SHIFT + W]=], hl.dsp.exec_cmd([=[awtwall --random-current]=]), {})
hl.bind([=[SUPER + CTRL + W]=], hl.dsp.exec_cmd([=[awtwall --random-all]=]), {})
hl.bind([=[SUPER + ALT + W]=], hl.dsp.exec_cmd([=[awtwall --random-all-different]=]), {})
hl.bind([=[SUPER + T]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/theme_select.sh]=]), {})

-- Capture / clipboard / misc in "noalt"
hl.bind([=[SUPER + C]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/cliphist-fuzzel.sh]=]), {})
hl.bind([=[SUPER + S]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/qr_scan.sh]=]), {})
hl.bind([=[SUPER + SHIFT + S]=], hl.dsp.exec_cmd([=[env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN ~/.config/hypr/scripts/screenshot_area.sh]=]), {})
hl.bind([=[SUPER + SHIFT + F]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/screenshot_fullscreen.sh]=]), {})
hl.bind([=[SUPER + SHIFT + D]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/screenshot_display.sh]=]), {})
hl.bind([=[SUPER + SHIFT + G]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/gif_capture.sh]=]), {})

-- Window management in "noalt"
hl.bind([=[SUPER + Q]=], hl.dsp.window.close(), {})
hl.bind([=[SUPER + SHIFT + Q]=], hl.dsp.window.close(), {})
hl.bind([=[ALT + F4]=], hl.dsp.window.close(), {})
hl.bind([=[SUPER + ALT + Q]=], hl.dsp.exec_cmd([=[hyprctl kill]=]), {})
hl.bind([=[SUPER + Y]=], hl.dsp.window.pin(), {})
hl.bind([=[SUPER + SHIFT + R]=], hl.dsp.layout([=[togglesplit]=]), {})
hl.bind([=[SUPER + R]=], hl.dsp.layout([=[swapsplit]=]), {})
hl.bind([=[SUPER + F]=], hl.dsp.window.float({ action = "toggle" }), {})
hl.bind([=[SUPER + CTRL + F]=], hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), {})
hl.bind([=[ALT + TAB]=], hl.dsp.window.cycle_next({ next = true }), {})
hl.bind([=[ALT + TAB]=], (hl.dsp.window.bring_to_top and hl.dsp.window.bring_to_top() or hl.dsp.window.alter_zorder({ mode = "top" })), {})
hl.bind([=[ALT + SHIFT + TAB]=], hl.dsp.window.cycle_next({ next = false }), {})

-- Focus move in "noalt" (SUPER arrows)
hl.bind([=[SUPER + left]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + right]=], hl.dsp.focus({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + up]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + down]=], hl.dsp.focus({ direction = [=[d]=] }), {})
-- SUPER hjkl
hl.bind([=[SUPER + h]=], hl.dsp.focus({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + j]=], hl.dsp.focus({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + k]=], hl.dsp.focus({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + l]=], hl.dsp.focus({ direction = [=[r]=] }), {})

-- Window move in "noalt" (SUPER+SHIFT arrows)
hl.bind([=[SUPER + SHIFT + left]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + SHIFT + right]=], hl.dsp.window.move({ direction = [=[r]=] }), {})
hl.bind([=[SUPER + SHIFT + up]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + SHIFT + down]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
-- SUPER+SHIFT hjkl
hl.bind([=[SUPER + SHIFT + h]=], hl.dsp.window.move({ direction = [=[l]=] }), {})
hl.bind([=[SUPER + SHIFT + j]=], hl.dsp.window.move({ direction = [=[d]=] }), {})
hl.bind([=[SUPER + SHIFT + k]=], hl.dsp.window.move({ direction = [=[u]=] }), {})
hl.bind([=[SUPER + SHIFT + l]=], hl.dsp.window.move({ direction = [=[r]=] }), {})

-- Send current workspace to monitor in "noalt" (SUPER+CTRL+SHIFT numbers)
hl.bind([=[SUPER + CTRL + SHIFT + left]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + right]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + up]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + down]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})
-- SUPER+CTRL+SHIFT "[" or "]"
hl.bind([=[SUPER + CTRL + SHIFT + bracketleft]=], hl.dsp.workspace.move({ monitor = [=[-1]=] }), {})
hl.bind([=[SUPER + CTRL + SHIFT + bracketright]=], hl.dsp.workspace.move({ monitor = [=[+1]=] }), {})

-- Workspaces in "noalt" (SUPER numbers)
hl.bind([=[SUPER + 1]=], hl.dsp.focus({ workspace = 1 }), {})
hl.bind([=[SUPER + 2]=], hl.dsp.focus({ workspace = 2 }), {})
hl.bind([=[SUPER + 3]=], hl.dsp.focus({ workspace = 3 }), {})
hl.bind([=[SUPER + 4]=], hl.dsp.focus({ workspace = 4 }), {})
hl.bind([=[SUPER + 5]=], hl.dsp.focus({ workspace = 5 }), {})
hl.bind([=[SUPER + 6]=], hl.dsp.focus({ workspace = 6 }), {})
hl.bind([=[SUPER + 7]=], hl.dsp.focus({ workspace = 7 }), {})
hl.bind([=[SUPER + 8]=], hl.dsp.focus({ workspace = 8 }), {})
hl.bind([=[SUPER + 9]=], hl.dsp.focus({ workspace = 9 }), {})
hl.bind([=[SUPER + 0]=], hl.dsp.focus({ workspace = 10 }), {})

-- Prev/next workspace with (SUPER "[" or "]")
hl.bind([=[SUPER + bracketleft]=], hl.dsp.focus({ workspace = [=[-1]=] }), {})
hl.bind([=[SUPER + bracketright]=], hl.dsp.focus({ workspace = [=[+1]=] }), {})

-- Move window to workspace in "noalt" (SUPER+SHIFT numbers)
hl.bind([=[SUPER + SHIFT + 1]=], hl.dsp.window.move({ workspace = 1, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 2]=], hl.dsp.window.move({ workspace = 2, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 3]=], hl.dsp.window.move({ workspace = 3, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 4]=], hl.dsp.window.move({ workspace = 4, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 5]=], hl.dsp.window.move({ workspace = 5, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 6]=], hl.dsp.window.move({ workspace = 6, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 7]=], hl.dsp.window.move({ workspace = 7, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 8]=], hl.dsp.window.move({ workspace = 8, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 9]=], hl.dsp.window.move({ workspace = 9, follow = false }), {})
hl.bind([=[SUPER + SHIFT + 0]=], hl.dsp.window.move({ workspace = 10, follow = false }), {})

-- Resize in "noalt" (SUPER+CTRL arrows / hold)
hl.bind([=[SUPER + CTRL + right]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + left]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + up]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + down]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
-- SUPER+CTRL hjkl
hl.bind([=[SUPER + CTRL + h]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + j]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + k]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[SUPER + CTRL + l]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })

-- Mouse in "noalt" (SUPER mouse-left/right / hold)
hl.bind([=[SUPER + mouse:272]=], hl.dsp.window.drag(), { mouse = true })
hl.bind([=[SUPER + mouse:273]=], hl.dsp.window.resize(), { mouse = true })

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\)
hl.bind([=[SUPER + ALT + bracketright]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh up]=]), {})
hl.bind([=[SUPER + ALT + bracketleft]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh down]=]), {})
hl.bind([=[SUPER + ALT + backslash]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/vibrance_shader.sh toggle]=]), {})

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
hl.bind([=[SUPER + ALT + CTRL + 1]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 1]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 2]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 2]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 3]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 3]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 4]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 4]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 5]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 5]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 6]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 6]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 7]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 7]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 8]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 8]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 9]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 9]=]), {})
hl.bind([=[SUPER + ALT + CTRL + 0]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh toggle 10]=]), {})
hl.bind([=[SUPER + ALT + CTRL + F]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh focus]=]), {})
hl.bind([=[SUPER + ALT + CTRL + R]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/workspace_mix.sh restore]=]), {})

-- Zoom script in "noalt" (SUPER +/-)
hl.bind([=[SUPER + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh +]=]), { repeating = true })
hl.bind([=[SUPER + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh -]=]), { repeating = true })
hl.bind([=[SUPER + SHIFT + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh ++]=]), { repeating = true })
hl.bind([=[SUPER + SHIFT + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh --]=]), { repeating = true })
hl.bind([=[SUPER + backspace]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh reset]=]), {})
hl.bind([=[SUPER + backslash]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh rigid]=]), {})
hl.bind([=[SUPER + CTRL + equal]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh + step:5%]=]), { repeating = true })
hl.bind([=[SUPER + CTRL + minus]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/zoom.sh - step:5%]=]), { repeating = true })

-- Scratchpad in "noalt" (SUPER+x,X)
hl.bind([=[SUPER + X]=], hl.dsp.workspace.toggle_special([=[magic]=]), {})
hl.bind([=[SUPER + SHIFT + X]=], hl.dsp.window.move({ workspace = [=[special:magic]=], follow = true }), {})

-- Misc in "noalt" (SUPER+F12)
hl.bind([=[SUPER + F12]=], hl.dsp.exec_cmd([=[sh -c 'ver=$(hyprctl version | awk "/^Hyprland /{print \$2; exit}"); [ -z \"$ver\" ] && ver=\"unknown\"; notify-send "Hyprland Version" "$ver"']=]), {})
hl.bind([=[SUPER + CTRL + F12]=], hl.dsp.exec_cmd([=[notify-send "Debug" "$(hyprctl activewindow -j | jq -r '.class, .title')"]=]), {})

-- Media & Brightness
hl.bind([=[XF86AudioRaiseVolume]=], hl.dsp.exec_cmd([=[wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioLowerVolume]=], hl.dsp.exec_cmd([=[wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioMute]=], hl.dsp.exec_cmd([=[wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioMicMute]=], hl.dsp.exec_cmd([=[wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle]=]), { repeating = true, locked = true })
hl.bind([=[XF86MonBrightnessUp]=], hl.dsp.exec_cmd([=[brightnessctl -e4 -n2 set 5%+]=]), { repeating = true, locked = true })
hl.bind([=[XF86MonBrightnessDown]=], hl.dsp.exec_cmd([=[brightnessctl -e4 -n2 set 5%-]=]), { repeating = true, locked = true })
hl.bind([=[XF86AudioPlay]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/play_pause.sh]=]), { locked = true })
hl.bind([=[XF86AudioNext]=], hl.dsp.exec_cmd([=[playerctl next]=]), { locked = true })
hl.bind([=[XF86AudioPrev]=], hl.dsp.exec_cmd([=[playerctl previous]=]), { locked = true })
hl.bind([=[SUPER + M]=], hl.dsp.exec_cmd([=[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle]=]), {})

-- Submap binds in "noalt"             (Toggle off/on)
hl.bind([=[SUPER + ALT + N]=], hl.dsp.exec_cmd([=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]), {})
hl.bind([=[SUPER + ALT + M]=], hl.dsp.exec_cmd([=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=]), {})
hl.bind([=[SUPER + ALT + V]=], hl.dsp.exec_cmd([=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=]), {})

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- MOUSE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("mouse", function()

-- Submap references in "mouse" (Toggle off)  [empty file on exit]
local mouse_off = [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]

-- Resize (MOUSE-left/right / hold)
hl.bind([=[h]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[j]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[k]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[l]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[left]=], hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind([=[down]=], hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
hl.bind([=[up]=], hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind([=[right]=], hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })
hl.bind([=[mouse:272]=], hl.dsp.window.drag(), { mouse = true })
hl.bind([=[mouse:273]=], hl.dsp.window.resize(), { mouse = true })
hl.bind([=[mouse:274]=], hl.dsp.window.float({ action = "toggle" }), {})
hl.bind([=[Escape]=], hl.dsp.exec_cmd([=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"' reset]=]), {})
hl.bind([=[Return]=], hl.dsp.exec_cmd([=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"' reset]=]), {})

-- Submap binds in "mouse"  (Toggle off/on)
hl.bind([=[SUPER + ALT + M]=], hl.dsp.exec_cmd([=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]), {})
hl.bind([=[SUPER + ALT + N]=], hl.dsp.exec_cmd([=[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']=]), {})
hl.bind([=[SUPER + ALT + V]=], hl.dsp.exec_cmd([=[sh -c 'echo vm > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: ON"; hyprctl dispatch "hl.dsp.submap(\"vm\")"']=]), {})

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- VIRTUAL MACHINE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("vm", function()

-- Submap references in "vm" (Toggle off)  [empty file on exit]
local vm_off = [=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]

-- Binds
hl.bind([=[SUPER + ALT + Q]=], hl.dsp.window.close(), {})
hl.bind([=[SUPER + ALT + F]=], hl.dsp.window.float({ action = "toggle" }), {})
hl.bind([=[SUPER + ALT + P]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/fuzzel_toggle.sh]=]), {})
hl.bind([=[SUPER + ALT + C]=], hl.dsp.exec_cmd([=[speedcrunch]=]), {})
hl.bind([=[SUPER + ALT + CTRL + V]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/launch_handler.sh wiremix "alacritty --class Wiremix -e wiremix"]=]), {})
hl.bind([=[SUPER + ALT + CTRL + S]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/qr_scan.sh]=]), {})
hl.bind([=[SUPER + ALT + S]=], hl.dsp.exec_cmd([=[env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN ~/.config/hypr/scripts/screenshot_area.sh]=]), {})
hl.bind([=[SUPER + ALT + D]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/screenshot_display.sh]=]), {})
hl.bind([=[SUPER + ALT + G]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/gif_capture.sh]=]), {})
hl.bind([=[SUPER + ALT + RETURN]=], hl.dsp.exec_cmd([=[alacritty]=]), {})
hl.bind([=[SUPER + ALT + SPACE]=], hl.dsp.exec_cmd([=[~/.config/hypr/scripts/mako_dismiss.sh]=]), { repeating = true })
hl.bind([=[SUPER + ALT + mouse:272]=], hl.dsp.window.drag(), { mouse = true })
hl.bind([=[SUPER + ALT + mouse:273]=], hl.dsp.window.resize(), { mouse = true })
hl.bind([=[SUPER + ALT + mouse:274]=], hl.dsp.window.float({ action = "toggle" }), {})

-- Workspaces (SUPER+ALT numbers)
hl.bind([=[SUPER + ALT + 1]=], hl.dsp.focus({ workspace = 1 }), {})
hl.bind([=[SUPER + ALT + 2]=], hl.dsp.focus({ workspace = 2 }), {})
hl.bind([=[SUPER + ALT + 3]=], hl.dsp.focus({ workspace = 3 }), {})
hl.bind([=[SUPER + ALT + 4]=], hl.dsp.focus({ workspace = 4 }), {})
hl.bind([=[SUPER + ALT + 5]=], hl.dsp.focus({ workspace = 5 }), {})
hl.bind([=[SUPER + ALT + 6]=], hl.dsp.focus({ workspace = 6 }), {})
hl.bind([=[SUPER + ALT + 7]=], hl.dsp.focus({ workspace = 7 }), {})
hl.bind([=[SUPER + ALT + 8]=], hl.dsp.focus({ workspace = 8 }), {})
hl.bind([=[SUPER + ALT + 9]=], hl.dsp.focus({ workspace = 9 }), {})
hl.bind([=[SUPER + ALT + 0]=], hl.dsp.focus({ workspace = 10 }), {})

-- Move window to workspace (SUPER+ALT+SHIFT numbers)
hl.bind([=[SUPER + ALT + SHIFT + 1]=], hl.dsp.window.move({ workspace = 1, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 2]=], hl.dsp.window.move({ workspace = 2, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 3]=], hl.dsp.window.move({ workspace = 3, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 4]=], hl.dsp.window.move({ workspace = 4, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 5]=], hl.dsp.window.move({ workspace = 5, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 6]=], hl.dsp.window.move({ workspace = 6, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 7]=], hl.dsp.window.move({ workspace = 7, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 8]=], hl.dsp.window.move({ workspace = 8, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 9]=], hl.dsp.window.move({ workspace = 9, follow = false }), {})
hl.bind([=[SUPER + ALT + SHIFT + 0]=], hl.dsp.window.move({ workspace = 10, follow = false }), {})

-- Submap binds in "vm"            (Toggle off/on)
hl.bind([=[SUPER + ALT + V]=], hl.dsp.exec_cmd([=[sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "vm mode: OFF"; hyprctl dispatch "hl.dsp.submap(\"reset\")"']=]), {})
hl.bind([=[SUPER + ALT + M]=], hl.dsp.exec_cmd([=[sh -c 'echo mouse > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "mouse mode: ON"; hyprctl dispatch "hl.dsp.submap(\"mouse\")"']=]), {})
hl.bind([=[SUPER + ALT + N]=], hl.dsp.exec_cmd([=[sh -c 'echo noalt > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 "noalt mode: ON"; hyprctl dispatch "hl.dsp.submap(\"noalt\")"']=]), {})

end)

-- ───────────────────────────────────────────────────────────────────────────────
-- RULES
-- ───────────────────────────────────────────────────────────────────────────────

-- Games: send to workspace 1, strip effects, fullscreen, allow tearing, keep awake
-- Note: Proton/Wine windows often have class like "game.exe" (not "Wine"), so we also match *.exe.
local games = [=[^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\.moonlight_stream\.Moonlight|.*\.exe)$]=]
-- Mark these windows as "game" content type so render:direct_scanout=2 can auto-engage
hl.window_rule({ match = { class = games }, content = [=[game]=] })
-- other $games window rules
hl.window_rule({ match = { class = games }, workspace = [=[1 silent]=] })
hl.window_rule({ match = { class = games }, no_anim = true })
hl.window_rule({ match = { class = games }, no_blur = true })
hl.window_rule({ match = { class = games }, no_shadow = true })
hl.window_rule({ match = { class = games }, decorate = false })
hl.window_rule({ match = { class = games }, border_size = 0 })
hl.window_rule({ match = { class = games }, rounding = 0 })
hl.window_rule({ match = { class = games }, fullscreen = true })
hl.window_rule({ match = { class = games }, immediate = true })
hl.window_rule({ match = { class = games }, idle_inhibit = [=[always]=] })

-- Workspace auto-assignments
hl.window_rule({ match = { class = [=[^(firefox|librewolf|Mullvad Browser|Cromite|brave-browser|io\.github\.ungoogled_software\.ungoogled_chromium)$]=] }, workspace = [=[2 silent]=] })
hl.window_rule({ match = { class = [=[^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|brave-app\.revolt\.chat__-.*|chat\.revolt\.RevoltDesktop|info\.mumble\.Mumble|fluxer|Fluxer)$]=] }, workspace = [=[3 silent]=] })
hl.window_rule({ match = { class = [=[^(steam|com\.valvesoftware\.Steam|SteamChat|net\.lutris\.Lutris|itch|io\.itch\.itch|heroic|com\.heroicgameslauncher\.hgl|r2modman)$]=] }, workspace = [=[4 silent]=] })
hl.window_rule({ match = { class = [=[^(Spotify|com\.spotify\.Client|brave-music\.youtube\.com__-.*)$]=] }, workspace = [=[5 silent]=] })
hl.window_rule({ match = { title = [=[^(.*YouTube Music.*)$]=] }, workspace = [=[5 silent]=] })
hl.window_rule({ match = { class = [=[^(org\.telegram\.desktop|brave-web\.telegram\.org__a_-.*|brave-messages\.google\.com__-.*)$]=] }, workspace = [=[6 silent]=] })
hl.window_rule({ match = { title = [=[^(Telegram Web)$]=] }, workspace = [=[6 silent]=] })
hl.window_rule({ match = { class = [=[^(Messages)$]=] }, workspace = [=[6 silent]=] })
hl.window_rule({ match = { class = [=[^(Telegram)$]=] }, workspace = [=[6 silent]=] })
hl.window_rule({ match = { class = [=[^(Vncviewer|rustdesk)$]=] }, workspace = [=[7 silent]=] })
hl.window_rule({ match = { class = [=[^(com\.github\.IsmaelMartinez\.teams_for_linux)$]=] }, workspace = [=[8 silent]=] })
hl.window_rule({ match = { class = [=[^(kdenlive|org\.kde\.kdenlive|org\.shotcut\.Shotcut|krita|org\.kde\.krita)$]=] }, workspace = [=[9 silent]=] })
hl.window_rule({ match = { class = [=[^(obs|com\.obsproject\.Studio|gpu-screen-recorder|gpu-screen-recorder-gtk|gpu-screen-recorder-ui|gsr-ui|com\.dec05eba\.gpu_screen_recorder)$]=] }, workspace = [=[10 silent]=] })

-- Global behavior / XWayland quirks
hl.window_rule({ match = { class = [=[.*]=] }, suppress_event = [=[maximize]=] })
hl.window_rule({ match = { class = [=[^$]=], title = [=[^$]=], xwayland = true, float = true, fullscreen = false, pin = false }, no_focus = true })
hl.window_rule({ match = { xwayland = true }, no_blur = true })
hl.window_rule({ match = { class = [=[^(steam)$]=], title = [=[^$]=] }, stay_focused = true })
hl.window_rule({ match = { class = [=[^(steam)$]=], title = [=[^$]=] }, min_size = { 1, 1 } })

-- Picture-in-Picture
local pip = [=[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]=]
hl.window_rule({ match = { title = pip }, float = true })
hl.window_rule({ match = { title = pip }, keep_aspect_ratio = true })
hl.window_rule({ match = { title = pip }, move = { [=[(monitor_w*0.73)]=], [=[(monitor_h*0.70)]=] } })
hl.window_rule({ match = { title = pip }, size = { [=[(monitor_w*0.25)]=], [=[(monitor_h*0.25)]=] } })
hl.window_rule({ match = { title = pip }, pin = true })

-- Dialogs float+center
local dialogs = [=[^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload)(.*)$]=]
hl.window_rule({ match = { title = dialogs }, float = true })
hl.window_rule({ match = { title = dialogs }, center = true })

-- Transparency
hl.window_rule({ match = { class = [=[^(wofi)$]=] }, opacity = [=[0.85 0.85]=] })
hl.window_rule({ match = { class = [=[^(Spotify)$]=] }, opacity = [=[0.85 0.85]=] })
hl.window_rule({ match = { title = [=[^(YouTube Music|YouTube Music - .+ - YouTube Music|YouTube Music - 1\. YouTube Music)$]=] }, opacity = [=[0.85 0.85]=] })
hl.window_rule({ match = { class = [=[^(com\.github\.th_ch\.youtube_music|brave-music\.youtube\.com__-.*)$]=] }, opacity = [=[0.85 0.85]=] })
hl.window_rule({ match = { class = [=[^(pcmanfm-qt|localsend|org\.pulseaudio\.pavucontrol|org\.speedcrunch\.speedcrunch|net\.davidotek\.pupgui2|wallpicker)$]=] }, opacity = [=[0.95 0.95]=] })

-- Float + size + center
hl.window_rule({ match = { class = [=[^org\.speedcrunch\.speedcrunch$]=] }, float = true })
hl.window_rule({ match = { class = [=[^org\.speedcrunch\.speedcrunch$]=] }, size = { [=[(monitor_w*0.15)]=], [=[(monitor_h*0.55)]=] } })
hl.window_rule({ match = { class = [=[^org\.speedcrunch\.speedcrunch$]=] }, center = true })

hl.window_rule({ match = { class = [=[^org\.pulseaudio\.pavucontrol$]=] }, float = true })
hl.window_rule({ match = { class = [=[^org\.pulseaudio\.pavucontrol$]=] }, size = { [=[(monitor_w*0.55)]=], [=[(monitor_h*0.70)]=] } })
hl.window_rule({ match = { class = [=[^org\.pulseaudio\.pavucontrol$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(Pulsemixer)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(Pulsemixer)$]=] }, size = { [=[(monitor_w*0.55)]=], [=[(monitor_h*0.70)]=] } })
hl.window_rule({ match = { class = [=[^(Pulsemixer)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(Wiremix)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(Wiremix)$]=] }, size = { [=[(monitor_w*0.65)]=], [=[(monitor_h*0.70)]=] } })
hl.window_rule({ match = { class = [=[^(Wiremix)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(hypr_quicksettings)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(hypr_quicksettings)$]=] }, size = { [=[(monitor_w*0.70)]=], [=[(monitor_h*0.40)]=] } })
hl.window_rule({ match = { class = [=[^(hypr_quicksettings)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(awtarchy-tips-tui)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(awtarchy-tips-tui)$]=] }, size = { [=[(monitor_w*0.50)]=], [=[(monitor_h*0.50)]=] } })
hl.window_rule({ match = { class = [=[^(awtarchy-tips-tui)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(maccel)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(maccel)$]=] }, size = { [=[(monitor_w*0.90)]=], [=[(monitor_h*0.96)]=] } })
hl.window_rule({ match = { class = [=[^(maccel)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(hyprbars)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(hyprbars)$]=] }, size = { [=[(monitor_w*0.30)]=], [=[(monitor_h*0.10)]=] } })
hl.window_rule({ match = { class = [=[^(hyprbars)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(smtty)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(smtty)$]=] }, size = { [=[(monitor_w*0.80)]=], [=[(monitor_h*0.88)]=] } })
hl.window_rule({ match = { class = [=[^(smtty)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(smtty-O)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(smtty-O)$]=] }, size = { [=[(monitor_w*0.50)]=], [=[(monitor_h*0.50)]=] } })
hl.window_rule({ match = { class = [=[^(smtty-O)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(wallpicker)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(wallpicker)$]=] }, size = { [=[(monitor_w*0.85)]=], [=[(monitor_h*0.90)]=] } })
hl.window_rule({ match = { class = [=[^(wallpicker)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(nm-connection-editor)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(nm-connection-editor)$]=] }, size = { [=[(monitor_w*0.45)]=], [=[(monitor_h*0.45)]=] } })
hl.window_rule({ match = { class = [=[^(nm-connection-editor)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(blueman-manager)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(blueman-manager)$]=] }, size = { [=[(monitor_w*0.45)]=], [=[(monitor_h*0.45)]=] } })
hl.window_rule({ match = { class = [=[^(blueman-manager)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(net\.davidotek\.pupgui2)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(net\.davidotek\.pupgui2)$]=] }, size = { [=[(monitor_w*0.45)]=], [=[(monitor_h*0.45)]=] } })
hl.window_rule({ match = { class = [=[^(net\.davidotek\.pupgui2)$]=] }, center = true })

hl.window_rule({ match = { class = [=[^(btop)$]=] }, float = true })
hl.window_rule({ match = { class = [=[^(btop)$]=] }, size = { [=[(monitor_w*0.80)]=], [=[(monitor_h*0.85)]=] } })
hl.window_rule({ match = { class = [=[^(btop)$]=] }, center = true })

-- Force Tile
hl.window_rule({ match = { class = [=[^(steam|com\.valvesoftware\.Steam)$]=], title = [=[^(Steam)$]=] }, tile = true })
hl.window_rule({ match = { class = [=[^(steam|com\.valvesoftware\.Steam)$]=], title = [=[^(Friends List)$]=] }, tile = true })

-- ───────────────────────────────────────────────────────────────────────────────
-- SCREENSHARE GUARD
-- ───────────────────────────────────────────────────────────────────────────────

hl.window_rule({ match = { class = [=[^(Bitwarden|com\.bitwarden\.desktop|KeePassXC|org\.keepassxc\.KeePassXC|1Password|com\.1password\.1password|Enpass|org\.gnome\.Secrets|org\.gnome\.seahorse\.Application|OTPClient|otpclient|org\.rasalminen\.OTPClient|Mullvad Browser|mullvad-browser|com\.mullvad\.Browser|localsend|LocalSend|org\.localsend\.localsend|io\.github\.localsend\.localsend)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(firefox)$]=], title = [=[^(Extension: \(Bitwarden Password Manager\).*)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$]=], title = [=[^(Bitwarden Password Manager.*)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(org\.telegram\.desktop|TelegramDesktop|telegram-desktop|Telegram)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$]=], title = [=[^.*Telegram.*$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(Element|io\.element\.Element|im\.riot\.Riot|chat\.element\.desktop|SchildiChat|im\.fluffychat\.Fluffychat|Fractal|org\.gnome\.Fractal|nheko)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(discord|com\.discordapp\.Discord|vesktop|dev\.vencord\.Vesktop|Fluxer|fluxer)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(com\.github\.IsmaelMartinez\.teams_for_linux)$]=] }, no_screen_share = true })
hl.window_rule({ match = { class = [=[^(Messages)$]=] }, no_screen_share = true })

-- Layers (notifications/swaync are layer surfaces, not windows)
hl.layer_rule({ match = { namespace = [=[^(notifications|swaync.*)$]=] }, no_screen_share = true })

-- optional
-- hl.window_rule({ match = { class = [=[^(obs|com\.obsproject\.Studio|obs-studio|com\.obsproject\.Studio\.obs)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(steam|com\.valvesoftware\.Steam)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(rustdesk|com\.rustdesk\.RustDesk)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(wallpicker)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(virt-manager)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(Alacritty)$]=] }, no_screen_share = true })
-- hl.window_rule({ match = { class = [=[^(mpv)$]=] }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = [=[^(ags)$]=] }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = [=[^(logout_dialog)$]=] }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = [=[^(waybar)$]=] }, no_screen_share = true })

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
