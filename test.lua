print("Hello World")


print("Environment closure testing")
-- environment closure testing
local function createCounter()
    local i = 0

    return function()
        i = i + 1
        return i
    end
end


local counter = createCounter()
print(counter())
print(counter())
print(counter())


print("Table testing")
-- table stuff
local sprite_defaults = {
    print_coords = function(self)
        print(self.x, self.y)
    end
}


local function sprite(x, y)
    return setmetatable({
        x = x,
        y = y
    }, {__index=sprite_defaults})
end


local test_sprite = sprite(2, 5)
test_sprite:print_coords()

print("Other fun stuff")
-- Loading the scanner from the module because why not
local luaScanner = require("lua.scanner")
local tokens = luaScanner:scan("print('Hello')")

for _, token in ipairs(tokens) do
    print(token.type, token.lexeme)
end