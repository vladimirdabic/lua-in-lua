# Lua in Lua

### Questions
- **Why?**
  - Simple, because why not.
- **How does this work?**
  - It's a tree walker, meaning it's not as efficient as bytecode.
- **Does it support everything from Lua?**
  - It should. It might not have a thing or two but almost everything should work just fine.
  - Unsupported things (that I know of):
    - \u{} escape codes (utf escape code)
    - \x00 escape codes (hexadecimal escape code)
    - \0 escape codes (decimal escape codes)
    - Some forms of nested strings
    - Multiline comments

### Usage
```lua
local lua = require("lua.main")

local script = [[
print("Hello, World!")
]]

local environment = {
  print = print -- global print _G.print
}

-- If you want, you can pass the _G table as the environment, but I recommend making a special one
lua:run(script, environment)
```

### Can you run Lua in Lua in Lua?
Yes! You can.

```lua
local lua = require("lua.main")

-- Custom environment
local env = {
    print = print,
    getmetatable = getmetatable,
    setmetatable = setmetatable,
    type = type,
    pcall = function(f, ...) -- we need a simple pcall and error wrapper if you wanna call Lua in Lua in Lua in Lua and so on... :^)
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
    table = table,
    string = string,
    tostring = tostring,
    tonumber = tonumber,
    math = math
}

-- Custom require function
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

local script = [[
local lua = require("lua.main")
local script = "print('Hello World')"

local env = {
  print = print
}

lua:run(script, env)
]]

lua:run(script, env)

```

### Other
There's a special statement `debugdmpenvstack`\
All this does is it prints out the environment stack starting from the local stack up to the global one\
This won't affect any lua scripts and if it does, you can disable it yourself :^) (Its useful for debugging and playing around)

```lua
local number = 2000

local function test()
  local message = "Hello World"
  debugdmpenvstack -- dumps the environment stack to the output
end

test()
```
