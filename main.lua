local lua = require("lua.main")

-- Custom environment
local env = {
    print = print,
    getmetatable = getmetatable,
    setmetatable = setmetatable,
    type = type,
    pcall = function(f, ...)
        local data = {pcall(f, ...)}
        if not data[1] then
            return false, data[2].error_object
        else
            return unpack(data)
        end
    end,
    error = function(object)
        error {error_object=object}
    end,
    pairs = pairs,
    ipairs = ipairs,
    unpack = unpack,
    io = io,
    table = table,
    string = string,
    tostring = tostring,
    tonumber = tonumber,
    math = math
}

-- Custom require and dofile functions
env._G = env
env.require = function(fpath)
    local fpath = fpath:gsub("%.", "/")
    local f = io.open(fpath .. ".lua", "r")
    local code = f:read("*a")
    f:close()

    local success, ret = pcall(lua.run, lua, code, env)

    if not success then
        error("In file " .. fpath .. ": " .. ret)
    end

    return ret
end

env.dofile = function(fpath)
    local f = io.open(fpath, "r")
    local code = f:read("*a")
    f:close()

    local success, ret = pcall(lua.run, lua, code, env)

    if not success then
        error("In file " .. fpath .. ": " .. ret)
    end

    return ret
end


lua:dofile("test.lua", env)