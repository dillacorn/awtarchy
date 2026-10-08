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
    if AwtarchyYaziContextMenu and AwtarchyYaziContextMenu._visible
        and AwtarchyYaziContextMenu._kind == "drop"
    then
        AwtarchyYaziContextMenu:choose()
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

-- Shift+Up/Down previews a contiguous range without selecting anything.
-- Space commits it through Yazi's native visual-selection engine; Esc cancels.
-- Shift+Up/Down is a reversible preview; only Space commits selection.
-- Use the documented tab index and ipairs(fs::Files), not an undocumented
-- tab id or guessed indices into Yazi's file-list userdata.
local AwtarchyYaziRangePreview = nil

local function AwtarchyYaziRangeValid()
    local range = AwtarchyYaziRangePreview
    if not range then return false end

    local folder = cx.active.current
    return cx.active.mode.is_normal
        and range.tab == cx.tabs.idx
        and range.cwd == tostring(folder.cwd)
        and range.count == #folder.files
end

local function AwtarchyYaziRangeDiscard()
    if not AwtarchyYaziRangePreview then return false end
    AwtarchyYaziRangePreview = nil
    ui.render()
    return true
end

-- Yazi's file list is a Lua userdata supporting ipairs. Materialize the
-- ordered URLs once per Shift keypress so all indices are Lua 1-based.
local function AwtarchyYaziRangeFiles(folder)
    local files = {}
    for _, file in ipairs(folder.files) do
        files[#files + 1] = tostring(file.url)
    end
    return files
end

local function AwtarchyYaziRangeFind(files, url)
    for i, path in ipairs(files) do
        if path == url then return i end
    end
    return nil
end

local function AwtarchyYaziRangeRebuild(range, files)
    range.paths = {}
    for i = math.min(range.anchor, range.last), math.max(range.anchor, range.last) do
        range.paths[files[i]] = true
    end
end

function AwtarchyYaziShiftArrow(step)
    if not cx.active.mode.is_normal then
        ya.emit("arrow", { step })
        return
    end

    local folder = cx.active.current
    local hovered = folder.hovered
    if not hovered or #folder.files == 0 then
        AwtarchyYaziRangeDiscard()
        return
    end

    local files = AwtarchyYaziRangeFiles(folder)
    local hovered_url = tostring(hovered.url)
    local current = AwtarchyYaziRangeFind(files, hovered_url)
    if not current then
        AwtarchyYaziRangeDiscard()
        return
    end

    local range = AwtarchyYaziRangePreview
    if not AwtarchyYaziRangeValid() or not range or range.last_url ~= hovered_url
        or files[range.anchor] ~= range.anchor_url
        or files[range.last] ~= range.last_url
    then
        range = {
            tab = cx.tabs.idx,
            cwd = tostring(folder.cwd),
            count = #files,
            anchor = current,
            anchor_url = hovered_url,
            last = current,
            last_url = hovered_url,
        }
        AwtarchyYaziRangePreview = range
    end

    local target = math.max(1, math.min(#files, current + step))
    if target == current then
        if not range.paths then
            AwtarchyYaziRangeRebuild(range, files)
            ui.render()
        end
        return
    end

    range.last = target
    range.last_url = files[target]
    AwtarchyYaziRangeRebuild(range, files)
    ya.emit("arrow", { step })
    ui.render()
end

function AwtarchyYaziSpace()
    if AwtarchyYaziRangeValid() then
        local range = AwtarchyYaziRangePreview
        local hovered = cx.active.current.hovered
        local files = AwtarchyYaziRangeFiles(cx.active.current)
        if hovered and tostring(hovered.url) == range.last_url
            and files[range.anchor] == range.anchor_url
            and files[range.last] == range.last_url
        then
            -- Preview never changed the selected set. Commit with Yazi's
            -- own visual mode only when Space is actually pressed.
            AwtarchyYaziRangePreview = nil
            ya.emit("reveal", { Url(range.anchor_url) })
            ya.emit("visual_mode", {})
            ya.emit("arrow", { range.last - range.anchor })
            ya.emit("escape", { visual = true })
            ya.emit("reveal", { Url(range.last_url) })
            ui.render()
            return
        end
    end

    AwtarchyYaziRangeDiscard()
    ya.emit("toggle", {})
end

function AwtarchyYaziArrow(step)
    if AwtarchyYaziDeleteMenu and AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:move(step)
        return
    end
    if AwtarchyYaziContextMenu and AwtarchyYaziContextMenu._visible
        and AwtarchyYaziContextMenu._kind == "drop"
    then
        AwtarchyYaziContextMenu:move_keyboard(step)
        return
    end

    AwtarchyYaziRangeDiscard()
    local direction = step < 0 and "prev" or "next"
    ya.emit("arrow", { direction })
end

local AwtarchyYaziDefaultEntityStyle = Entity.style
function Entity:style()
    local style = AwtarchyYaziDefaultEntityStyle(self)
    local range = AwtarchyYaziRangePreview
    if self._file.in_current and range and AwtarchyYaziRangeValid()
        and range.paths and range.paths[tostring(self._file.url)]
    then
        return style:patch(ui.Style():reverse():underline())
    end
    return style
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

local AwtarchyYaziTabDrag = nil

local function AwtarchyYaziTabIndexAtX(tabs, x)
    for i = #cx.tabs, 1, -1 do
        local offset = tabs._offsets[i]
        if offset and x >= offset then
            return i
        end
    end
    return nil
end

local function AwtarchyYaziFinishTabDrag()
    local drag = AwtarchyYaziTabDrag
    AwtarchyYaziTabDrag = nil
    if drag and drag.moved then
        ui.render()
    end
end

local AwtarchyYaziDefaultTabsStyle = Tabs.style

function Tabs:style()
    local styles = AwtarchyYaziDefaultTabsStyle(self)
    if AwtarchyYaziTabDrag and AwtarchyYaziTabDrag.moved then
        -- A single terminal row cannot lift a tab physically; emphasize the dragged block.
        styles.active = styles.active:patch(ui.Style():bold():underline():reverse())
    end
    return styles
end

local function AwtarchyYaziMoveActiveTabTo(current, target)
    if not current or not target or current == target then
        return
    end

    local step = target > current and 1 or -1
    for _ = 1, math.abs(target - current) do
        ya.emit("tab_swap", { step })
    end
end

function Tabs:click(event, up)
    local index = AwtarchyYaziTabIndexAtX(self, event.x)
    if not index then
        AwtarchyYaziFinishTabDrag()
        return
    end

    if event.is_right then
        if up then
            return
        end
        AwtarchyYaziFinishTabDrag()
        ya.emit("tab_switch", { index - 1 })
        ya.emit("tab_rename", { interactive = true })
        return
    elseif not event.is_left then
        return
    end

    if not up then
        AwtarchyYaziTabDrag = {
            target = index,
            last_x = event.x,
            moved = false,
        }
        ya.emit("tab_switch", { index - 1 })
        return
    end

    AwtarchyYaziFinishTabDrag()
end

local function AwtarchyYaziTabMidpoint(tabs, index)
    local first = tabs._offsets[index]
    if not first then return nil end
    local next_offset = tabs._offsets[index + 1]
    -- The last tab ends at its rendered label, not at the terminal edge.
    -- Using the whole remaining tab-bar width makes the rightmost slot
    -- unreachable when there is unused space to the right of the tabs.
    local last = next_offset
    if not last then
        local max = math.floor(tabs:inner_width() / #cx.tabs)
        local name = ui.truncate(
            string.format(" %d %s ", index, cx.tabs[index].name),
            { max = max }
        )
        last = first + ui.width(name)
    end
    return math.floor((first + last) / 2)
end

function Tabs:drag(event)
    local drag = AwtarchyYaziTabDrag
    if not drag or not event.x then return end

    if not drag.moved then
        drag.moved = true
        ui.render()
    end

    -- Swap only after crossing the adjacent tab's midpoint, rather than
    -- reacting to its moving edge. Require mouse travel after a swap too,
    -- preventing a reflow at a stationary cursor from ping-ponging tabs.
    if drag.last_swap_x and math.abs(event.x - drag.last_swap_x) < 3 then
        return
    end

    local target = drag.target
    local margin = 1
    if event.x > (drag.last_x or event.x) then
        while target < #cx.tabs do
            local midpoint = AwtarchyYaziTabMidpoint(self, target + 1)
            if not midpoint or event.x < midpoint + margin then break end
            target = target + 1
        end
    elseif event.x < (drag.last_x or event.x) then
        while target > 1 do
            local midpoint = AwtarchyYaziTabMidpoint(self, target - 1)
            if not midpoint or event.x > midpoint - margin then break end
            target = target - 1
        end
    end

    drag.last_x = event.x
    if target ~= drag.target then
        AwtarchyYaziMoveActiveTabTo(drag.target, target)
        drag.target = target
        drag.last_swap_x = event.x
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

local function AwtarchyYaziTextFile(file)
    if not file or file.cha.is_dir then return nil end

    local mime = file:mime() or ""
    if mime:match("^text/")
        or mime == "application/json"
        or mime == "application/xml"
        or mime == "application/javascript"
        or mime == "application/x-javascript"
        or mime == "application/x-shellscript"
    then
        return file
    end

    local name = tostring(file.url.name or ""):lower()
    if AwtarchyYaziTextNames[name] then return file end

    local ext = name:match("%.([^%.]+)$")
    if ext and AwtarchyYaziTextExtensions[ext] then return file end
    return nil
end

local function AwtarchyYaziHoveredTextFile()
    return AwtarchyYaziTextFile(cx.active.current.hovered)
end

local function AwtarchyYaziPreviewTextSelectable()
    return AwtarchyYaziPreviewMaximized and AwtarchyYaziHoveredTextFile() ~= nil
end

local function AwtarchyYaziShellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Export the snapped preview item as a Wayland file URI, or its text
-- contents as plain text. This intentionally does not change Yazi's own
-- selected/yanked state. wl-copy is already an Awtarchy requirement.
local function AwtarchyYaziPreviewClipboard(path, as_text)
    ya.async(function()
        local command, argv
        if as_text then
            command = 'test -f "$1" && [ "$(wc -c < "$1")" -le 8388608 ] && wl-copy -t text/plain < "$1"'
            argv = { "-c", command, "awtarchy-yazi-preview", path }
        else
            local encoded = path:gsub("[^A-Za-z0-9%-%._~/]", function(byte)
                return string.format("%%%02X", byte:byte())
            end)
            command = 'test -e "$1" && printf "%s\\r\\n" "$2" | wl-copy -t text/uri-list'
            argv = { "-c", command, "awtarchy-yazi-preview", path, "file://" .. encoded }
        end

        local result, err = Command("sh"):arg(argv):output()
        if err or not result or not result.status.success then
            ya.notify {
                title = "Preview clipboard",
                content = "Could not copy preview item. Check file access and wl-copy.",
                timeout = 5,
                level = "error",
            }
            return
        end

        ya.notify {
            title = "Preview clipboard",
            content = as_text and "Copied preview text contents"
                or "Copied preview item as a Wayland file URI",
            timeout = 2,
        }
    end)
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
        "printf '\n\nSelect text with the mouse, copy with Ctrl+Shift+C, then press Enter or Esc to return to Yazi...'; " ..
        "awtarchy_stty=$(stty -g) || exit 1; " ..
        "trap 'stty \"$awtarchy_stty\"' EXIT HUP INT TERM; " ..
        "stty -echo -icanon min 1 time 0; " ..
        "while :; do " ..
        "key=$(dd bs=1 count=1 2>/dev/null); " ..
        "[ -z \"$key\" ] && break; " ..
        "[ \"$key\" = \"$(printf '\\033')\" ] && break; " ..
        "done; " ..
        "stty \"$awtarchy_stty\"; " ..
        "trap - EXIT HUP INT TERM"

    ya.emit("shell", { run = command, block = true })
end

-- Shared gesture state must be in scope for Esc as well as pane mouse events.
local AwtarchyYaziDragState = nil
local AwtarchyYaziDragPending = nil
local AwtarchyYaziPendingClick = nil

function AwtarchyYaziEscape()
    -- Keyboard cancellation must erase the ghost and never start a file task.
    if AwtarchyYaziDragState or AwtarchyYaziDragPending then
        AwtarchyYaziDragState = nil
        AwtarchyYaziDragPending = nil
        AwtarchyYaziPendingClick = nil
        ui.render()
        return
    end

    if AwtarchyYaziDeleteMenu and AwtarchyYaziDeleteMenu._visible then
        AwtarchyYaziDeleteMenu:hide()
        return
    end

    -- Close Copy/Move (or other context) actions without changing selection.
    if AwtarchyYaziContextMenu and AwtarchyYaziContextMenu._visible then
        AwtarchyYaziContextMenu:hide()
        return
    end

    -- Esc discards a Shift+arrow preview. Native selected files stay selected.
    if AwtarchyYaziRangeDiscard() then return end

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

-- Preview right-click never calls Entity:click, which would mutate selection
-- and reveal a potentially different manager item. The menu snapshots a path.
local AwtarchyYaziDefaultPreviewClick = Preview.click
function Preview:click(event, up)
    if event.is_left and AwtarchyYaziContextMenu._visible then
        -- Mouse1 on preview outside menu dismisses without navigation.
        if not up then AwtarchyYaziContextMenu:hide() end
        return
    end
    if not event.is_right then
        return AwtarchyYaziDefaultPreviewClick(self, event, up)
    end
    if up then return end

    AwtarchyYaziRangeDiscard()
    local hovered = cx.active.current.hovered
    if not hovered then return end

    local target = hovered
    if hovered.cha.is_dir and self._folder
        and tostring(self._folder.cwd) == tostring(hovered.url)
    then
        local row = event.y - self._area.y + 1
        if row >= 1 and self._folder.window[row] then
            target = self._folder.window[row]
        end
    end

    AwtarchyYaziContextMenu:show_preview(target, event.x, event.y)
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
local AwtarchyYaziDefaultParentRedraw = Parent.redraw
-- Defined below, after the mouse drag state. Keep native pane rendering.
local AwtarchyYaziDragGhostRedraw = function() return {}, {} end

function Parent:redraw()
    local cleanup, ghost = AwtarchyYaziDragGhostRedraw(self._area, "parent")
    local elements = ya.list_merge(cleanup, AwtarchyYaziDefaultParentRedraw(self) or {})
    return ya.list_merge(elements, ghost)
end

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
    -- Drop a preview whenever tab, directory, sort order, or mode changed.
    if AwtarchyYaziRangePreview and not AwtarchyYaziRangeValid() then
        AwtarchyYaziRangePreview = nil
    end
    local cleanup, ghost = AwtarchyYaziDragGhostRedraw(self._area, "current")
    local elements = ya.list_merge(cleanup, AwtarchyYaziDefaultCurrentRedraw(self) or {})
    if self._awtarchy_preview_toggle_button then
        elements = ya.list_merge(elements, ui.redraw(self._awtarchy_preview_toggle_button))
    end
    return ya.list_merge(elements, ghost)
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
    { label = "Open", action = "smart_open" },
    { label = "Open with...", action = "open_with" },
    { label = "Bookmark / unbookmark", action = "bookmark_hovered" },
    { label = "Rename", action = "rename" },
    { label = "Drag out...", action = "drag_out" },
    { label = "Copy", action = "copy" },
    { label = "Cut", action = "cut" },
    { label = "Copy path", action = "copy_path" },
    { label = "Compress to ZIP...", action = "compress_zip" },
    { label = "Details", action = "details" },
    { label = "Trash", action = "trash" },
}

-- Terminal-native ghost, clipped to the pane under the pointer.
-- Clear its previous rectangle *before* native rows redraw so a ghost
-- never remains painted on the list after release, Esc, or leaving the pane.
local AwtarchyYaziDragGhostPrevious = {}
AwtarchyYaziDragGhostRedraw = function(area, pane)
    local cleanup = {}
    local previous = AwtarchyYaziDragGhostPrevious[pane]
    if previous then cleanup[1] = ui.Clear(previous) end
    AwtarchyYaziDragGhostPrevious[pane] = nil

    local drag = AwtarchyYaziDragState
    if not drag or not drag.x or not drag.y or area.w < 8 or area.h < 2
        or drag.x < area.x or drag.x >= area.x + area.w
        or drag.y < area.y or drag.y >= area.y + area.h
    then
        return cleanup, {}
    end

    local count = #drag.sources
    if count == 0 then return cleanup, {} end

    local label = count == 1
        and (" " .. tostring(drag.sources[1].name or "item") .. " ")
        or string.format(" %d items ", count)
    local line = ui.truncate(ui.printable(label), { max = math.min(36, area.w) })
    local width = ui.width(line)
    if width < 1 then return cleanup, {} end

    local x = math.max(area.x, math.min(drag.x + 2, area.x + area.w - width))
    local y = drag.y + 1 < area.y + area.h and drag.y + 1 or drag.y - 1
    y = math.max(area.y, math.min(y, area.y + area.h - 1))
    local rect = ui.Rect { x = x, y = y, w = width, h = 1 }
    AwtarchyYaziDragGhostPrevious[pane] = rect

    return cleanup, {
        ui.Text(ui.Line(line):style(ui.Style():fg("gray"):bg("darkgray")))
            :area(rect),
    }
end

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
        local source_url = Url(source.path)
        -- Moving or copying an item into its existing folder is a no-op
        -- (or a same-path collision); do not offer it as a drop destination.
        if AwtarchyYaziNormalizeFsPath(target_url) == AwtarchyYaziNormalizeFsPath(source_url.parent)
            or (source.is_dir and target_url:starts_with(source_url))
        then
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

function AwtarchyYaziDragOut()
    -- Outbound drag stays explicit and handled by Awtarchy's vendored
    -- drag.yazi/ripdrag workflow, not by the internal folder-drop gesture.
    ya.emit("plugin", { "drag" })
end

local AwtarchyYaziFolderActions = {
    { label = "New file", action = "new_file" },
    { label = "New folder", action = "new_folder" },
    { label = "Paste", action = "paste" },
    { label = "Terminal here", action = "terminal" },
    { label = "Bookmark / unbookmark folder", action = "bookmark_current" },
}

local function AwtarchyYaziContextActions(actions)
    local result = {}
    for _, action in ipairs(actions) do
        result[#result + 1] = action
    end
    result[#result + 1] = { label = "Copy current directory path", action = "copy_dirpath" }
    result[#result + 1] = { label = "Open PCManFM-Qt here", action = "file_manager_here" }
    result[#result + 1] = { label = "Help", action = "help" }
    return result
end

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
    _preview_target = nil,
    _preview_is_text = false,
    _preview_is_dir = false,
    _preview_details = nil,
}

function AwtarchyYaziContextMenu:show(kind, x, y, selection_count)
    if kind ~= "preview" then
        self._preview_target = nil
        self._preview_is_text = false
        self._preview_is_dir = false
        self._preview_details = nil
    end
    self._kind = kind
    self._x = x
    self._y = y
    self._selection_count = selection_count or 0
    -- Copy is highlighted by default, but no action executes until a click,
    -- Enter, or the explicit copy/move mnemonic.
    self._hovered_row = kind == "drop" and 1 or nil
    self._visible = true
    ui.render()
end

function AwtarchyYaziContextMenu:show_drop(target, sources, x, y)
    self._drop_target = tostring(target)
    self._drop_sources = sources
    self:show("drop", x, y, #sources)
end

function AwtarchyYaziContextMenu:show_preview(file, x, y)
    if not file or not file.url or AwtarchyYaziIsCollectionItemUrl(file.url)
        or AwtarchyYaziCollectionKind(file.url)
    then
        return
    end

    local path = tostring(file.url)
    -- This menu operates only on real filesystem paths, never virtual URLs.
    if path == "" or path:find("://", 1, true) then return end
    self._preview_target = path
    self._preview_is_dir = file.cha.is_dir
    self._preview_is_text = AwtarchyYaziTextFile(file) ~= nil
    local modified = math.floor(file.cha.mtime or 0)
    local size = file:size()
    self._preview_details = table.concat({
        "Name: " .. tostring(file.url.name or ""),
        "Type: " .. (file.cha.is_dir and "Folder" or "File"),
        "Path: " .. path,
        "Size: " .. (size and ya.readable_size(size) or "Unknown"),
        "Modified: " .. (modified > 0 and os.date("%Y-%m-%d %H:%M", modified) or "Unknown"),
    }, "\n")
    self:show("preview", x, y, 0)
end

function AwtarchyYaziContextMenu:hide()
    if not self._visible then
        return
    end

    self._visible = false
    self._hovered_row = nil
    self._drop_target = nil
    self._drop_sources = nil
    self._preview_target = nil
    self._preview_is_text = false
    self._preview_is_dir = false
    self._preview_details = nil
    ui.render()
end

function AwtarchyYaziContextMenu:title()
    if self._kind == "preview" then
        return " Preview actions "
    elseif self._kind == "background" then
        return " Folder actions "
    elseif self._kind == "drop" then
        return " Copy / move "
    elseif self._selection_count > 1 then
        return " " .. tostring(self._selection_count) .. " selected "
    end

    return " Item actions "
end

function AwtarchyYaziContextMenu:actions()
    if self._kind == "preview" then
        local actions = {}
        if self._preview_is_text then
            actions[#actions + 1] = { label = "Open in Micro", action = "preview_micro" }
            actions[#actions + 1] = { label = "Copy text contents", action = "preview_copy_text" }
        end
        actions[#actions + 1] = {
            label = self._preview_is_dir and "Copy folder to clipboard"
                or "Copy file to clipboard",
            action = "preview_copy_file",
        }
        actions[#actions + 1] = { label = "Copy path", action = "preview_copy_path" }
        actions[#actions + 1] = { label = "Open containing folder in PCManFM-Qt", action = "preview_explorer" }
        actions[#actions + 1] = { label = "Details", action = "preview_details" }
        return actions
    elseif self._kind == "background" then
        return AwtarchyYaziContextActions(AwtarchyYaziFolderActions)
    elseif self._kind == "drop" then
        local url = self._drop_target and Url(self._drop_target) or nil
        local folder = url and tostring(url.name or url) or "folder"
        local label = ui.truncate(ui.printable(folder), { max = 30 })
        return {
            { label = "Copy to " .. label, action = "drop_copy" },
            { label = "Move to " .. label, action = "drop_move" },
        }
    end

    local hovered = cx.active.current.hovered
    if self._selection_count > 1 then
        return AwtarchyYaziContextActions {
            {
                label = "Rename " .. tostring(self._selection_count) .. " items...",
                action = "bulk_rename",
            },
            { label = "Drag out...", action = "drag_out" },
            { label = "Copy", action = "copy" },
            { label = "Cut", action = "cut" },
            { label = "Compress to ZIP...", action = "compress_zip" },
            { label = "Trash " .. tostring(self._selection_count) .. " items", action = "trash" },
        }
    end

    if hovered and hovered.cha.is_dir then
        return AwtarchyYaziContextActions {
            { label = "Enter folder", action = "smart_open" },
            { label = "Open in new tab", action = "open_new_tab" },
            {
                label = "Bookmark / unbookmark",
                action = "bookmark_hovered",
            },
            { label = "Rename", action = "rename" },
            { label = "Drag out...", action = "drag_out" },
            { label = "Copy", action = "copy" },
            { label = "Cut", action = "cut" },
            { label = "Copy path", action = "copy_path" },
            { label = "Compress to ZIP...", action = "compress_zip" },
            { label = "Details", action = "details" },
            { label = "Trash", action = "trash" },
        }
    end

    local actions = {}
    for _, action in ipairs(AwtarchyYaziFileActions) do
        actions[#actions + 1] = action
    end

    if hovered and hovered.name:lower():sub(-4) == ".zip" then
        actions[#actions + 1] = { label = "Extract here", action = "extract_here" }
        actions[#actions + 1] = { label = "Extract to folder", action = "extract_folder" }
    end

    return AwtarchyYaziContextActions(actions)
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
    local height = math.min(#actions + 2, area.h)

    if width < 28 or height < #actions + 2 then
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
    for i, action in ipairs(self:actions()) do
        local row = ui.Line(" " .. action.label .. " "):style(th.help.action)
        if i == self._hovered_row then
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
            :title(ui.Line(self:title()):align(ui.Align.CENTER)),
        ui.List(rows):area(self._list_area),
    }
end

function AwtarchyYaziContextMenu:run(action)
    local count = self._selection_count > 0 and self._selection_count or 1
    local drop_target = self._drop_target
    local drop_sources = self._drop_sources
    local preview_target = self._preview_target
    local preview_is_text = self._preview_is_text
    local preview_details = self._preview_details
    local preview_is_dir = self._preview_is_dir
    self._visible = false
    self._hovered_row = nil
    self._drop_target = nil
    self._drop_sources = nil
    self._preview_target = nil
    self._preview_is_text = false
    self._preview_is_dir = false
    self._preview_details = nil
    ui.render()

    if action == "preview_copy_file" and preview_target then
        AwtarchyYaziPreviewClipboard(preview_target, false)
    elseif action == "preview_copy_text" and preview_target and preview_is_text then
        AwtarchyYaziPreviewClipboard(preview_target, true)
    elseif action == "preview_details" and preview_target and preview_details then
        ya.notify {
            title = "Preview item details",
            content = preview_details,
            timeout = 12,
        }
    elseif action == "preview_copy_path" and preview_target then
        ya.async(function()
            ya.clipboard(preview_target)
            ya.notify {
                title = "Clipboard",
                content = "Copied preview item path",
                timeout = 2,
            }
        end)
    elseif action == "preview_micro" and preview_target and preview_is_text then
        ya.emit("shell", {
            run = "micro " .. AwtarchyYaziShellQuote(preview_target),
            block = true,
        })
    elseif action == "preview_explorer" and preview_target then
        -- pcmanfm-qt has no documented --select switch. Open the exact
        -- containing directory (or the target directory) without claiming
        -- to select the item in PCManFM-Qt.
        local directory = preview_is_dir and preview_target
            or tostring(Url(preview_target).parent)
        ya.emit("shell", {
            run = "pcmanfm-qt " .. AwtarchyYaziShellQuote(directory),
            orphan = true,
        })
    elseif action == "smart_open" then
        AwtarchyYaziSmartEnter()
    elseif action == "open_new_tab" then
        AwtarchyYaziOpenHoveredTab()
    elseif action == "open_with" then
        AwtarchyYaziOpenFiles(true, true)
    elseif action == "rename" then
        ya.emit("rename", { hovered = true })
    elseif action == "bulk_rename" then
        ya.emit("rename", {})
    elseif action == "drag_out" then
        AwtarchyYaziDragOut()
    elseif action == "bookmark_hovered" then
        local hovered = cx.active.current.hovered
        if hovered then
            AwtarchyYaziBookmarkTarget(tostring(hovered.url), hovered.cha.is_dir)
        end
    elseif action == "bookmark_current" then
        AwtarchyYaziBookmarkTarget(tostring(cx.active.current.cwd), true)
    elseif action == "copy_dirpath" then
        -- Snapshot the exact current directory, not selected files' parents.
        local cwd = tostring(cx.active.current.cwd)
        ya.async(function()
            ya.clipboard(cwd)
            ya.notify {
                title = "Clipboard",
                content = "Copied current directory path",
                timeout = 2,
            }
        end)
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
    elseif action == "file_manager_here" then
        ya.emit("shell", { "pcmanfm-qt .", orphan = true })
    elseif action == "help" then
        ya.emit("help", {})
    elseif action == "drop_copy" then
        AwtarchyYaziDropInto("copy", drop_target, drop_sources)
    elseif action == "drop_move" then
        AwtarchyYaziDropInto("move", drop_target, drop_sources)
    end
end

function AwtarchyYaziContextMenu:move_keyboard(step)
    if not self._visible or self._kind ~= "drop" then return end
    local total = #self:actions()
    self._hovered_row = ((self._hovered_row or 1) - 1 + step) % total + 1
    ui.render()
end

function AwtarchyYaziContextMenu:choose()
    if not self._visible or self._kind ~= "drop" then return end
    local actions = self:actions()
    local selected = actions[self._hovered_row or 1]
    if selected then self:run(selected.action) end
end

function AwtarchyYaziDropToParent()
    local target = cx.active.current.cwd.parent
    if not target then return end

    local sources = {}
    if #cx.active.selected > 0 then
        for _, file in pairs(cx.active.selected) do
            sources[#sources + 1] = {
                path = tostring(file.path),
                name = file.name,
                is_dir = file.cha.is_dir,
            }
        end
    elseif cx.active.current.hovered then
        sources = AwtarchyYaziDragSources(cx.active.current.hovered)
    end

    if #sources == 0 or not AwtarchyYaziCanDropInto(tostring(target), sources) then
        ya.notify {
            title = "Yazi",
            content = "No files can be sent to the parent folder from here.",
            level = "warn",
            timeout = 3,
        }
        return
    end

    local area = AwtarchyYaziContextMenu._screen
    local x = area and area.x + math.floor(area.w / 2) or 0
    local y = area and area.y + math.floor(area.h / 2) or 0
    AwtarchyYaziContextMenu:show_drop(target, sources, x, y)
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
local AwtarchyYaziDefaultRootScroll = Root.scroll

function Root:move(event)
    -- Ordinary mouse movement follows release; in-progress Mouse1 holds use
    -- drag events. Clear a released ghost even if it ended outside Current.
    if AwtarchyYaziDragState then
        AwtarchyYaziDragState = nil
        AwtarchyYaziDragPending = nil
        ui.render()
    end
    if AwtarchyYaziTabDrag then
        AwtarchyYaziFinishTabDrag()
    end
    if AwtarchyYaziContextMenu._visible then
        return AwtarchyYaziContextMenu:move(event)
    end
    return AwtarchyYaziDefaultRootMove(self, event)
end

function Root:scroll(event, step)
    if tostring(cx.layer) == "help" then
        ya.emit("help:arrow", { step })
        return
    end
    return AwtarchyYaziDefaultRootScroll(self, event, step)
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

local function AwtarchyYaziApplyFolderSort()
    local cwd = tostring(cx.active.current.cwd)
    local home = os.getenv("HOME")

    if home and cwd == home .. "/Downloads" then
        ya.emit("sort", { "mtime", reverse = true, dir_first = true })
    else
        ya.emit("sort", { "natural", reverse = false, dir_first = true })
    end
end

ps.sub("cd", function()
    AwtarchyYaziApplyFolderSort()

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

local AwtarchyYaziDefaultCurrentDrag = Current.drag
local AwtarchyYaziDefaultParentClick = Parent.click

local function AwtarchyYaziParentDropTarget(parent, event)
    -- The left pane lists the parent directory. Releasing over a file
    -- targets its containing parent directory, never the file itself.
    -- A folder row remains an explicit folder destination.
    local row = event.y - parent._area.y + 1
    local folder = parent._folder
    local file = folder and folder.window[row] or nil
    if file then
        if AwtarchyYaziIsCollectionItemUrl(file.url) then return nil end
        return file.cha.is_dir and file.url or file.url.parent
    end
    return cx.active.current.cwd.parent
end

function Parent:click(event, up)
    if up and event.is_left and AwtarchyYaziDragState then
        local drag = AwtarchyYaziDragState
        AwtarchyYaziDragState = nil
        AwtarchyYaziDragPending = nil
        AwtarchyYaziPendingClick = nil

        local target = AwtarchyYaziParentDropTarget(self, event)
        if target and AwtarchyYaziCanDropInto(tostring(target), drag.sources) then
            AwtarchyYaziContextMenu:show_drop(target, drag.sources, event.x, event.y)
        else
            ui.render()
        end
        return
    end

    return AwtarchyYaziDefaultParentClick(self, event, up)
end

function Current:click(event, up)
    if not up and (event.is_left or event.is_right) then
        AwtarchyYaziRangeDiscard()
    end
    local row = event.y - self._area.y + 1
    local file = self._folder.window[row]

    if file then
        return Entity:new(file):click(event, up)
    end

    if not up and event.is_right then
        AwtarchyYaziDragPending = nil
        AwtarchyYaziPendingClick = nil
        AwtarchyYaziContextMenu:show("background", event.x, event.y)
    elseif event.is_left then
        AwtarchyYaziDragPending = nil
        AwtarchyYaziPendingClick = nil
        if up then
            local was_dragging = AwtarchyYaziDragState ~= nil
            AwtarchyYaziDragState = nil
            if was_dragging then ui.render() end
        else
            AwtarchyYaziContextMenu:hide()
        end
    end
end

function Current:drag(event)
    AwtarchyYaziPendingClick = nil

    -- Use the file(s) captured at Mouse1 down, never the hovered destination.
    -- Mouse gestures have coordinates; OSC 72 offers do not trigger this UI.
    if event.x and event.y then
        if not AwtarchyYaziDragState and AwtarchyYaziDragPending then
            AwtarchyYaziContextMenu:hide()
            AwtarchyYaziDragState = { sources = AwtarchyYaziDragPending.sources }
            AwtarchyYaziDragPending = nil
        end

        if AwtarchyYaziDragState
            and (AwtarchyYaziDragState.x ~= event.x or AwtarchyYaziDragState.y ~= event.y)
        then
            AwtarchyYaziDragState.x = event.x
            AwtarchyYaziDragState.y = event.y
            ui.render()
        end
    end

    return AwtarchyYaziDefaultCurrentDrag(self, event)
end

function Entity:click(event, up)
    if not up then AwtarchyYaziRangeDiscard() end
    if up then
        AwtarchyYaziDragPending = nil
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
            else
                -- Invalid release cancels; clear the ghost without a file operation.
                ui.render()
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
        AwtarchyYaziDragPending = nil
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
        AwtarchyYaziDragPending = nil
        AwtarchyYaziPendingClick = nil
        if not was_selected then
            ya.emit("toggle_all", { state = "off" })
            selected_count = 1
        else
            selected_count = math.max(1, selected_count)
        end

        ya.emit("reveal", { self._file.url })
        AwtarchyYaziContextMenu:show("item", event.x, event.y, selected_count)
        return
    end

    AwtarchyYaziContextMenu:hide()
    -- An unselected file drags alone; a selected item drags the selected group.
    -- No Space press is needed for a single file. Nothing moves until menu choice.
    AwtarchyYaziDragPending = { sources = AwtarchyYaziDragSources(self._file) }
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
