local m = {
    Scanner = require("lua.scanner"),
    Parser = require("lua.parser"),
    Interpreter = require("lua.interpreter")
}


---Parses string input and returns a tree
---@param input string
---@return table "Tree representation"
function m:getTree(input)
    local tokens = self.Scanner:scan(input)
    return self.Parser:parse(tokens)
end

---
---Runs a lua string, `environment` should be a table with variables and functions that will be used as the global environment
---
---@param input string
---@param environment table
---@return ...
function m:run(input, environment, ...)
    local tokens = self.Scanner:scan(input)
    local tree = self.Parser:parse(tokens)
    local env = self.Interpreter:encloseEnvironment(environment)
    self.Interpreter:setEnvMeta(env, "varargs", {...})
    env.arg = {...}
    return self.Interpreter:evaluate(tree, env)
end

---
---Runs a lua file, `environment` should be a table with variables and functions that will be used as the global environment
---
---@param file_path string
---@param environment table
---@return ...
function m:dofile(file_path, environment, ...)
    local f = io.open(file_path, "r")
    if not f then error("Failed to load file") end
    local source = f:read("*a")
    f:close()
    return self:run(source, environment, ...)
end

return m