-- Behavioral test against the actual Quick Mark code in the managed init.lua.
local path = "config/yazi/init.lua"
local f = assert(io.open(path, "rb"))
local source = assert(f:read("*a"))
f:close()
local begin_at = assert(source:find("-- Quick Mark is deliberately", 1, true))
local end_at = assert(source:find("local AwtarchyYaziDefaultEntityHighlights", begin_at, true))
local script = assert(load(source:sub(begin_at, end_at - 1), "=awtarchy-quick-mark", "t", _G))

local notifications = {}
local cd_count = 0
local tab_one = { id = { value = 11 }, current = { cwd = "/unit/alpha" } }
local tab_two = { id = { value = 12 }, current = { cwd = "/unit/gamma" } }
cx = { active = tab_one }
Url = function(value) return value end
ya = {
    notify = function(value) notifications[#notifications + 1] = value end,
    emit = function(name, args)
        assert(name == "cd", "Quick Mark must use native Yazi cd")
        assert(args.raw == true and type(args[1]) == "string")
        cd_count = cd_count + 1
        cx.active.current.cwd = args[1]
    end,
}
script()

AwtarchyYaziSetQuickMark()
cx.active.current.cwd = "/unit/beta"
AwtarchyYaziGoQuickMark()
assert(cx.active.current.cwd == "/unit/alpha", "g q must jump directly to Quick Mark")
AwtarchyYaziToggleQuickMark()
assert(cx.active.current.cwd == "/unit/beta", "Q must return tab one to previous directory")

cx.active = tab_two
AwtarchyYaziToggleQuickMark()
assert(cx.active.current.cwd == "/unit/alpha", "Q must navigate tab two to Quick Mark")
AwtarchyYaziToggleQuickMark()
assert(cx.active.current.cwd == "/unit/gamma", "Q must return tab two independently")
cx.active = tab_one
AwtarchyYaziToggleQuickMark()
assert(cx.active.current.cwd == "/unit/alpha", "tab one returns must retain their own state")
AwtarchyYaziToggleQuickMark()
assert(cx.active.current.cwd == "/unit/beta", "tab one original return path must remain intact")

local before = cd_count
-- Simulates a new Yazi process with freshly initialized local state.
script()
AwtarchyYaziToggleQuickMark()
assert(cd_count == before, "new Yazi process cannot restore a session-only Quick Mark")
assert(#notifications > 0, "unmarked Quick Mark must notify the user")
print("Yazi session-only Quick Mark behavioral smoke test passed")
