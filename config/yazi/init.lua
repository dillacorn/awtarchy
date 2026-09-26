-- github.com/dillacorn/awtarchy/tree/main/config/yazi
-- ~/.config/yazi/init.lua

require("recent-files"):setup()
require("bookmarks"):setup()
require("git"):setup { order = 1500 }

local function AwtarchyYaziNormalizeFsPath(value)
    return tostring(value or ""):gsub("\\", "/"):gsub("/+$", "")
end

local function AwtarchyYaziStateDir()
    local root = os.getenv("XDG_STATE_HOME")
    if not root or root == "" then
        local home = os.getenv("HOME") or "."
        root = home .. "/.local/state"
    end
    return root .. "/yazi"
end

local AwtarchyYaziCollectionRoots = {
    bookmarks = AwtarchyYaziNormalizeFsPath(AwtarchyYaziStateDir() .. "/collections/Bookmarks"),
    recents = AwtarchyYaziNormalizeFsPath(AwtarchyYaziStateDir() .. "/collections/Recently Opened"),
}

local function AwtarchyYaziCollectionKind(value)
    local path = AwtarchyYaziNormalizeFsPath(value)
    if path == AwtarchyYaziCollectionRoots.bookmarks then return "bookmarks" end
    if path == AwtarchyYaziCollectionRoots.recents then return "recents" end
    return nil
end

local function AwtarchyYaziIsCollectionItemUrl(value)
    local path = AwtarchyYaziNormalizeFsPath(value)
    for _, root in pairs(AwtarchyYaziCollectionRoots) do
        local prefix = root .. "/"
        if path:sub(1, #prefix) == prefix then
            local rest = path:sub(#prefix + 1)
            return rest ~= "" and rest:find("/", 1, true) == nil
        end
    end
    return false
end

local function AwtarchyYaziCollectionCwd()
    return AwtarchyYaziCollectionKind(cx.active.current.cwd)
end

local AwtarchyYaziCollectionReturns = {}

local function AwtarchyYaziCollectionReturnState()
    local tab_key = tostring(cx.active.id)
    local state = AwtarchyYaziCollectionReturns[tab_key]
    if not state then
        state = {}
        AwtarchyYaziCollectionReturns[tab_key] = state
    end
    return state
end

local function AwtarchyYaziOpenCollection(kind)
    local plugin = kind == "bookmarks" and "bookmarks" or "recent-files"
    local state = AwtarchyYaziCollectionReturnState()

    if AwtarchyYaziCollectionCwd() ~= kind then
        state[kind] = tostring(cx.active.current.cwd)
    end

    ya.emit("plugin", { plugin })
end

local function AwtarchyYaziToggleCollection(kind)
    local state = AwtarchyYaziCollectionReturnState()

    if AwtarchyYaziCollectionCwd() == kind then
        local target = state[kind]
        state[kind] = nil
        if target and target ~= "" then
            ya.emit("cd", { Url(target), raw = true })
        else
            ya.emit("back", {})
        end
        return
    end

    AwtarchyYaziOpenCollection(kind)
end

function AwtarchyYaziGoBookmarks()
    AwtarchyYaziOpenCollection("bookmarks")
end

function AwtarchyYaziToggleBookmarks()
    AwtarchyYaziToggleCollection("bookmarks")
end

function AwtarchyYaziGoRecents()
    AwtarchyYaziOpenCollection("recents")
end

function AwtarchyYaziToggleRecents()
    AwtarchyYaziToggleCollection("recents")
end

local AwtarchyYaziDefaultEntityHighlights = Entity.highlights
local AwtarchyYaziDefaultEntitySymlink = Entity.symlink

function Entity:highlights()
    if AwtarchyYaziIsCollectionItemUrl(self._file.url) then
        return ui.printable(tostring(self._file.url.name or ""):gsub("^%d+%-%-", ""))
    end
    return AwtarchyYaziDefaultEntityHighlights(self)
end

function Entity:symlink()
    if AwtarchyYaziIsCollectionItemUrl(self._file.url) then return "" end
    return AwtarchyYaziDefaultEntitySymlink(self)
end

function Linemode:size_and_mtime()
    if AwtarchyYaziIsCollectionItemUrl(self._file.url) then return "" end
    local size = self._file:size()
    local size_text

    if size then
        size_text = ya.readable_size(size)
    else
        local folder = cx.active:history(self._file.url)
        size_text = folder and tostring(#folder.files) or "-"
    end

    local time = math.floor(self._file.cha.mtime or 0)
    local date_text = "-"

    if time > 0 then
        local parts = os.date("*t", time)
        date_text = string.format(
            "%d/%d/%02d",
            parts.month,
            parts.day,
            parts.year % 100
        )
    end

    return string.format("%9s  %8s", size_text, date_text)
end


local function AwtarchyYaziPluginHex(value)
    return (value:gsub(".", function(char)
        return string.format("%02x", string.byte(char))
    end))
end

local function AwtarchyYaziPluginArgs(command, values)
    local args = { command }
    for _, value in ipairs(values) do
        args[#args + 1] = "hex:" .. AwtarchyYaziPluginHex(value)
    end
    return table.concat(args, " ")
end

local function AwtarchyYaziBookmarkTarget(target, is_dir)
    ya.emit("plugin", {
        "bookmarks",
        AwtarchyYaziPluginArgs("toggle", { is_dir and "D" or "F", target }),
    })
end

local function AwtarchyYaziNavigateCollection(file, new_tab)
    local kind = AwtarchyYaziCollectionCwd()
    if not kind or not file or not AwtarchyYaziIsCollectionItemUrl(file.url) then return false end

    local plugin = kind == "bookmarks" and "bookmarks" or "recent-files"
    ya.emit("plugin", {
        plugin,
        AwtarchyYaziPluginArgs("activate", { tostring(file.url), new_tab and "1" or "0" }),
    })
    return true
end

local function AwtarchyYaziCollectionSelection()
    local kind = AwtarchyYaziCollectionCwd()
    if not kind then return nil, {} end

    local tab = cx.active
    local markers = {}
    if #tab.selected > 0 then
        for _, file in pairs(tab.selected) do
            if AwtarchyYaziIsCollectionItemUrl(file.url) then
                markers[#markers + 1] = tostring(file.url)
            end
        end
    elseif tab.current.hovered and AwtarchyYaziIsCollectionItemUrl(tab.current.hovered.url) then
        markers[1] = tostring(tab.current.hovered.url)
    end
    return kind, markers
end

local function AwtarchyYaziDeleteCollectionSelection()
    local kind, markers = AwtarchyYaziCollectionSelection()
    if not kind or #markers == 0 then return false end

    local plugin = kind == "bookmarks" and "bookmarks" or "recent-files"
    ya.emit("plugin", {
        plugin,
        AwtarchyYaziPluginArgs("delete", markers),
    })
    return true
end

local function AwtarchyYaziOpenFiles(interactive, hovered_only)
    local tab = cx.active
    local recent = {}

    if hovered_only then
        local file = tab.current.hovered
        if file and not file.cha.is_dir then
            recent[1] = tostring(file.url)
        end
    elseif #tab.selected > 0 then
        for _, file in pairs(tab.selected) do
            if not file.cha.is_dir then
                recent[#recent + 1] = tostring(file.url)
            end
        end
    elseif tab.current.hovered and not tab.current.hovered.cha.is_dir then
        recent[1] = tostring(tab.current.hovered.url)
    end

    if #recent > 0 then
        ya.emit("plugin", {
            "recent-files",
            AwtarchyYaziPluginArgs("record", recent),
        })
    end

    local args = {}
    if interactive then
        args.interactive = true
    end
    if hovered_only then
        args.hovered = true
    end
    ya.emit("open", args)
end

function AwtarchyYaziOpen(interactive)
    AwtarchyYaziOpenFiles(interactive == true, false)
end

function AwtarchyYaziSmartEnter()
    if AwtarchyYaziDeleteMenu and AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:submit()
        return
    end

    local hovered = cx.active.current.hovered
    if AwtarchyYaziNavigateCollection(hovered, false) then
        return
    elseif hovered and hovered.cha.is_dir then
        ya.emit("enter", {})
    else
        AwtarchyYaziOpenFiles(false, false)
    end
end

function AwtarchyYaziRight()
    local hovered = cx.active.current.hovered
    if not hovered then
        return
    elseif AwtarchyYaziNavigateCollection(hovered, false) then
        return
    elseif hovered.cha.is_dir then
        ya.emit("enter", {})
    elseif not AwtarchyYaziPreviewMaximized and rt.mgr.ratio[3] > 0 then
        AwtarchyYaziTogglePreviewMax()
    end
end

function AwtarchyYaziLeft()
    if AwtarchyYaziPreviewMaximized then
        AwtarchyYaziTogglePreviewMax()
    elseif AwtarchyYaziCollectionCwd() then
        ya.emit("back", {})
    else
        ya.emit("leave", {})
    end
end

AwtarchyYaziShiftRangeActive = false

function AwtarchyYaziShiftArrow(step)
    if cx.active.mode.is_normal then
        ya.emit("visual_mode", {})
    end
    AwtarchyYaziShiftRangeActive = true
    ya.emit("arrow", { step })
end

function AwtarchyYaziArrow(step)
    if AwtarchyYaziDeleteMenu and AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:move(step)
        return
    end

    if AwtarchyYaziShiftRangeActive and not cx.active.mode.is_normal then
        ya.emit("escape", { visual = true })
    end
    AwtarchyYaziShiftRangeActive = false
    local direction = step < 0 and "prev" or "next"
    ya.emit("arrow", { direction })
end

function AwtarchyYaziConfirmQuit(no_cwd_file)
    ya.async(function()
        local confirmed = ya.confirm {
            pos = { "center", w = 48, h = 8 },
            title = "Quit Yazi?",
            body = ui.Text {
                ui.Line("Quit this Yazi session?"):align(ui.Align.CENTER),
                ui.Line(""),
                ui.Line("Yes: Y / Enter / Space"):align(ui.Align.CENTER),
                ui.Line("No:  N / Esc"):align(ui.Align.CENTER),
            },
        }

        if confirmed then
            ya.emit("quit", { no_cwd_file = no_cwd_file == true })
        end
    end)
end

function AwtarchyYaziCloseTab()
    if #cx.tabs > 1 then
        ya.emit("close", {})
    else
        AwtarchyYaziConfirmQuit(false)
    end
end

AwtarchyYaziDeleteMenu = {
    _id = "awtarchy-yazi-delete-menu",
    _visible = false,
    _selected = 1,
    _area = ui.Rect {},
    _list_area = ui.Rect {},
}

function AwtarchyYaziDeleteMenu:show()
    self._selected = 1
    self._visible = true
    ui.render()
end

function AwtarchyYaziDeleteMenu:hide()
    if not self._visible then
        return
    end
    self._visible = false
    ui.render()
end

function AwtarchyYaziDeleteMenu:move(step)
    self._selected = ((self._selected - 1 + step) % 2) + 1
    ui.render()
end

function AwtarchyYaziDeleteMenu:submit(choice)
    local selected = choice or self._selected
    self._visible = false
    ui.render()

    if AwtarchyYaziDeleteCollectionSelection() then
        return
    elseif selected == 1 then
        ya.emit("remove", { force = true })
    elseif selected == 2 then
        ya.emit("remove", { permanently = true })
    end
end

function AwtarchyYaziDeleteMenu:new(area)
    if not self._visible then
        self._area = ui.Rect {}
        self._list_area = ui.Rect {}
        return self
    end

    local width = math.min(50, area.w)
    local height = math.min(6, area.h)
    if width < 34 or height < 6 then
        self._area = ui.Rect {}
        self._list_area = ui.Rect {}
        return self
    end

    local x = area.x + math.floor((area.w - width) / 2)
    local y = area.y + math.floor((area.h - height) / 2)
    self._area = ui.Rect { x = x, y = y, w = width, h = height }
    self._list_area = ui.Rect { x = x + 1, y = y + 1, w = width - 2, h = 2 }
    self._footer_area = ui.Rect { x = x + 1, y = y + 4, w = width - 2, h = 1 }
    return self
end

function AwtarchyYaziDeleteMenu:reflow()
    return self._visible and self._area.w > 0 and { self } or {}
end

function AwtarchyYaziDeleteMenu:redraw()
    if not self._visible or self._area.w == 0 then
        return {}
    end

    local actions = {
        { label = "Move to trash", shortcut = "y / Enter" },
        { label = "Permanently delete...", shortcut = "D" },
    }
    local rows = {}
    for i, action in ipairs(actions) do
        local gap = math.max(1, self._list_area.w - #action.label - #action.shortcut - 2)
        local row = ui.Line {
            ui.Span(" " .. action.label):style(th.help.action),
            ui.Span(string.rep(" ", gap)),
            ui.Span(action.shortcut):style(th.help.chord),
            ui.Span(" "),
        }
        if i == self._selected then
            row:style(th.help.hovered)
        end
        rows[#rows + 1] = row
    end

    return {
        ui.Clear(self._area),
        ui.Border(ui.Edge.ALL)
            :area(self._area)
            :type(ui.Border.PLAIN)
            :style(th.help.border)
            :title(ui.Line(" Delete "):align(ui.Align.CENTER)),
        ui.List(rows):area(self._list_area),
        ui.Text(ui.Line(" ↑/↓ choose   Enter confirm   Esc cancel "):align(ui.Align.CENTER))
            :area(self._footer_area),
    }
end

Modal:children_add(AwtarchyYaziDeleteMenu, 30)

function AwtarchyYaziRemoveMenu()
    AwtarchyYaziDeleteMenu:show()
end

function AwtarchyYaziYank()
    if AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:submit(1)
    else
        ya.emit("yank", {})
    end
end

function AwtarchyYaziPermanentDelete()
    if AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:submit(2)
    elseif AwtarchyYaziDeleteCollectionSelection() then
        return
    else
        ya.emit("remove", { permanently = true })
    end
end

function AwtarchyYaziSearchMenu()
    ya.async(function()
        local choice = ya.which {
            cands = {
                { on = "n", desc = "Name search" },
                { on = "c", desc = "Content search" },
            },
            silent = false,
        }

        if choice == 1 then
            ya.emit("search", { via = "fd" })
        elseif choice == 2 then
            ya.emit("search", { via = "rg" })
        end
    end)
end

function AwtarchyYaziBookmarkHovered()
    if AwtarchyYaziContextMenu
        and AwtarchyYaziContextMenu._visible
        and AwtarchyYaziContextMenu._kind == "background"
    then
        AwtarchyYaziBookmarkTarget(tostring(cx.active.current.cwd), true)
        return
    end

    local hovered = cx.active.current.hovered
    if not hovered or AwtarchyYaziIsCollectionItemUrl(hovered.url) then
        return
    end

    AwtarchyYaziBookmarkTarget(tostring(hovered.url), hovered.cha.is_dir)
end

function AwtarchyYaziOpenHoveredTab()
    local hovered = cx.active.current.hovered
    if AwtarchyYaziNavigateCollection(hovered, true) then
        return
    elseif hovered and hovered.cha.is_dir then
        ya.emit("tab_create", { tostring(hovered.url), raw = true })
    end
end

local AwtarchyYaziInitialRatio = nil
local AwtarchyYaziPreviewHiddenRestore = nil
local AwtarchyYaziPreviewMaxRestore = nil
AwtarchyYaziPreviewMaximized = false

local function AwtarchyYaziRatio()
    local ratio = rt.mgr.ratio
    if not AwtarchyYaziInitialRatio then
        AwtarchyYaziInitialRatio = { ratio[1], ratio[2], ratio[3] }
    end
    return { ratio[1], ratio[2], ratio[3] }
end

local function AwtarchyYaziApplyRatio(ratio)
    rt.mgr.ratio = { ratio[1], ratio[2], ratio[3] }
    ya.emit("app:resize", {})
end

function AwtarchyYaziTogglePreview()
    local ratio = AwtarchyYaziRatio()

    if AwtarchyYaziPreviewMaximized then
        AwtarchyYaziPreviewMaximized = false
        ratio = AwtarchyYaziPreviewMaxRestore or ratio
        AwtarchyYaziPreviewMaxRestore = nil
        AwtarchyYaziApplyRatio(ratio)
    end

    ratio = AwtarchyYaziRatio()
    if ratio[3] > 0 then
        AwtarchyYaziPreviewHiddenRestore = ratio
        AwtarchyYaziApplyRatio { ratio[1], ratio[2], 0 }
    else
        local restore = AwtarchyYaziPreviewHiddenRestore or AwtarchyYaziInitialRatio
        if restore and restore[3] > 0 then
            AwtarchyYaziApplyRatio(restore)
        end
        AwtarchyYaziPreviewHiddenRestore = nil
    end
end

function AwtarchyYaziTogglePreviewMax()
    local ratio = AwtarchyYaziRatio()
    if AwtarchyYaziPreviewMaximized then
        AwtarchyYaziPreviewMaximized = false
        AwtarchyYaziApplyRatio(AwtarchyYaziPreviewMaxRestore or AwtarchyYaziInitialRatio or ratio)
        AwtarchyYaziPreviewMaxRestore = nil
        return
    end

    AwtarchyYaziPreviewMaxRestore = ratio
    AwtarchyYaziPreviewMaximized = true
    AwtarchyYaziApplyRatio({ 0, 0, 9999 })
end

local AwtarchyYaziTextExtensions = {
    txt = true, md = true, markdown = true, log = true, csv = true, tsv = true,
    json = true, jsonc = true, yaml = true, yml = true, toml = true,
    ini = true, conf = true, cfg = true, xml = true, html = true, htm = true,
    css = true, scss = true, less = true, js = true, jsx = true, ts = true,
    tsx = true, lua = true, py = true, rb = true, rs = true, go = true,
    c = true, cc = true, cpp = true, h = true, hpp = true, cs = true,
    java = true, kt = true, kts = true, sh = true, bash = true, zsh = true,
    fish = true, ps1 = true, bat = true, cmd = true, sql = true, env = true,
}

local AwtarchyYaziTextNames = {
    dockerfile = true,
    makefile = true,
    readme = true,
    [".gitignore"] = true,
    [".gitattributes"] = true,
    [".editorconfig"] = true,
}

local function AwtarchyYaziHoveredTextFile()
    local hovered = cx.active.current.hovered
    if not hovered or hovered.cha.is_dir then return nil end

    local mime = hovered:mime() or ""
    if mime:match("^text/")
        or mime == "application/json"
        or mime == "application/xml"
        or mime == "application/javascript"
        or mime == "application/x-javascript"
        or mime == "application/x-shellscript"
    then
        return hovered
    end

    local name = tostring(hovered.url.name or ""):lower()
    if AwtarchyYaziTextNames[name] then return hovered end

    local ext = name:match("%.([^%.]+)$")
    if ext and AwtarchyYaziTextExtensions[ext] then return hovered end
    return nil
end

local function AwtarchyYaziPreviewTextSelectable()
    return AwtarchyYaziPreviewMaximized and AwtarchyYaziHoveredTextFile() ~= nil
end

local function AwtarchyYaziShellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function AwtarchyYaziSelectPreviewText()
    local hovered = AwtarchyYaziHoveredTextFile()
    if not hovered then
        ya.notify {
            title = "Select text",
            content = "The highlighted item is not recognized as a text file.",
            timeout = 3,
            level = "warn",
        }
        return
    end

    local path = AwtarchyYaziShellQuote(tostring(hovered.url))
    local command = "clear; " ..
        "cat -- " .. path .. "; " ..
        "printf '\\n\\nSelect text with the mouse, copy with Ctrl+Shift+C, then press Enter to return to Yazi...'; " ..
        "read -r _"

    ya.emit("shell", { run = command, block = true })
end

function AwtarchyYaziEscape()
    if AwtarchyYaziContextMenu and AwtarchyYaziContextMenu._visible then
        AwtarchyYaziContextMenu:hide()
        return
    end

    if AwtarchyYaziDeleteMenu and AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:hide()
        return
    end

    if AwtarchyYaziPreviewMaximized then
        AwtarchyYaziPreviewMaximized = false
        AwtarchyYaziApplyRatio(
            AwtarchyYaziPreviewMaxRestore
                or AwtarchyYaziInitialRatio
                or { 1, 4, 3 }
        )
        AwtarchyYaziPreviewMaxRestore = nil
        return
    end

    ya.emit("escape", {})
end

AwtarchyYaziPreviewButton = {
    _id = "awtarchy-yazi-preview-button",
}

function AwtarchyYaziPreviewButton:new(area)
    return setmetatable({ _area = area }, { __index = self })
end

function AwtarchyYaziPreviewButton:reflow()
    return { self }
end

function AwtarchyYaziPreviewButton:redraw()
    local label = AwtarchyYaziPreviewMaximized and " 󰘕 [m x] " or " 󰹶 [m x] "
    return {
        ui.Text(ui.Line(label):style(ui.Style():reverse()))
            :area(self._area)
            :align(ui.Align.RIGHT),
    }
end

function AwtarchyYaziPreviewButton:click(event, up)
    if up or not event.is_left then
        return
    end
    AwtarchyYaziTogglePreviewMax()
end

AwtarchyYaziTextSelectButton = {
    _id = "awtarchy-yazi-text-select-button",
}

function AwtarchyYaziTextSelectButton:new(area)
    return setmetatable({ _area = area }, { __index = self })
end

function AwtarchyYaziTextSelectButton:reflow()
    return { self }
end

function AwtarchyYaziTextSelectButton:redraw()
    if not AwtarchyYaziPreviewTextSelectable() then return {} end
    return {
        ui.Text(ui.Line(" Select text [m c] "):style(ui.Style():reverse()))
            :area(self._area)
            :align(ui.Align.LEFT),
    }
end

function AwtarchyYaziTextSelectButton:click(event, up)
    if up or not event.is_left or not AwtarchyYaziPreviewTextSelectable() then return end
    AwtarchyYaziSelectPreviewText()
end

local AwtarchyYaziDefaultPreviewNew = Preview.new
local AwtarchyYaziDefaultPreviewRedraw = Preview.redraw

function Preview:new(area, tab)
    local reserve_control_row = area.w >= 3 and area.h >= 2
    local preview_area = reserve_control_row
        and ui.Rect { x = area.x, y = area.y, w = area.w, h = area.h - 1 }
        or area

    local me = AwtarchyYaziDefaultPreviewNew(self, preview_area, tab)
    if reserve_control_row then
        local preview_button_width = math.min(10, area.w)
        me._awtarchy_text_select_button = AwtarchyYaziTextSelectButton:new(ui.Rect {
            x = area.x,
            y = area.y + area.h - 1,
            w = math.min(19, math.max(0, area.w - preview_button_width)),
            h = 1,
        })
        me._awtarchy_preview_button = AwtarchyYaziPreviewButton:new(ui.Rect {
            x = area.x + area.w - preview_button_width,
            y = area.y + area.h - 1,
            w = preview_button_width,
            h = 1,
        })
    end
    return me
end

function Preview:reflow()
    local components = { self }
    if self._awtarchy_text_select_button then
        components[#components + 1] = self._awtarchy_text_select_button
    end
    if self._awtarchy_preview_button then
        components[#components + 1] = self._awtarchy_preview_button
    end
    return components
end

function Preview:redraw()
    local elements = AwtarchyYaziDefaultPreviewRedraw(self) or {}
    if self._awtarchy_text_select_button then
        elements = ya.list_merge(elements, ui.redraw(self._awtarchy_text_select_button))
    end
    if self._awtarchy_preview_button then
        elements = ya.list_merge(elements, ui.redraw(self._awtarchy_preview_button))
    end
    return elements
end

AwtarchyYaziPreviewToggleButton = { _id = "awtarchy-yazi-preview-toggle-button" }

function AwtarchyYaziPreviewToggleButton:new(area)
    return setmetatable({ _area = area }, { __index = self })
end

function AwtarchyYaziPreviewToggleButton:reflow()
    return { self }
end

function AwtarchyYaziPreviewToggleButton:redraw()
    local visible = AwtarchyYaziRatio()[3] > 0
    local label = visible and " 󰞔 [m v] " or " 󰞓 [m v] "
    return {
        ui.Text(ui.Line(label):style(ui.Style():reverse()))
            :area(self._area)
            :align(ui.Align.CENTER),
    }
end

function AwtarchyYaziPreviewToggleButton:click(event, up)
    if up or not event.is_left then
        return
    end
    AwtarchyYaziTogglePreview()
end

local AwtarchyYaziDefaultCurrentNew = Current.new
local AwtarchyYaziDefaultCurrentRedraw = Current.redraw

function Current:new(area, tab)
    local reserve_control_row = area.w >= 3 and area.h >= 2
    local current_area = reserve_control_row
        and ui.Rect { x = area.x, y = area.y, w = area.w, h = area.h - 1 }
        or area

    local me = AwtarchyYaziDefaultCurrentNew(self, current_area, tab)
    if reserve_control_row then
        local preview_toggle_width = math.min(10, area.w)
        me._awtarchy_preview_toggle_button = AwtarchyYaziPreviewToggleButton:new(ui.Rect {
            x = area.x + area.w - preview_toggle_width,
            y = area.y + area.h - 1,
            w = preview_toggle_width,
            h = 1,
        })
    end
    return me
end

function Current:reflow()
    local components = { self }
    if self._awtarchy_preview_toggle_button then
        components[#components + 1] = self._awtarchy_preview_toggle_button
    end
    return components
end

function Current:redraw()
    local elements = AwtarchyYaziDefaultCurrentRedraw(self) or {}
    if self._awtarchy_preview_toggle_button then
        elements = ya.list_merge(elements, ui.redraw(self._awtarchy_preview_toggle_button))
    end
    return elements
end

local function AwtarchyYaziArchiveSnapshot()
    local tab = cx.active
    local files = {}

    if #tab.selected > 0 then
        for _, file in pairs(tab.selected) do
            files[#files + 1] = {
                path = tostring(file.path),
                name = file.name,
                stem = file.url.stem or file.name,
                parent = file.url.parent and tostring(file.url.parent) or "",
                is_dir = file.cha.is_dir,
            }
        end
    elseif tab.current.hovered then
        local file = tab.current.hovered
        files[1] = {
            path = tostring(file.path),
            name = file.name,
            stem = file.url.stem or file.name,
            parent = file.url.parent and tostring(file.url.parent) or "",
            is_dir = file.cha.is_dir,
        }
    end

    return {
        cwd = tostring(tab.current.cwd),
        files = files,
    }
end

local function AwtarchyYaziArchiveNotify(content, level)
    ya.notify {
        title = "Archive",
        content = content,
        timeout = 4,
        level = level,
    }
end

local function AwtarchyYaziRun7z(args, cwd)
    local commands = ya.target_os() == "windows"
        and { "7z.exe", "7zz.exe", "7z" }
        or { "7zz", "7z" }
    local last_error = nil

    for _, command in ipairs(commands) do
        local output, err = Command(command):arg(args):cwd(cwd):output()
        if output then
            return output, nil
        end
        last_error = err
    end

    return nil, last_error
end

local function AwtarchyYaziUniqueZip(cwd, requested)
    local name = requested
    if name:lower():sub(-4) ~= ".zip" then
        name = name .. ".zip"
    end

    local stem = name:sub(1, -5)
    local index = 1
    while true do
        local candidate = index == 1
            and name
            or string.format("%s (%d).zip", stem, index)
        local url = Url(cwd):join(candidate)
        local cha = fs.cha(url)
        if not cha then
            return url
        end
        index = index + 1
    end
end

function AwtarchyYaziCompressSelection()
    local snapshot = AwtarchyYaziArchiveSnapshot()
    ya.async(function()
        if #snapshot.files == 0 then
            return AwtarchyYaziArchiveNotify("Nothing selected.", "warn")
        end

        for _, file in ipairs(snapshot.files) do
            if file.parent ~= snapshot.cwd then
                return AwtarchyYaziArchiveNotify(
                    "ZIP creation currently requires all selected items to be in the current directory.",
                    "warn"
                )
            end
        end

        local default_name
        if #snapshot.files == 1 then
            default_name = (snapshot.files[1].stem ~= "" and snapshot.files[1].stem or snapshot.files[1].name) .. ".zip"
        else
            default_name = "Archive.zip"
        end

        local requested, event = ya.input {
            pos = { "center", w = 52 },
            title = "Compress to ZIP:",
            value = default_name,
        }
        if event ~= 1 or not requested then
            return
        end

        requested = requested:match("^%s*(.-)%s*$") or ""
        if requested == "" then
            return AwtarchyYaziArchiveNotify("Archive name cannot be empty.", "warn")
        elseif requested == "." or requested == ".."
            or requested:find("[/\\]")
            or requested:find(":", 1, true)
        then
            return AwtarchyYaziArchiveNotify("Enter a file name, not a path.", "warn")
        end

        local target = AwtarchyYaziUniqueZip(snapshot.cwd, requested)
        local args = { "a", "-tzip", tostring(target), "--" }
        for _, file in ipairs(snapshot.files) do
            args[#args + 1] = file.name
        end

        local output, err = AwtarchyYaziRun7z(args, snapshot.cwd)
        if not output then
            return AwtarchyYaziArchiveNotify(
                "7-Zip is unavailable. Install 7-Zip/7zip to use ZIP actions.",
                "error"
            )
        elseif not output.status.success then
            local detail = output.stderr ~= "" and output.stderr or tostring(err or "7-Zip failed")
            return AwtarchyYaziArchiveNotify(detail, "error")
        end

        AwtarchyYaziArchiveNotify("Created " .. tostring(target.name or target), "info")
        ya.emit("reveal", { target })
    end)
end

local function AwtarchyYaziSingleZipSnapshot()
    local snapshot = AwtarchyYaziArchiveSnapshot()
    if #snapshot.files ~= 1 or snapshot.files[1].name:lower():sub(-4) ~= ".zip" then
        return nil
    end
    return snapshot
end

function AwtarchyYaziExtractZipHere()
    local snapshot = AwtarchyYaziSingleZipSnapshot()
    ya.async(function()
        if not snapshot then
            return AwtarchyYaziArchiveNotify("Select one .zip file to extract.", "warn")
        end

        local zip = snapshot.files[1]
        local output = AwtarchyYaziRun7z(
            { "x", "-y", "-aou", zip.path, "-o" .. snapshot.cwd },
            snapshot.cwd
        )
        if not output then
            return AwtarchyYaziArchiveNotify(
                "7-Zip is unavailable. Install 7-Zip/7zip to use ZIP actions.",
                "error"
            )
        elseif not output.status.success then
            return AwtarchyYaziArchiveNotify(output.stderr ~= "" and output.stderr or "Extraction failed.", "error")
        end

        AwtarchyYaziArchiveNotify("Extracted into current directory.", "info")
        ya.emit("refresh", {})
    end)
end

function AwtarchyYaziExtractZipFolder()
    local snapshot = AwtarchyYaziSingleZipSnapshot()
    ya.async(function()
        if not snapshot then
            return AwtarchyYaziArchiveNotify("Select one .zip file to extract.", "warn")
        end

        local zip = snapshot.files[1]
        local base = zip.stem ~= "" and zip.stem or "Extracted"
        local index = 1
        local target

        while true do
            local name = index == 1 and base or string.format("%s (%d)", base, index)
            local candidate = Url(snapshot.cwd):join(name)
            if not fs.cha(candidate) then
                target = candidate
                break
            end
            index = index + 1
        end

        local ok, mkdir_err = fs.create("dir", target)
        if not ok then
            return AwtarchyYaziArchiveNotify("Could not create extraction folder: " .. tostring(mkdir_err), "error")
        end

        local output = AwtarchyYaziRun7z(
            { "x", "-y", zip.path, "-o" .. tostring(target) },
            snapshot.cwd
        )
        if not output then
            return AwtarchyYaziArchiveNotify(
                "7-Zip is unavailable. Install 7-Zip/7zip to use ZIP actions.",
                "error"
            )
        elseif not output.status.success then
            return AwtarchyYaziArchiveNotify(output.stderr ~= "" and output.stderr or "Extraction failed.", "error")
        end

        AwtarchyYaziArchiveNotify("Extracted to " .. tostring(target.name or target), "info")
        ya.emit("refresh", {})
        ya.emit("reveal", { target })
    end)
end

local AwtarchyYaziFileActions = {
    { label = "Open", shortcut = "Enter", action = "smart_open" },
    { label = "Open with...", shortcut = "O", action = "open_with" },
    { label = "Bookmark / unbookmark", shortcut = "B", action = "bookmark_hovered" },
    { label = "Rename", shortcut = "R", action = "rename" },
    { label = "Drag out...", shortcut = "d g", action = "drag_out" },
    { label = "Copy", shortcut = "Ctrl+C / y", action = "copy" },
    { label = "Cut", shortcut = "Ctrl+X / Y", action = "cut" },
    { label = "Copy path", shortcut = "c c", action = "copy_path" },
    { label = "Compress to ZIP...", shortcut = "c z", action = "compress_zip" },
    { label = "Details", shortcut = "Tab", action = "details" },
    { label = "Trash", shortcut = "d d", action = "trash" },
}

local AwtarchyYaziDropActions = {
    { label = "Copy to folder", shortcut = "copy", action = "drop_copy" },
    { label = "Move to folder", shortcut = "move", action = "drop_move" },
}

local AwtarchyYaziDragState = nil

local function AwtarchyYaziDragSources(file)
    local sources = {}

    if file:is_selected() and #cx.active.selected > 0 then
        for _, selected in pairs(cx.active.selected) do
            sources[#sources + 1] = {
                path = tostring(selected.path),
                name = selected.name,
                is_dir = selected.cha.is_dir,
            }
        end
    else
        sources[1] = {
            path = tostring(file.path),
            name = file.name,
            is_dir = file.cha.is_dir,
        }
    end

    return sources
end

local function AwtarchyYaziCanDropInto(target, sources)
    local target_url = Url(target)
    for _, source in ipairs(sources) do
        if source.is_dir and target_url:starts_with(Url(source.path)) then
            return false
        end
    end
    return true
end

local function AwtarchyYaziDropInto(op, target, sources)
    if not target or not sources or #sources == 0 then
        return
    end

    ya.async(function()
        for _, source in ipairs(sources) do
            local from = Url(source.path)
            local to = Url(target):join(source.name)
            ya.task(op, { from = from, to = to }):spawn()
        end
    end)

    ya.notify {
        title = "Yazi",
        content = string.format(
            "%s %d item(s) to %s",
            op == "move" and "Moving" or "Copying",
            (#sources),
            tostring(Url(target).name or target)
        ),
        timeout = 2,
    }
end

local AwtarchyYaziFolderActions = {
    { label = "New file", shortcut = "a", action = "new_file" },
    { label = "New folder", shortcut = "a /", action = "new_folder" },
    { label = "Paste", shortcut = "Ctrl+V / p", action = "paste" },
    { label = "Terminal here", shortcut = "t e", action = "terminal" },
    { label = "Bookmark / unbookmark folder", shortcut = "B", action = "bookmark_current" },
}

AwtarchyYaziContextMenu = {
    _id = "awtarchy-yazi-context-menu",
    _visible = false,
    _kind = "item",
    _x = 0,
    _y = 0,
    _area = ui.Rect {},
    _list_area = ui.Rect {},
    _hovered_row = nil,
    _selection_count = 0,
    _drop_target = nil,
    _drop_sources = nil,
}

function AwtarchyYaziContextMenu:show(kind, x, y, selection_count)
    self._kind = kind
    self._x = x
    self._y = y
    self._selection_count = selection_count or 0
    self._hovered_row = nil
    self._visible = true
    ui.render()
end

function AwtarchyYaziContextMenu:show_drop(target, sources, x, y)
    self._drop_target = tostring(target)
    self._drop_sources = sources
    self:show("drop", x, y, #sources)
end

function AwtarchyYaziContextMenu:hide()
    if not self._visible then
        return
    end

    self._visible = false
    self._hovered_row = nil
    self._drop_target = nil
    self._drop_sources = nil
    ui.render()
end

function AwtarchyYaziContextMenu:title()
    if self._kind == "background" then
        return " Folder actions "
    elseif self._kind == "drop" then
        local target = self._drop_target and Url(self._drop_target) or nil
        return " Drop into " .. tostring(target and target.name or "folder") .. " "
    elseif self._selection_count > 1 then
        return " " .. tostring(self._selection_count) .. " selected "
    end

    return " Item actions "
end

function AwtarchyYaziContextMenu:actions()
    if self._kind == "background" then
        return AwtarchyYaziFolderActions
    elseif self._kind == "drop" then
        return AwtarchyYaziDropActions
    end

    local hovered = cx.active.current.hovered
    if self._selection_count > 1 then
        return {
            {
                label = "Rename " .. tostring(self._selection_count) .. " items...",
                shortcut = "R",
                action = "bulk_rename",
            },
            { label = "Drag out...", shortcut = "d g", action = "drag_out" },
            { label = "Copy", shortcut = "Ctrl+C / y", action = "copy" },
            { label = "Cut", shortcut = "Ctrl+X / Y", action = "cut" },
            { label = "Compress to ZIP...", shortcut = "c z", action = "compress_zip" },
            { label = "Trash " .. tostring(self._selection_count) .. " items", shortcut = "d d", action = "trash" },
        }
    end

    if hovered and hovered.cha.is_dir then
        return {
            { label = "Enter folder", shortcut = "Enter / l", action = "smart_open" },
            { label = "Open in new tab", shortcut = "t n", action = "open_new_tab" },
            { label = "Bookmark / unbookmark", shortcut = "B", action = "bookmark_hovered" },
            { label = "Rename", shortcut = "R", action = "rename" },
            { label = "Drag out...", shortcut = "d g", action = "drag_out" },
            { label = "Copy", shortcut = "Ctrl+C / y", action = "copy" },
            { label = "Cut", shortcut = "Ctrl+X / Y", action = "cut" },
            { label = "Copy path", shortcut = "c c", action = "copy_path" },
            { label = "Compress to ZIP...", shortcut = "c z", action = "compress_zip" },
            { label = "Details", shortcut = "Tab", action = "details" },
            { label = "Trash", shortcut = "d d", action = "trash" },
        }
    end

    local actions = {}
    for _, action in ipairs(AwtarchyYaziFileActions) do
        actions[#actions + 1] = action
    end

    if hovered and hovered.name:lower():sub(-4) == ".zip" then
        actions[#actions + 1] = { label = "Extract here", shortcut = "e h", action = "extract_here" }
        actions[#actions + 1] = { label = "Extract to folder", shortcut = "e f", action = "extract_folder" }
    end

    return actions
end

function AwtarchyYaziContextMenu:footer()
    if self._kind == "background" then
        return {
            "Keys: a create | Ctrl+V/p paste | t e terminal | B bookmark",
            "Navigate: b bookmarks | r recents | g b/g r explicit go",
        }
    elseif self._kind == "drop" then
        return {
            "Release chose this folder as the destination",
            "Choose Copy or Move; click elsewhere to cancel",
        }
    elseif self._selection_count > 1 then
        return {
            "Keys: R bulk rename | d g drag out | Ctrl+C/X copy/cut",
            "More: c z ZIP | d d trash | Shift+D permanent delete",
        }
    end

    local hovered = cx.active.current.hovered
    if hovered and hovered.cha.is_dir then
        return {
            "Keys: Enter open | t n new tab | B bookmark | R rename",
            "More: Ctrl+C/X copy/cut | c c path | Tab info | c z ZIP | d d trash",
        }
    end

    return {
        "Keys: Enter open | d g drag out | R rename | Ctrl+C/X copy/cut",
        "More: c z ZIP | c c path | Tab info | d d trash | e h/e f extract ZIP",
    }
end

function AwtarchyYaziContextMenu:new(area)
    self._screen = area
    if not self._visible then
        self._area = ui.Rect {}
        self._list_area = ui.Rect {}
        return self
    end

    local actions = self:actions()
    local width = math.min(56, area.w)
    local height = math.min(#actions + 4, area.h)

    if width < 28 or height < #actions + 4 then
        self._area = ui.Rect {}
        self._list_area = ui.Rect {}
        return self
    end

    local max_x = area.x + area.w - width
    local max_y = area.y + area.h - height
    local x = math.max(area.x, math.min(self._x, max_x))
    local y = math.max(area.y, math.min(self._y, max_y))

    self._area = ui.Rect { x = x, y = y, w = width, h = height }
    self._list_area = ui.Rect {
        x = x + 1,
        y = y + 1,
        w = width - 2,
        h = #actions,
    }
    self._footer_area = ui.Rect {
        x = x + 1,
        y = y + 1 + #actions,
        w = width - 2,
        h = 2,
    }

    return self
end

function AwtarchyYaziContextMenu:reflow()
    return self._visible and self._area.w > 0 and { self } or {}
end

function AwtarchyYaziContextMenu:redraw()
    if not self._visible or self._area.w == 0 then
        return {}
    end

    local rows = {}
    local content_width = self._list_area.w
    for i, action in ipairs(self:actions()) do
        local gap = math.max(1, content_width - #action.label - #action.shortcut - 2)
        local row = ui.Line {
            ui.Span(" " .. action.label):style(th.help.action),
            ui.Span(string.rep(" ", gap)),
            ui.Span(action.shortcut):style(th.help.chord),
            ui.Span(" "),
        }
        if i == self._hovered_row then
            row:style(th.help.hovered)
        end
        rows[#rows + 1] = row
    end

    local footer = self:footer()
    return {
        ui.Clear(self._area),
        ui.Border(ui.Edge.ALL)
            :area(self._area)
            :type(ui.Border.PLAIN)
            :style(th.help.border)
            :title(ui.Line(self:title()):align(ui.Align.CENTER)),
        ui.List(rows):area(self._list_area),
        ui.Text({
            ui.Line(" " .. footer[1]),
            ui.Line(" " .. footer[2]),
        }):area(self._footer_area),
    }
end

function AwtarchyYaziContextMenu:run(action)
    local count = self._selection_count > 0 and self._selection_count or 1
    local drop_target = self._drop_target
    local drop_sources = self._drop_sources
    self._visible = false
    self._hovered_row = nil
    self._drop_target = nil
    self._drop_sources = nil
    ui.render()

    if action == "smart_open" then
        AwtarchyYaziSmartEnter()
    elseif action == "open_new_tab" then
        AwtarchyYaziOpenHoveredTab()
    elseif action == "open_with" then
        AwtarchyYaziOpenFiles(true, true)
    elseif action == "rename" then
        ya.emit("rename", { hovered = true })
    elseif action == "bulk_rename" then
        ya.emit("rename", {})
    elseif action == "bookmark_hovered" then
        AwtarchyYaziBookmarkHovered()
    elseif action == "bookmark_current" then
        AwtarchyYaziBookmarkTarget(tostring(cx.active.current.cwd), true)
    elseif action == "drag_out" then
        ya.emit("plugin", { "drag" })
    elseif action == "copy" then
        ya.emit("yank", {})
        ya.notify { title = "Yazi", content = "Copied " .. tostring(count) .. " item(s)", timeout = 2 }
    elseif action == "cut" then
        ya.emit("yank", { cut = true })
        ya.notify { title = "Yazi", content = "Cut " .. tostring(count) .. " item(s)", timeout = 2 }
    elseif action == "copy_path" then
        ya.emit("copy", { "path", hovered = true })
        ya.notify { title = "Clipboard", content = "Path copied", timeout = 2 }
    elseif action == "compress_zip" then
        AwtarchyYaziCompressSelection()
    elseif action == "extract_here" then
        AwtarchyYaziExtractZipHere()
    elseif action == "extract_folder" then
        AwtarchyYaziExtractZipFolder()
    elseif action == "details" then
        ya.emit("spot", {})
    elseif action == "trash" then
        AwtarchyYaziRemoveMenu()
    elseif action == "new_file" then
        ya.emit("create", { dir = false })
    elseif action == "new_folder" then
        ya.emit("create", { dir = true })
    elseif action == "paste" then
        local yanked = #cx.yanked
        ya.emit("paste", {})
        if yanked > 0 then
            ya.notify { title = "Yazi", content = "Pasting " .. tostring(yanked) .. " item(s)...", timeout = 2 }
        end
    elseif action == "terminal" then
        ya.emit("shell", { '"$HOME/.config/hypr/scripts/default_terminal.sh" -- bash', orphan = true })
    elseif action == "drop_copy" then
        AwtarchyYaziDropInto("copy", drop_target, drop_sources)
    elseif action == "drop_move" then
        AwtarchyYaziDropInto("move", drop_target, drop_sources)
    end
end

function AwtarchyYaziContextMenu:move(event)
    local row = nil
    if event.x >= self._list_area.x
        and event.x < self._list_area.x + self._list_area.w
        and event.y >= self._list_area.y
        and event.y < self._list_area.y + self._list_area.h
    then
        local candidate = event.y - self._list_area.y + 1
        if self:actions()[candidate] then
            row = candidate
        end
    end

    if row ~= self._hovered_row then
        self._hovered_row = row
        ui.render()
    end
end

function AwtarchyYaziContextMenu:click(event, up)
    if up or not event.is_left then
        return
    end

    local row = event.y - self._list_area.y + 1
    local action = self:actions()[row]
    if action then
        self:run(action.action)
    else
        self:hide()
    end
end

Modal:children_add(AwtarchyYaziContextMenu, 20)

local AwtarchyYaziDefaultRootMove = Root.move

function Root:move(event)
    if AwtarchyYaziContextMenu._visible then
        return AwtarchyYaziContextMenu:move(event)
    end
    return AwtarchyYaziDefaultRootMove(self, event)
end

local AwtarchyYaziDefaultHeaderCwd = Header.cwd
local AwtarchyYaziBreadcrumbTarget = nil

local function AwtarchyYaziPathIsAncestor(base, target)
    if base == target then
        return true
    elseif base == "/" then
        return target:sub(1, 1) == "/"
    end
    return target:sub(1, #base + 1) == base .. "/"
end

local function AwtarchyYaziBreadcrumbSegments(path)
    if path:sub(1, 1) ~= "/" then
        return nil
    end

    local segments = {}
    local home = os.getenv("HOME")
    local current
    local rest

    if home and (path == home or path:sub(1, #home + 1) == home .. "/") then
        current = home
        rest = path == home and "" or path:sub(#home + 2)
        segments[#segments + 1] = { text = "~", target = home }
    else
        current = "/"
        rest = path:sub(2)
        segments[#segments + 1] = { text = "/", target = "/" }
    end

    for part in rest:gmatch("[^/]+") do
        local text
        if current == "/" then
            current = "/" .. part
            text = part
        else
            current = current .. "/" .. part
            text = "/" .. part
        end
        segments[#segments + 1] = { text = text, target = current }
    end

    return segments
end

ps.sub("cd", function()
    if not AwtarchyYaziBreadcrumbTarget then
        return
    end

    local cwd = tostring(cx.active.current.cwd)
    if cwd == AwtarchyYaziBreadcrumbTarget
        or not AwtarchyYaziPathIsAncestor(cwd, AwtarchyYaziBreadcrumbTarget)
    then
        AwtarchyYaziBreadcrumbTarget = nil
    end
end)

local function AwtarchyYaziHeaderFallback(max, cwd, flags)
    if max <= 0 then return "" end

    local flag_width = ui.Line(flags):width()
    if flags ~= "" and flag_width >= max then
        return ui.Span(ui.truncate(flags, { max = max, rtl = true }))
            :style(th.mgr.find_keyword)
    end

    local path_max = math.max(0, max - flag_width)
    local path = ui.truncate(ya.readable_path(cwd), { max = path_max, rtl = true })
    local spans = { ui.Span(path):style(th.mgr.cwd) }
    if flags ~= "" then
        spans[#spans + 1] = ui.Span(flags):style(th.mgr.find_keyword)
    end
    return ui.Line(spans)
end

function Header:cwd()
    local max = self._area.w - self._right_width
    local cwd = tostring(self._current.cwd)
    local flags = self:flags()
    local flag_width = ui.Line(flags):width()
    local path_max = math.max(0, max - flag_width)

    self._awtarchy_breadcrumbs = {}
    if max <= 0 then return "" end

    local segments = AwtarchyYaziBreadcrumbSegments(cwd)
    if not segments then
        return AwtarchyYaziHeaderFallback(max, cwd, flags)
    end

    if AwtarchyYaziBreadcrumbTarget
        and cwd ~= AwtarchyYaziBreadcrumbTarget
        and AwtarchyYaziPathIsAncestor(cwd, AwtarchyYaziBreadcrumbTarget)
    then
        for _, segment in ipairs(AwtarchyYaziBreadcrumbSegments(AwtarchyYaziBreadcrumbTarget) or {}) do
            if segment.target ~= cwd and AwtarchyYaziPathIsAncestor(cwd, segment.target) then
                segment.forward = true
                segments[#segments + 1] = segment
            end
        end
    end

    local total = 0
    for _, segment in ipairs(segments) do total = total + ui.Line(segment.text):width() end

    local clipped = false
    while total > path_max and #segments > 1 do
        total = total - ui.Line(segments[1].text):width()
        table.remove(segments, 1)
        clipped = true
    end
    if clipped then total = total + 1 end
    if total > path_max then return AwtarchyYaziHeaderFallback(max, cwd, flags) end

    local spans = {}
    local x = self._area.x
    if clipped then
        spans[#spans + 1] = ui.Span("…"):style(ui.Style():dim())
        x = x + 1
    end

    for _, segment in ipairs(segments) do
        local width = ui.Line(segment.text):width()
        local style = segment.forward and ui.Style():dim() or th.mgr.cwd
        spans[#spans + 1] = ui.Span(segment.text):style(style)
        self._awtarchy_breadcrumbs[#self._awtarchy_breadcrumbs + 1] = {
            x1 = x,
            x2 = x + width - 1,
            target = segment.target,
            forward = segment.forward == true,
        }
        x = x + width
    end

    if flags ~= "" then spans[#spans + 1] = ui.Span(flags):style(th.mgr.find_keyword) end
    return ui.Line(spans)
end

function Header:click(event, up)
    if up or (not event.is_left and not event.is_right) then
        return
    end

    local path_width = math.max(0, self._area.w - (self._right_width or 0))
    if event.x >= self._area.x + path_width then
        return
    end

    if event.is_right then
        local cwd = ya.readable_path(tostring(self._current.cwd))
        ya.emit("copy", { "dirpath" })
        ya.notify {
            title = "Clipboard",
            content = "Copied to clipboard: " .. cwd,
            timeout = 2,
        }
        return
    end

    local cwd = tostring(self._current.cwd)
    local segments = AwtarchyYaziBreadcrumbSegments(cwd) or {}
    if AwtarchyYaziBreadcrumbTarget
        and cwd ~= AwtarchyYaziBreadcrumbTarget
        and AwtarchyYaziPathIsAncestor(cwd, AwtarchyYaziBreadcrumbTarget)
    then
        for _, segment in ipairs(AwtarchyYaziBreadcrumbSegments(AwtarchyYaziBreadcrumbTarget) or {}) do
            if segment.target ~= cwd and AwtarchyYaziPathIsAncestor(cwd, segment.target) then
                segment.forward = true
                segments[#segments + 1] = segment
            end
        end
    end

    local total = 0
    for _, segment in ipairs(segments) do
        total = total + ui.Line(segment.text):width()
    end
    local clipped = false
    while total > path_width and #segments > 1 do
        total = total - ui.Line(segments[1].text):width()
        table.remove(segments, 1)
        clipped = true
    end

    local x = self._area.x + (clipped and 1 or 0)
    for _, segment in ipairs(segments) do
        local width = ui.Line(segment.text):width()
        if event.x >= x and event.x < x + width and segment.target ~= cwd then
            if not segment.forward and AwtarchyYaziPathIsAncestor(segment.target, cwd) then
                AwtarchyYaziBreadcrumbTarget = AwtarchyYaziBreadcrumbTarget or cwd
            end
            ya.emit("cd", { Url(segment.target), raw = true })
            return
        end
        x = x + width
    end
end

local AwtarchyYaziPendingClick = nil
local AwtarchyYaziDefaultCurrentDrag = Current.drag

function Current:click(event, up)
    local row = event.y - self._area.y + 1
    local file = self._folder.window[row]

    if file then
        return Entity:new(file):click(event, up)
    end

    if not up and event.is_right then
        AwtarchyYaziPendingClick = nil
        AwtarchyYaziContextMenu:show("background", event.x, event.y)
    elseif event.is_left then
        AwtarchyYaziPendingClick = nil
        if up then
            AwtarchyYaziDragState = nil
        else
            AwtarchyYaziContextMenu:hide()
        end
    end
end

function Current:drag(event)
    AwtarchyYaziPendingClick = nil

    if not AwtarchyYaziDragState then
        local source = self._folder.hovered
        if source then
            local sources = AwtarchyYaziDragSources(source)
            if #sources > 0 then
                if not source:is_selected() then
                    ya.emit("toggle_all", { state = "off" })
                    ya.emit("reveal", { source.url })
                end

                AwtarchyYaziContextMenu:hide()
                AwtarchyYaziDragState = { sources = sources }
            end
        end
    end

    return AwtarchyYaziDefaultCurrentDrag(self, event)
end

function Entity:click(event, up)
    if up then
        if event.is_left and AwtarchyYaziDragState then
            local drag = AwtarchyYaziDragState
            AwtarchyYaziDragState = nil
            AwtarchyYaziPendingClick = nil

            if self._file.cha.is_dir
                and AwtarchyYaziCanDropInto(tostring(self._file.url), drag.sources)
            then
                AwtarchyYaziContextMenu:show_drop(
                    self._file.url,
                    drag.sources,
                    event.x,
                    event.y
                )
            end
            return
        end

        if event.is_left and AwtarchyYaziPendingClick then
            local pending = AwtarchyYaziPendingClick
            AwtarchyYaziPendingClick = nil

            if pending.path == tostring(self._file.url) and pending.was_hovered then
                AwtarchyYaziContextMenu:hide()
                if AwtarchyYaziNavigateCollection(self._file, false) then
                    return
                elseif self._file.cha.is_dir then
                    ya.emit("enter", {})
                else
                    AwtarchyYaziOpenFiles(false, true)
                end
            end
        end
        return
    elseif not event.is_left and not event.is_right and not event.is_middle then
        return
    end

    if event.is_middle then
        AwtarchyYaziPendingClick = nil
        AwtarchyYaziContextMenu:hide()
        if AwtarchyYaziNavigateCollection(self._file, true) then
            return
        elseif self._file.cha.is_dir then
            ya.emit("tab_create", { tostring(self._file.url), raw = true })
        end
        return
    end

    local was_hovered = self._file.is_hovered
    local was_selected = self._file:is_selected()
    local selected_count = #cx.active.selected

    if event.is_right then
        AwtarchyYaziPendingClick = nil
        if not was_selected then
            ya.emit("toggle_all", { state = "off" })
            selected_count = 1
        else
            selected_count = math.max(1, selected_count)
        end

        ya.emit("reveal", { self._file.url })
        AwtarchyYaziContextMenu:show("item", event.x, event.y, selected_count, self._file)
        return
    end

    AwtarchyYaziContextMenu:hide()
    AwtarchyYaziPendingClick = {
        path = tostring(self._file.url),
        was_hovered = was_hovered,
    }
    ya.emit("reveal", { self._file.url })
end

AwtarchyYaziTimeFormat = "24h"

ps.sub("@awtarchy-yazi-time-format", function(value)
    if value == "12h" or value == "24h" then
        AwtarchyYaziTimeFormat = value
    end
end)

function AwtarchyYaziToggleTimeFormat()
    local next_format = AwtarchyYaziTimeFormat == "24h" and "12h" or "24h"
    AwtarchyYaziTimeFormat = next_format
    ps.pub("@awtarchy-yazi-time-format", next_format)
    ui.render()
end

function Status:selected_count()
    local count = #cx.active.selected
    if count < 2 then
        return ""
    end

    return string.format(" %d selected ", count)
end

function Status:task_summary()
    local summary = cx.tasks.summary
    if summary.total == 0 then
        return ""
    end

    local active = math.max(0, summary.total - summary.success)
    if summary.failed > 0 then
        return ui.Span(
            string.format(" %d tasks · %d failed ", active, summary.failed)
        ):style(th.status.progress_error)
    end

    return ui.Span(
        string.format(" %d task%s ", active, active == 1 and "" or "s")
    ):style(th.status.progress_label)
end

local AwtarchyYaziDefaultStatusClick = Status.click

function Status:click(event, up)
    if not up and event.is_left and cx.tasks.summary.total > 0 then
        ya.emit("tasks:show", {})
        return
    end
    return AwtarchyYaziDefaultStatusClick(self, event, up)
end

function Status:modified_time()
    local hovered = self._current.hovered
    if not hovered then
        return ""
    end

    local time = math.floor(hovered.cha.mtime or 0)
    if time <= 0 then
        return ""
    end

    local parts = os.date("*t", time)

    if AwtarchyYaziTimeFormat == "12h" then
        local hour = parts.hour % 12
        if hour == 0 then
            hour = 12
        end

        local meridiem = parts.hour < 12 and "AM" or "PM"
        return string.format(
            " Modified: %d/%d/%02d %d:%02d %s ",
            parts.month,
            parts.day,
            parts.year % 100,
            hour,
            parts.min,
            meridiem
        )
    end

    return string.format(
        " Modified: %d/%d/%02d %02d:%02d ",
        parts.month,
        parts.day,
        parts.year % 100,
        parts.hour,
        parts.min
    )
end

Status:children_add(function(self)
    return self:selected_count()
end, 450, Status.RIGHT)

Status:children_add(function(self)
    return self:task_summary()
end, 400, Status.RIGHT)

Status:children_add(function(self)
    return self:modified_time()
end, 500, Status.RIGHT)
