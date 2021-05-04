local m = {
    current = 0,
    line = 1,
    tokens = nil,
    
    precedence = {
        ["and"] = {prec=2, assoc='left'},
        ["or"] = {prec=2, assoc='left'},

        LESS = {prec=5, assoc='left'},
        LESS_EQUAL = {prec=5, assoc='left'},
        GREATER = {prec=5, assoc='left'},
        GREATER_EQUAL = {prec=5, assoc='left'},
        DOUBLE_EQUALS = {prec=5, assoc='left'},
        NOT_EQUAL = {prec=5, assoc='left'},

        CONCAT = {prec=10, assoc='left'},

        PLUS = {prec=20, assoc='left'},
        MINUS = {prec=20, assoc='left'},

        STAR = {prec=30, assoc='left'},
        SLASH = {prec=30, assoc='left'},
        PRECENTAGE = {prec=30, assoc='left'},

        UP = {prec=40, assoc='right'}
    }
}


---Parses tokens and returns a tree
---@param tokens table "Array table of tokens"
---@return table "Tree"
function m:parse(tokens)
    self.current = 1
    self.line = 1
    self.tokens = tokens

    return self:parseChunk()
end


function m:parseChunk()
    local statements = {}
    local parsed

    while self:available() do
        parsed = false

        if self:match("return") then
            self:match("SEMICOLON")
            if self:available() then
                local node = {type="return", values=self:parseExprList()}
                self:match("SEMICOLON")
                if self:available() then error("Return statement must be the last statement in the block") end
                statements[#statements+1] = node
            else
                statements[#statements+1] = {type="return", values={nil}}
            end
            parsed = true
        end

        if not parsed then
            self.line = self:peek().line
            statements[#statements+1] = self:parseStatement()
        end

        self:match("SEMICOLON")
    end

    return {type="chunk", statements=statements}
end

function m:parseBlock(token_type, ...)
    local token_type = token_type or "end"
    local statements = {}
    local parsed

    while not self:match(token_type, ...) do
        parsed = false

        if self:match("return") then
            self:match("SEMICOLON")
            if not self:tokenOneOf(self:peek(), token_type, ...) then
                local node = {type="return", values=self:parseExprList()}
                self:match("SEMICOLON")
                if not self:tokenOneOf(self:peek(), token_type, ...) then error("Return statement must be the last statement in the block") end
                statements[#statements+1] = node
            else
                statements[#statements+1] = {type="return", values={nil}}
            end
            parsed = true
        end

        if self:match("break") then
            self:match("SEMICOLON")
            if not self:tokenOneOf(self:peek(), token_type, ...) then
                error("Break statement must be the last statement in the block")
            else
                statements[#statements+1] = {type="break"}
            end
            parsed = true
        end

        if not parsed then
            self.line = self:peek().line
            statements[#statements+1] = self:parseStatement()
        end

        self:match("SEMICOLON")
    end

    return {type="block", statements=statements}
end


function m:parseStatement()
    if self:match("do") then return {type="do", body=self:parseBlock()} end

    if self:match("debugdmpenvstack") then return {type="debugdmpenvstack"} end

    if self:match("while") then
        local expr = self:parseExpr()
        self:consume("do", "Expected 'do' after while")
        return {type="while", expr=expr, body=self:parseBlock()}
    end

    if self:match("repeat") then
        local body = self:parseBlock('until')
        --self:consume("until", "Expected 'until' after repeat body") --consumed by parseBlock
        local expr = self:parseExpr()
        return {type="repeat", expr=expr, body=body}
    end

    if self:match("if") then
        local expr = self:parseExpr()
        self:consume("then", "Expected 'then' after if")

        local main_body = self:parseBlock('end', 'elseif', 'else')
        local clauses = {{expr=expr, body=main_body}}
        local else_body = nil

        while self:tokenOneOf(self:prev(), 'elseif', 'else') do
            local ttype = self:prev().type
            local subexpr

            if ttype == 'elseif' then
                subexpr = self:parseExpr()
                self:consume("then", "Expected 'then' after 'elseif'")
            end

            local body = self:parseBlock('end', 'elseif', 'else')
            
            if ttype == 'elseif' then clauses[#clauses+1] = {expr=subexpr, body=body}
            elseif ttype == 'else' then else_body = body end

        end

        return {type="if", expr=expr, clauses=clauses, else_body=else_body}
    end

    if self:match("for") then

        -- standard for loop
        if self:peek(1).type == "EQUALS" then
            local var_name = self:consume("identifier", "Expected variable name after for").lexeme
            self:consume("EQUALS", "Expected '=' after variable name")
            local start = self:parseExpr()
            self:consume("COMMA", "Expected ',' after for loop start")
            local end_loop = self:parseExpr()

            local step
            if self:match("COMMA") then
                step = self:parseExpr()
            else
                step = {type="literal", value=1}
            end

            self:consume("do", "Expected 'do' after for loop")

            local body = self:parseBlock()
            return {type="for", var_name=var_name, start=start, end_loop=end_loop, step=step, body=body}
        end

        -- foreach loop
        local ids = self:parseIdList()
        self:consume("in", "Expected 'in' after for loop variable names")

        local exprs = self:parseExprList()

        self:consume("do", "Expected 'do' after for loop")

        local body = self:parseBlock()
        return {type="foreach", variables=ids, expressions=exprs, body=body}
    end

    if self:match("function") then
        local func_name = self:parseFunctionName()
        local func_value = self:parseFunctionBody()

        if func_name.method then
            table.insert(func_value.arg_names, 1, "self")
        end

        func_name.node.value = func_value

        return func_name.node
    end

    -- extended stuff

    if self:match("class") then
        local cls = self:parseClass()
        return {type='assign', name=cls.name, value=cls}
    end

    -----------------

    if self:match("local") then

        if self:match("function") then
            local name = self:consume("identifier", "Expected function name").lexeme
            local func_value = self:parseFunctionBody()

            return {type="declare_local", names={name}, values={func_value}}
        end

        -- extended stuff
        if self:match("class") then
            local cls = self:parseClass()
            return {type='declare_local', names={cls.name}, values={cls}}
        end
        ----

        local idlist = self:parseIdList()
        local init_values

        if self:match("EQUALS") then
            init_values = self:parseExprList()
        else
            init_values = {}
        end

        return {type="declare_local", names=idlist, values=init_values}

    end


    if self:tokenOneOf(self:peek(1), "PLUS_EQ", "MINUS_EQ") then
        local var_name = self:consume("identifier", "Expected variable name before " .. self:peek(1).lexeme).lexeme
        local operator = self:advance()
        local expr = self:parseExpr()

        return {type=operator.type == "PLUS_EQ" and "increment" or "decrement", name=var_name, value=expr}
    end


    local func_call = self:parseCall()
        
    if func_call.type == "call" or func_call.type == "get_call" then
        return func_call
    end

    local exprs = {func_call}

    if func_call.type ~= "get" and func_call.type ~= "variable" then
        error("[Line " .. self.line .. "] Expected a statement")
    end
    self:match("COMMA")

    if not self:check("EQUALS") then
        repeat
            local expr = self:parseCall()
            if expr.type ~= "get" and expr.type ~= "variable" then
                error("[Line " .. self.line .. "] Expected a statement")
            end
            exprs[#exprs+1] = expr
        until not self:match("COMMA")
    end

    self:consume("EQUALS", "Expected '=' after variable list")
    local init_values = self:parseExprList()

    return {type="assign_expr", exprs=exprs, values=init_values}
end

function m:parseClass()
    local class_name = self:consume("identifier", "Expected class name after 'class'").lexeme
    local static_body = {}
    local non_static_body = {}
    local constructor

    while not self:match('end') do
        -- parse class fields
        local is_static = self:match("static")
        local node

        if self:match("field") then
            local field_name = self:consume("identifier", "Expected field name after 'field'").lexeme
            local initial_value

            if self:match("EQUALS") then
                initial_value = self:parseExpr()
            else
                initial_value = {type="literal", value=nil}
            end

            node = {name=field_name, value=initial_value}

        elseif self:match("function") then
            local func_name = self:consume("identifier", "Expected function name after 'function'").lexeme
            local func_body = self:parseFunctionBody()

            if func_name == "constructor" then
                constructor = func_body
            else
                node = {name=func_name, value=func_body}
            end
        
        elseif self:match("class") then
            local cls = self:parseClass()
            node = {name=cls.name, value=cls}
        end

        if is_static then static_body[#static_body+1] = node else non_static_body[#non_static_body+1] = node end
    end

    return {type="class", name=class_name, static_body=static_body, non_static_body=non_static_body, constructor=constructor}
end

function m:parseIdList()
    local names = {}

    repeat
        names[#names+1] = self:consume("identifier", "Expected variable name after ','").lexeme
    until not self:match("COMMA")

    return names
end

function m:parseFunctionName()
    local names = {}

    repeat
        names[#names+1] = self:consume("identifier", "Expected variable name after '.'").lexeme
    until not self:match("DOT")

    local method = false
    if self:match("COLON") then
        method = true
        names[#names+1] = self:consume("identifier", "Expected variable name after ':'").lexeme
    end

    if #names == 1 then
        return {node={type="assign", name=names[1]}, method=method}
    end

    local tree = {type="get", from={type="variable", name=names[1]}, index={type="literal", value=names[2]}}
    
    if #names > 2 then
        for i=3, #names do
            tree = {type="get", from=tree, index={type="literal", value=names[i]}}
        end
    end

    return {node={type="set", in_value=tree.from, index=tree.index}, method=method}
end

function m:parseExprList()
    local exprs = {}

    repeat
        exprs[#exprs+1] = self:parseExpr()
    until not self:match("COMMA")

    return exprs
end

function m:parseExpr()
    return self:parseBinOp(0)
end

function m:parseBinOp(min_prec)
    local left = self:parseCall()

    while true do
        if not self:available() then break end
        local op_token = self:peek()
        if not self.precedence[op_token.type] then break end -- not an operator
        local prec_data = self.precedence[op_token.type]
        if prec_data.prec < min_prec then break end -- lower precedence, so break

        -- consume op token
        self.current = self.current + 1

        local next_prec = prec_data.assoc == 'left' and prec_data.prec + 1 or prec_data.prec
        local right = self:parseBinOp(next_prec)

        left = {type="operation", operator=op_token.type, left=left, right=right}
    end

    return left
end


function m:parseCall()
    local left = self:parsePrimaryExpr()

    while true do
        if self:match("OPEN_PAREN") then
            left = {type="call", callee=left, args=self:parseArgs()}

        elseif self:match("OPEN_BRACE") then
            left = {type="call", callee=left, args={self:parseTableConstructor()}}

        elseif self:match("string") then
            left = {type="call", callee=left, args={{type='literal', value=self:prev().literal}}}

        elseif self:match("COLON") then
            local idx = self:consume("identifier", "Expected function name after ':'").lexeme
            self:consume("OPEN_PAREN", "Expected '(' after function name")
            local args = self:parseArgs()
            left = {type="get_call", callee=left, index=idx, args=args}

        elseif self:match("DOT") then
            local idx = self:consume("identifier", "Expected field name after '.'")
            left = {type="get", from=left, index={type="literal", value=idx.lexeme}}

        elseif self:match("OPEN_SQUARE") then
            local idx = self:parseExpr()
            self:consume("CLOSE_SQUARE", "Expected ']' after indexing expression")
            left = {type="get", from=left, index=idx}
        else
            break
        end
    end

    return left
end

function m:parseArgs()
    local args = {}

    if not self:check("CLOSE_PAREN") then
        repeat
            args[#args+1] = self:parseExpr()
        until not self:match("COMMA")
    end

    self:consume("CLOSE_PAREN", "Expected ')' after parameters")
    return args
end

function m:parsePrimaryExpr()
    if self:match("nil") then return {type="literal", value=nil} end
    if self:match("string") then return {type="literal", value=self:prev().literal} end
    if self:match("number") then return {type="literal", value=self:prev().literal} end
    if self:match("true") then return {type="literal", value=true} end
    if self:match("false") then return {type="literal", value=false} end
    if self:match("function") then return self:parseFunctionBody() end
    if self:match("OPEN_BRACE") then return self:parseTableConstructor() end

    if self:match("identifier") then return {type="variable", name=self:prev().lexeme} end
    if self:match("OPEN_PAREN") then 
        local expr = self:parseExpr()
        self:consume("CLOSE_PAREN", "Expected ')' after grouping expression")
        return expr
    end

    if self:match("not") then return {type="not", value=self:parseBinOp(40)} end
    if self:match("MINUS") then return {type="uminus", value=self:parseBinOp(40)} end
    if self:match("HASHTAG") then return {type="get_length", value=self:parseBinOp(40)} end
    if self:match("VARARGS") then return {type="varargs"} end

    print(self:peek().type)
    error("Expected expression")
end

function m:parseFunctionBody()
    self:consume("OPEN_PAREN", "Expected '(' for function declaration")

    local arg_names = {}
    local varargs = false

    if not self:check("CLOSE_PAREN") then
        repeat
            if self:match("VARARGS") then
                varargs = true
                break
            else
                arg_names[#arg_names+1] = self:consume("identifier", "Expected variable name in function parameter definition").lexeme
            end
        until not self:match("COMMA")
    end

    self:consume("CLOSE_PAREN", "Expected ')' after function parameter definition")

    local body = self:parseBlock()
    body.type = 'chunk'

    return {type="function", arg_names=arg_names, varargs=varargs, body=body}
end

function m:parseTableConstructor()
    local fields = {}

    if not self:check("CLOSE_BRACE") then
        while true do
            fields[#fields+1] = self:parseTableField()
            if not (self:match('COMMA') or self:match('SEMICOLON')) then break end
            if self:check("CLOSE_BRACE") then break end
        end
    end

    self:consume("CLOSE_BRACE", "Expected '}' after table constructor")
    
    return {type="table", fields=fields}
end

function m:parseTableField()
    if self:match("VARARGS") then
        return {array_item=true, value={type='varargs'}}
    end

    if self:match("OPEN_SQUARE") then
        local idx = self:parseExpr()
        self:consume("CLOSE_SQUARE", "Expected ']' after table field key")
        self:consume("EQUALS", "Expected '=' after table field key")
        local value = self:parseExpr()
        return {key=idx, value=value}
    end

    if self:peek(1).type == "EQUALS" then
        local idx = self:consume("identifier", "Expected field name").lexeme
        self:consume("EQUALS", "Expected '=' after table field key")
        local value = self:parseExpr()
        return {key={type="literal", value=idx}, value=value}
    end

    local value = self:parseExpr()
    return {array_item=true, value=value}
end

function m:match(...)
    local types = {...}

    for _, token_type in ipairs(types) do
        if self:check(token_type) then
            self.current = self.current + 1
            return true
        end
    end

    return false
end

function m:check(token_type)
    return self:peek().type == token_type
end

function m:tokenOneOf(token, ...)
    local types = {...}

    for _, token_type in ipairs(types) do
        if token.type == token_type then
            return true
        end
    end

    return false
end

function m:consume(token_type, err)
    if self:check(token_type) then return self:advance() end
    error("[Line " .. self:peek().line .. "] ".. err ..'\n'..self:peek().type) 
end

function m:peek(offset)
    local offset = offset or 0
    if self.current+offset > #self.tokens then return {type="EOF"} end
    return self.tokens[self.current+offset]
end

function m:prev()
    return self.tokens[self.current-1]
end

function m:available()
    return self:peek().type ~= "EOF"
end

function m:advance()
    local token = self.tokens[self.current]
    self.current = self.current + 1
    return token
end



return m