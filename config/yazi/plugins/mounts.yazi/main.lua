local M = {}

local KEYS = {
    "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
    "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
    "u", "v", "w", "x", "y", "z",
}

local function disk_for(src)
    local patterns = {
        "^(/dev/sd[a-z])%d+$",
        "^(/dev/nvme%d+n%d+)p%d+$",
        "^(/dev/mmcblk%d+)p%d+$",
        "^(/dev/md%d+)p%d+$",
        "^(/dev/nbd%d+)p%d+$",
        "^(/dev/bcache%d+)p%d+$",
    }

    for _, pattern in ipairs(patterns) do
        local disk = src:match(pattern)
        if disk then
            return disk
        end
    end
    return src
end

local function obtain()
    local out = {}
    for _, partition in ipairs(fs.partitions()) do
        if partition.src and partition.src ~= "" then
            out[#out + 1] = {
                src = partition.src,
                label = partition.label or "",
                dist = partition.dist or "",
                fstype = partition.fstype or "",
            }
        end
    end
    table.sort(out, function(a, b)
        return a.src < b.src
    end)
    return out
end

local function notify(message, level)
    ya.notify {
        title = "Mounts",
        content = message,
        timeout = 5,
        level = level,
    }
end

local function run_udisks(action, src)
    local output, err = Command("udisksctl")
        :arg({ action, "-b", src })
        :output()

    if not output then
        return notify("Failed to run udisksctl: " .. tostring(err), "error")
    elseif not output.status.success then
        local detail = output.stderr ~= "" and output.stderr or output.stdout
        return notify(detail ~= "" and detail or ("udisksctl " .. action .. " failed"), "error")
    end

    local detail = output.stdout:gsub("%s+$", "")
    notify(detail ~= "" and detail or (action .. " completed"), "info")
end

local function power_off(partition)
    if partition.dist ~= "" then
        local output = Command("udisksctl")
            :arg({ "unmount", "-b", partition.src })
            :output()
        if output and not output.status.success then
            local detail = output.stderr ~= "" and output.stderr or output.stdout
            return notify(detail ~= "" and detail or "Unmount before eject failed", "error")
        end
    end

    run_udisks("power-off", disk_for(partition.src))
end

local function describe(partition)
    local bits = { partition.src }
    if partition.label ~= "" then
        bits[#bits + 1] = partition.label
    end
    if partition.fstype ~= "" then
        bits[#bits + 1] = partition.fstype
    end
    if partition.dist ~= "" then
        bits[#bits + 1] = "mounted: " .. partition.dist
    else
        bits[#bits + 1] = "not mounted"
    end
    return table.concat(bits, " | ")
end

function M:entry()
    if ya.target_os() ~= "linux" then
        return notify("Mount manager is available on Linux only.", "warn")
    end

    while true do
        local partitions = obtain()
        if #partitions == 0 then
            return notify("No mountable block devices found.", "warn")
        end

        local candidates = {}
        for i, partition in ipairs(partitions) do
            if not KEYS[i] then
                break
            end
            candidates[i] = {
                on = KEYS[i],
                desc = describe(partition),
            }
        end

        local choice = ya.which { cands = candidates, silent = false }
        local partition = choice and partitions[choice] or nil
        if not partition then
            return
        end

        local actions = {}
        if partition.dist ~= "" then
            actions[#actions + 1] = { on = "o", desc = "Open mount point" }
            actions[#actions + 1] = { on = "u", desc = "Unmount" }
        else
            actions[#actions + 1] = { on = "m", desc = "Mount" }
        end
        actions[#actions + 1] = { on = "e", desc = "Eject / power off device" }

        local action = ya.which { cands = actions, silent = false }
        if not action then
            return
        end

        local selected = actions[action].on
        if selected == "o" then
            ya.emit("cd", { Url(partition.dist), raw = true })
            return
        elseif selected == "m" then
            run_udisks("mount", partition.src)
        elseif selected == "u" then
            run_udisks("unmount", partition.src)
        elseif selected == "e" then
            power_off(partition)
        end
    end
end

return M
