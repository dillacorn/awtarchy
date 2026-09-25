local M = {}

local function decode_arg(value)
    if type(value) ~= "string" then return value end
    local hex = value:match("^hex:([0-9a-fA-F]+)$")
    if not hex or #hex % 2 ~= 0 then return value end
    return (hex:gsub("..", function(byte)
        return string.char(tonumber(byte, 16))
    end))
end

function M:entry(job)
    if job.args[1] ~= "show" then
        return
    end

    local cands = {}
    local i = 2
    while job.args[i] and job.args[i + 1] do
        cands[#cands + 1] = {
            on = decode_arg(job.args[i]),
            desc = decode_arg(job.args[i + 1]),
        }
        i = i + 2
    end

    if #cands == 0 then
        ya.emit("plugin", { "awtarchy-context-run", "--cancel", mode = "sync" })
        return
    end

    local index = ya.which { cands = cands, silent = false }
    local arg = index and ("--index=" .. tostring(index)) or "--cancel"
    ya.emit("plugin", { "awtarchy-context-run", arg, mode = "sync" })
end

return M
