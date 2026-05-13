-- ~/.config/hypr/lua.lua
-- Hidden compatibility helpers for the converted Hyprland Lua config.
-- Edit ~/.config/hypr/hyprland.lua for your actual config.

vars = vars or {}

function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function split_commas(s, maxsplit)
    local ret, cur, splits = {}, {}, 0
    local single, double, esc = false, false, false
    s = tostring(s or "")

    for i = 1, #s do
        local ch = s:sub(i, i)

        if esc then
            table.insert(cur, ch)
            esc = false
        elseif ch == "\\" and double then
            table.insert(cur, ch)
            esc = true
        elseif ch == "'" and not double then
            single = not single
            table.insert(cur, ch)
        elseif ch == '"' and not single then
            double = not double
            table.insert(cur, ch)
        elseif ch == "," and not single and not double and (not maxsplit or splits < maxsplit) then
            table.insert(ret, trim(table.concat(cur)))
            cur = {}
            splits = splits + 1
        else
            table.insert(cur, ch)
        end
    end

    table.insert(ret, trim(table.concat(cur)))
    return ret
end

function expand(value)
    local s = tostring(value or "")

    for _ = 1, 30 do
        local changed = false
        s = s:gsub("%$([%w_-]+)", function(name)
            local replacement = vars[name]
            if replacement == nil then
                return "$" .. name
            end
            changed = true
            return replacement
        end)
        if not changed then
            break
        end
    end

    return s
end

function set_var(name, value)
    vars[name] = value
end

function parse_scalar(value)
    local s = trim(expand(value))

    if s == "true" or s == "yes" or s == "on" then return true end
    if s == "false" or s == "no" or s == "off" then return false end

    local n = tonumber(s)
    if n ~= nil then return n end

    return s
end

function normalize_hyprbars_action(action)
    local s = trim(expand(action or ""))

    if s == "hyprctl dispatch killactive" then
        return [[hyprctl dispatch 'hl.dsp.window.close()']]
    end

    if s == "hyprctl dispatch fullscreen 1" then
        return [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']]
    end

    if s == "hyprctl dispatch togglefloating" then
        return [[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']]
    end

    return s
end

function parse_config_value(key, value)
    local s = trim(expand(value))

    if key == "on_double_click" then
        return normalize_hyprbars_action(s)
    end

    if key == "active_border"
        or key == "inactive_border"
        or key == "color"
        or key == "text"
        or key == "col.text"
        or key == "bar_color"
    then
        return s
    end

    return parse_scalar(s)
end

function set_nested(root, path, key, value)
    local node = root

    for _, part in ipairs(path or {}) do
        node[part] = node[part] or {}
        node = node[part]
    end

    local parts = {}
    for part in tostring(key):gmatch("[^%.]+") do
        table.insert(parts, part)
    end

    for i = 1, #parts - 1 do
        node[parts[i]] = node[parts[i]] or {}
        node = node[parts[i]]
    end

    node[parts[#parts]] = value
end

function hyprbars_loaded()
    return hl and hl.plugin and hl.plugin.hyprbars ~= nil
end

function config_set(path, key, raw_value)
    -- hyprbars can be toggled off with hyprpm.
    -- When disabled, Hyprland does not know plugin.hyprbars.* config keys.
    if path and path[1] == "plugin" and path[2] == "hyprbars" then
        if not hyprbars_loaded() then
            return
        end
    end

    local t = {}
    set_nested(t, path, key, parse_config_value(key, raw_value))
    hl.config(t)
end

function monitor_old(raw)
    local p = split_commas(raw)
    local output = p[1] or ""
    local mode = p[2] or "preferred"
    local position = p[3] or "auto"
    local scale = parse_scalar(p[4] or "auto")
    local m = { output = output, mode = mode, position = position, scale = scale }

    local i = 5
    while i <= #p do
        local k = trim(p[i] or "")
        local v = trim(p[i + 1] or "")
        if k ~= "" then
            m[k] = parse_scalar(v)
        end
        i = i + 2
    end

    hl.monitor(m)
end

function env_old(raw)
    local p = split_commas(raw, 1)
    hl.env(trim(p[1] or ""), trim(p[2] or ""))
end

function exec_once_old(cmd)
    local expanded = expand(cmd)
    hl.on("hyprland.start", function()
        hl.exec_cmd(expanded)
    end)
end

function permission_old(raw)
    local p = split_commas(raw, 2)
    hl.permission(trim(p[1] or ""), trim(p[2] or ""), trim(p[3] or ""))
end

function curve_old(raw)
    local p = split_commas(raw)
    local name = trim(p[1] or "")
    local x1 = tonumber(trim(p[2] or "")) or 0
    local y1 = tonumber(trim(p[3] or "")) or 0
    local x2 = tonumber(trim(p[4] or "")) or 1
    local y2 = tonumber(trim(p[5] or "")) or 1

    hl.curve(name, { type = "bezier", points = { { x1, y1 }, { x2, y2 } } })
end

function animation_old(raw)
    local p = split_commas(raw)
    local leaf = trim(p[1] or "")
    local enabled = parse_scalar(p[2] or "true")
    local speed = tonumber(trim(p[3] or "")) or 1
    local curve = trim(p[4] or "")
    local style = trim(p[5] or "")
    local t = { leaf = leaf, enabled = enabled, speed = speed }

    if curve ~= "" then t.bezier = curve end
    if style ~= "" then t.style = style end

    hl.animation(t)
end

function gesture_old(raw)
    local p = split_commas(raw)
    hl.gesture({
        fingers = tonumber(trim(p[1] or "")) or 3,
        direction = trim(p[2] or ""),
        action = trim(p[3] or ""),
    })
end

function keycombo(mods, key)
    local m = trim(expand(mods or ""))
    local k = trim(expand(key or ""))
    local parts = {}

    for token in m:gmatch("%S+") do
        table.insert(parts, token)
    end

    if k ~= "" then
        table.insert(parts, k)
    end

    return table.concat(parts, " + ")
end

function parse_workspace(value)
    local s = trim(expand(value or ""))
    if s:match("^%d+$") then return tonumber(s) end
    return s
end

function parse_resize_xy(args)
    local s = trim(expand(args or ""))
    local x, y = s:match("^([^%s]+)%s+([^%s]+)")
    return tonumber(x) or 0, tonumber(y) or 0
end

function dispatch_old(dispatcher, args)
    local d = trim(dispatcher)
    local a = trim(args or "")

    if d == "exec" then return hl.dsp.exec_cmd(expand(a)) end
    if d == "killactive" then return hl.dsp.window.close() end
    if d == "pin" then return hl.dsp.window.pin() end
    if d == "layoutmsg" then return hl.dsp.layout(expand(a)) end
    if d == "togglefloating" then return hl.dsp.window.float({ action = "toggle" }) end

    if d == "fullscreen" then
        if a == "1" then
            return hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
        end
        return hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })
    end

    if d == "cyclenext" then
        return hl.dsp.window.cycle_next({ next = (trim(a) ~= "prev") })
    end

    if d == "bringactivetotop" then
        if hl.dsp.window.bring_to_top then
            return hl.dsp.window.bring_to_top()
        end
        return hl.dsp.window.alter_zorder({ mode = "top" })
    end

    if d == "movefocus" then
        return hl.dsp.focus({ direction = expand(a) })
    end

    if d == "movewindow" then
        -- bindm mouse drag uses empty args.
        if a == "" then
            return hl.dsp.window.drag()
        end

        -- Keyboard window movement uses l/r/u/d.
        return hl.dsp.window.move({ direction = expand(a) })
    end

    if d == "movecurrentworkspacetomonitor" then
        return hl.dsp.workspace.move({ monitor = expand(a) })
    end

    if d == "workspace" then
        return hl.dsp.focus({ workspace = parse_workspace(a) })
    end

    if d == "movetoworkspacesilent" then
        return hl.dsp.window.move({ workspace = parse_workspace(a), follow = false })
    end

    if d == "movetoworkspace" then
        return hl.dsp.window.move({ workspace = parse_workspace(a), follow = true })
    end

    if d == "resizeactive" then
        local x, y = parse_resize_xy(a)
        return hl.dsp.window.resize({ x = x, y = y, relative = true })
    end

    if d == "resizewindow" then
        -- bindm mouse resize uses empty args.
        return hl.dsp.window.resize()
    end

    if d == "togglespecialworkspace" then
        return hl.dsp.workspace.toggle_special(expand(a))
    end

    if d == "submap" then
        return hl.dsp.submap(expand(a))
    end

    error("Unsupported converted dispatcher: " .. d .. " " .. a)
end

function bind_old(kind, mods, key, dispatcher, args)
    local opts = {}

    if kind:find("e", 1, true) then opts.repeating = true end
    if kind:find("l", 1, true) then opts.locked = true end
    if kind:find("m", 1, true) then opts.mouse = true end

    hl.bind(keycombo(mods, key), dispatch_old(dispatcher, args), opts)
end

function parse_boolish(s)
    s = trim(expand(s or ""))

    if s == "on" or s == "yes" or s == "true" or s == "1" then return true end
    if s == "off" or s == "no" or s == "false" or s == "0" then return false end

    return s
end

function parse_rule_value(effect, value)
    value = trim(expand(value or ""))

    if value == "" then return true end

    if effect == "float"
        or effect == "tile"
        or effect == "fullscreen"
        or effect == "maximize"
        or effect == "center"
        or effect == "pseudo"
        or effect == "pin"
        or effect == "no_initial_focus"
        or effect == "persistent_size"
        or effect == "no_max_size"
        or effect == "stay_focused"
        or effect == "keep_aspect_ratio"
        or effect == "no_anim"
        or effect == "no_blur"
        or effect == "no_dim"
        or effect == "no_focus"
        or effect == "no_follow_mouse"
        or effect == "no_shadow"
        or effect == "no_shortcuts_inhibit"
        or effect == "no_screen_share"
        or effect == "no_vrr"
        or effect == "opaque"
        or effect == "force_rgbx"
        or effect == "sync_fullscreen"
        or effect == "immediate"
        or effect == "xray"
        or effect == "render_unfocused"
        or effect == "decorate"
        or effect == "allows_input"
        or effect == "dim_around"
        or effect == "confine_pointer"
    then
        return parse_boolish(value)
    end

    if effect == "border_size"
        or effect == "rounding"
        or effect == "no_close_for"
        or effect == "scrolling_width"
        or effect == "scroll_mouse"
        or effect == "scroll_touchpad"
    then
        return tonumber(value) or value
    end

    if effect == "move" or effect == "size" or effect == "min_size" or effect == "max_size" then
        local a, b = value:match("^([^%s]+)%s+([^%s]+)$")
        if a and b then
            local na, nb = tonumber(a), tonumber(b)
            if na and nb then return { na, nb } end
            return { a, b }
        end
    end

    return value
end

function add_match(rule, key, value)
    key = trim(key)
    value = trim(expand(value or ""))

    if key == "xwayland"
        or key == "float"
        or key == "fullscreen"
        or key == "pin"
        or key == "focus"
        or key == "group"
        or key == "modal"
    then
        rule.match[key] = parse_boolish(value)
    elseif key == "fullscreen_state_client" or key == "fullscreen_state_internal" then
        rule.match[key] = tonumber(value) or value
    else
        rule.match[key] = value
    end
end

function rule_old(raw, is_layer)
    local rule = { match = {} }
    local p = split_commas(raw)

    for _, item in ipairs(p) do
        local s = trim(item)
        local mkey, mval = s:match("^match:([%w_]+)%s+(.+)$")

        if mkey then
            add_match(rule, mkey, mval)
        else
            local key, val = s:match("^([^%s]+)%s*(.*)$")
            if key and key ~= "" then
                rule[key] = parse_rule_value(key, val)
            end
        end
    end

    if is_layer then
        hl.layer_rule(rule)
    else
        hl.window_rule(rule)
    end
end

function hyprbars_button_old(raw)
    -- hyprbars can be toggled off with hyprpm.
    if not (hl and hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button) then
        return
    end

    local p = split_commas(raw, 4)
    local action = normalize_hyprbars_action(p[4] or "")

    local t = {
        bg_color = trim(expand(p[1] or "rgb(1e1e1e)")),
        fg_color = trim(expand(p[5] or "rgb(d0d0d0)")),
        size = tonumber(trim(p[2] or "")) or 20,
        icon = trim(p[3] or ""),
        action = action,
    }

    if t.bg_color == "" then t.bg_color = "rgb(1e1e1e)" end
    if t.fg_color == "" then t.fg_color = "rgb(d0d0d0)" end

    hl.plugin.hyprbars.add_button(t)
end
-- Clean helper aliases. The *_old names remain for backward compatibility.
monitor = monitor_old
env = env_old
exec_once = exec_once_old
permission = permission_old
curve = curve_old
animation = animation_old
gesture = gesture_old
bind = bind_old
rule = rule_old
hyprbars_button = hyprbars_button_old

-- Clean helper aliases.
-- These let hyprland.lua use monitor(), bind(), env(), etc.
-- The *_old functions remain the real compatibility parser layer.
monitor = monitor or monitor_old
env = env or env_old
exec_once = exec_once or exec_once_old
permission = permission or permission_old
curve = curve or curve_old
animation = animation or animation_old
gesture = gesture or gesture_old
bind = bind or bind_old
rule = rule or rule_old
hyprbars_button = hyprbars_button or hyprbars_button_old

