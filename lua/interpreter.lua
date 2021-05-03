local m = {}

local function tableToString(t)
    if type(t) ~= 'table' then return tostring(t) end
    local s = "{"

    for k, v in pairs(t) do
        s = s .. tostring(k) .. "=" .. tableToString(v) .. ', '
    end

    s = s:sub(1, #s-2)

    return s .. "}"
end

m.evals = {
    ['chunk'] = function(self, node, environment)
        for _, statement in ipairs(node.statements) do
            --self:evaluate(statement, environment)

            local success, r = pcall(self.evaluate, self, statement, environment)

            if not success then
                if type(r) == 'table' then
                    if r.type == 'return_error' then return unpack(r.values) end
                    if r.type == 'break_error' then return end
                end
                error(r)
            end
        end
    end,
    ['block'] = function(self, node, environment)
        for _, statement in ipairs(node.statements) do
            self:evaluate(statement, environment)
        end
    end,
    ['literal'] = function(self, node)
        return node.value
    end,
    ['assign'] = function(self, node, environment)
        local globals = self:getGlobal(environment)
        globals[node.name] = self:evaluate(node.value, globals)
    end,
    ['function'] = function(self, node, environment)
        return function(...)
            local func_env = self:encloseEnvironment(environment)

            for _, arg in ipairs(node.arg_names) do
                self:declareInEnv(func_env, arg)
            end

            local args = {...}
            local loop = math.min(#node.arg_names, #args)

            for i=1, loop do
                func_env[node.arg_names[i]] = args[i]
            end

            local varargs = {}
            if node.varargs then
                local new_args = {}
                if #args > #node.arg_names then
                    for i=#node.arg_names+1, #args do
                        varargs[#varargs+1] = args[i]
                        new_args[#new_args+1] = args[i]
                    end
                end
                func_env.arg = new_args
            end
            self:setEnvMeta(func_env, "varargs", varargs)

            return self:evaluate(node.body, func_env)
        end
    end,
    ["declare_local"] = function(self, node, environment)
        local values = self:evaluateExpressionList(node.values, environment)

        for _, var_name in ipairs(node.names) do
            self:declareInEnv(environment, var_name)
        end

        local loop = math.min(#node.names, #values)
        for i=1, loop do
            local var_name = node.names[i]
            local value = values[i]

            environment[var_name] = value
        end
    end,
    ["assign_expr"] = function(self, node, environment)
        local values = self:evaluateExpressionList(node.values, environment)

        local loop = math.min(#node.exprs, #values)
        for i=1, loop do
            local target = node.exprs[i]
            local value = values[i]
            
            if target.type == "variable" then
                self:setInEnv(environment, target.name, value)
            else -- otherwise it's a get from table
                local table_value = self:evaluate(target.from, environment)
                local index = self:evaluate(target.index, environment)
                table_value[index] = value
            end
        end
    end,
    ["get"] = function(self, node, environment)
        local from = self:evaluate(node.from, environment)
        local index = self:evaluate(node.index, environment)

        if not from then
            self:dumpEnv(environment)
        end

        return from[index]
    end,
    ["set"] = function(self, node, environment)
        local in_value = self:evaluate(node.in_value, environment)
        local value = self:evaluate(node.value, environment)
        local index = self:evaluate(node.index, environment)
        in_value[index] = value
    end,
    ["call"] = function(self, node, environment)
        local callee = self:evaluate(node.callee, environment)
        local args = {}

        for _, arg_node in ipairs(node.args) do
            local values = {self:evaluate(arg_node, environment)}
            for _, value in ipairs(values) do
                args[#args+1] = value
            end
            --args[#args+1] = self:evaluate(arg_node, environment)
        end

        return callee(unpack(args))
    end,
    ["get_call"] = function(self, node, environment)
        local callee = self:evaluate(node.callee, environment)
        local args = {}

        for _, arg_node in ipairs(node.args) do
            local values = {self:evaluate(arg_node, environment)}
            for _, value in ipairs(values) do
                args[#args+1] = value
            end
            --args[#args+1] = self:evaluate(arg_node, environment)
        end
        
        return callee[node.index](callee, unpack(args))
    end,
    ["variable"] = function(self, node, environment)
        return self:getFromEnv(environment, node.name)
    end,
    ["table"] = function(self, node, environment)
        local tbl = {}

        local array_idx = 1
        for _, table_field in ipairs(node.fields) do
            if table_field.array_item then
                local values = {self:evaluate(table_field.value, environment)}
                for _, value in ipairs(values) do
                    tbl[array_idx] = value
                    array_idx = array_idx + 1
                end
            else
                local key = self:evaluate(table_field.key, environment)
                local value = self:evaluate(table_field.value, environment)
                tbl[key] = value
            end
        end

        return tbl
    end,
    ['operation'] = function(self, node, environment)
        local left = self:evaluate(node.left, environment)

        if node.operator == 'or' then
            if left ~= nil and left ~= false then return left
            else return self:evaluate(node.right, environment) end
        elseif node.operator == 'and' then
            if left ~= nil and left ~= false then return self:evaluate(node.right, environment)
            else return left end
        end

        local right = self:evaluate(node.right, environment)

        if not self.operations[node.operator] then
            error("Unknown operator '" .. node.operator .. "'")
        end

        return self.operations[node.operator](left, right)
    end,
    ["if"] = function(self, node, environment)
        local new_env = self:encloseEnvironment(environment)
        for _, clause in ipairs(node.clauses) do
            if self:evaluate(clause.expr, environment) then
                self:evaluate(clause.body, new_env)
                return
            end
        end

        if node.else_body then self:evaluate(node.else_body, new_env) end
    end,
    ["while"] = function(self, node, environment)
        while self:evaluate(node.expr, environment) do
            local new_env = self:encloseEnvironment(environment)
            --self:evaluate(node.body, new_env)

            local success, r = pcall(self.evaluate, self, node.body, new_env)

            if not success then
                if type(r) == 'table' and r.type == 'break_error' then
                    return
                end
                error(r)
            end
        end
    end,
    ["repeat"] = function(self, node, environment)
        repeat
            local new_env = self:encloseEnvironment(environment)
            --self:evaluate(node.body, new_env)

            local success, r = pcall(self.evaluate, self, node.body, new_env)

            if not success then
                if type(r) == 'table' and r.type == 'break_error' then
                    return
                end
                error(r)
            end
        until self:evaluate(node.expr, environment)
    end,
    ["for"] = function(self, node, environment)
        local start = self:evaluate(node.start, environment)
        local end_loop = self:evaluate(node.end_loop, environment)
        local step = self:evaluate(node.step, environment)

        for i=start, end_loop, step do
            local new_env = self:encloseEnvironment(environment)
            new_env[node.var_name] = i
            --self:evaluate(node.body, new_env)

            local success, r = pcall(self.evaluate, self, node.body, new_env)

            if not success then
                if type(r) == 'table' and r.type == 'break_error' then
                    return
                end
                error(r)
            end
        end
    end,
    ["foreach"] = function(self, node, environment)
        do
            local f, s, var = unpack(self:evaluateExpressionList(node.expressions, environment))
            while true do
                local vars = {f(s, var)}
                if vars[1] == nil then break end
                var = vars[1]

                local new_env = self:encloseEnvironment(environment)

                local loop = math.min(#node.variables, #vars)
                for i=1, loop do
                    new_env[node.variables[i]] = vars[i]
                end

                --self:evaluate(node.body, new_env)

                local success, r = pcall(self.evaluate, self, node.body, new_env)

                if not success then
                    if type(r) == 'table' and r.type == 'break_error' then
                        return
                    end
                    error(r)
                end
            end
        end
    end,
    ["do"] = function(self, node, environment)
        local new_env = self:encloseEnvironment(environment)
        self:evaluate(node.body, new_env)
    end,
    ["return"] = function(self, node, environment)
        error {type="return_error", values=self:evaluateExpressionList(node.values, environment)}
    end,
    ["break"] = function(self, node, environment)
        error {type="break_error"}
    end,
    uminus = function(self, node, environment)
        return -(self:evaluate(node.value, environment))
    end,
    ['not'] = function(self, node, environment)
        return not (self:evaluate(node.value, environment))
    end,
    get_length = function(self, node, environment)
        return #self:evaluate(node.value, environment)
    end,
    varargs = function(self, node, environment)
        local varargs = self:getEnvVarargs(environment)
        return unpack(varargs)
    end,
    ['debugdmpenvstack'] = function(self, node, environment)
        self:dumpEnv(environment)
    end
}

m.operations = {
    PLUS = function(l, r)
        return l + r
    end,
    MINUS = function(l, r)
        return l - r
    end,
    STAR = function(l, r)
        return l * r
    end,
    SLASH = function(l, r)
        return l / r
    end,
    PRECENTAGE = function(l, r)
        return l % r
    end,
    UP = function(l, r)
        return l ^ r
    end,
    CONCAT = function(l, r)
        return l .. r
    end,
    LESS = function(l, r)
        return l < r
    end,
    LESS_EQUAL = function(l, r)
        return l <= r
    end,
    GREATER = function(l, r)
        return l > r
    end,
    GREATER_EQUAL = function(l, r)
        return l >= r
    end,
    DOUBLE_EQUALS = function(l, r)
        return l == r
    end,
    NOT_EQUAL = function(l, r)
        return l ~= r
    end
}

function m:evaluate(node, environment)
    if not self.evals[node.type] then
        error("No evaluator found for node of type '" .. node.type .. "'\n" .. debug.traceback())
    end

    if self.debug then
        print(node.type, tableToString(node))
    end

    return self.evals[node.type](self, node, environment)
end

function m:evaluateExpressionList(node_values, environment)
    local values = {}

    for _, val in ipairs(node_values) do
        local returned = {self:evaluate(val, environment)}
        for _, returned_value in ipairs(returned) do
            values[#values+1] = returned_value
        end
    end

    return values
end


function m:getGlobal(environment)
    local mt = getmetatable(environment)
    if mt and mt.enclosing then return self:getGlobal(mt.enclosing) end
    return environment
end

function m:encloseEnvironment(enclosing)
    local mt = {enclosing=enclosing, declared={}}
    local new_env = {}
    setmetatable(new_env, mt)
    return new_env
end

function m:getFromEnv(environment, key)
    if environment[key] then
        return environment[key]
    end

    local mt = getmetatable(environment)
    if mt and mt.enclosing then return self:getFromEnv(mt.enclosing, key) end
    
    return nil
end

function m:dumpEnv(environment, level)
    local level = level or 0

    print('--- up level ' .. level .. ' ---')
    for k, v in pairs(environment) do
        print(k, v)
    end

    local mt = getmetatable(environment)
    if mt and mt.enclosing then return self:dumpEnv(mt.enclosing, level + 1) end
end

function m:declareInEnv(environment, key)
    local mt = getmetatable(environment)
    mt.declared[key] = true
    setmetatable(environment, mt)
end

function m:setInEnv(environment, key, value)
    if environment[key] then
        environment[key] = value
        return
    end

    local mt = getmetatable(environment)
    
    if mt and mt.declared and mt.declared[key] then
        environment[key] = value
        return
    end
    
    if mt and mt.enclosing then return self:setInEnv(mt.enclosing, key, value) end
    
    -- reached global env
    environment[key] = value
end

function m:setEnvMeta(environment, key, value)
    local mt = getmetatable(environment) or {}
    mt[key] = value
end

function m:getEnvMeta(environment, key)
    local mt = getmetatable(environment) or {}
    return mt[key]
end

function m:getEnvVarargs(environment)
    local mt = getmetatable(environment) or {}
    if mt.varargs then return mt.varargs end
    if mt.enclosing then return self:getEnvVarargs(mt.enclosing) end
end

return m