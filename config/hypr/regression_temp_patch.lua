-- Temporary workaround for Hyprland 0.55.x mouse/submap regression.
--
-- Remove this file when upstream mouse/submap handling is fixed.
-- hyprland.lua is written so missing this file restores normal intended behavior.

local M = {}

local function shell_quote_single(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function lua_eval(code)
    return "hyprctl eval " .. shell_quote_single(code)
end

local disable_alt_mouse = table.concat({
    'hl.unbind("ALT + mouse:272")',
    'hl.unbind("ALT + mouse:273")',
}, "; ")

local enable_alt_mouse = table.concat({
    'hl.unbind("ALT + mouse:272")',
    'hl.unbind("ALT + mouse:273")',
    'hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })',
    'hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })',
}, "; ")

local disable_mouse_mode = table.concat({
    'hl.unbind("mouse:272")',
    'hl.unbind("mouse:273")',
    'hl.unbind("mouse:274")',
}, "; ")

local enable_mouse_mode = table.concat({
    disable_mouse_mode,
    'hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })',
    'hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true })',
    'hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})',
}, "; ")

function M.on(name, cmd)
    if name == "mouse" then
        return lua_eval(disable_alt_mouse .. "; " .. enable_mouse_mode) .. "; " .. cmd
    end

    return lua_eval(disable_mouse_mode .. "; " .. disable_alt_mouse) .. "; " .. cmd
end

function M.off(name, cmd)
    return cmd .. "; " .. lua_eval(disable_mouse_mode .. "; " .. enable_alt_mouse)
end

return M
