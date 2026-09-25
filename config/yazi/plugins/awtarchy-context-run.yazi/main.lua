--- @sync entry

return {
    entry = function(_, job)
        if not AwtarchyYaziContextMenu or type(AwtarchyYaziContextMenu.choose) ~= "function" then
            ya.notify {
                title = "Yazi",
                content = "Awtarchy context action runner is unavailable.",
                timeout = 3,
                level = "error",
            }
            return
        end

        if job.args.cancel then
            AwtarchyYaziContextMenu:choose(nil)
            return
        end

        AwtarchyYaziContextMenu:choose(tonumber(job.args.index))
    end,
}
