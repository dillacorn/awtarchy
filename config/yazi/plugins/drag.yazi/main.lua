---@param s string
local function fail(s, ...)
    ya.notify({
        title = "ripdrag",
        content = string.format(s, ...),
        timeout = 4,
        level = "error",
    })
end

---@return string[]
local selected_files = ya.sync(function()
    local tab, paths = cx.active, {}

    for _, file in pairs(tab.selected) do
        paths[#paths + 1] = tostring(file.url)
    end

    if #paths == 0 and tab.current.hovered then
        paths[1] = tostring(tab.current.hovered.url)
    end

    return paths
end)

return {
    entry = function()
        local files = selected_files()
        if #files == 0 then
            return
        end

        local child, err = Command("ripdrag")
            :arg({
                "--all-compact",
                "--and-exit",
                "--no-click",
                "--basename",
            })
            :arg(files)
            :spawn()

        if not child then
            fail("Unable to start ripdrag: %s", err or "unknown error")
            return
        end

        local output
        output, err = child:wait_with_output()
        if not output then
            fail("Unable to read ripdrag result: %s", err or "unknown error")
        elseif not output.status.success and output.status.code ~= 131 then
            fail("ripdrag exited with code %s", output.status.code)
        end
    end,
}
