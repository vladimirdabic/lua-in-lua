local m = {
    current = 0,
    start = 0,
    line = 1,
    source = nil,
    tokens = nil,

    character_switch = {
        ['+'] = function(self) self:addToken(self:match('=') and 'PLUS_EQ' or 'PLUS') end,
        ['-'] = function(self)
            if self:match('-') then
                if self:match('[') and self:match('[') then
                    while true do
                        if self:match(']') and self:match(']') then return end
                        if not self:available() then return end
                        self.current = self.current + 1
                    end
                end
                while self:peek() ~= '\n' and self:available() do
                    self.current = self.current + 1
                end
            else
                self:addToken(self:match('=') and 'MINUS_EQ' or 'MINUS')
            end
        end,
        ['*'] = function(self) self:addToken('STAR') end,
        ['/'] = function(self) self:addToken('SLASH') end,
        ['^'] = function(self) self:addToken('UP') end,
        ['%'] = function(self) self:addToken('PRECENTAGE') end,
        ['.'] = function(self) self:addToken(self:match('.') and (self:match('.') and 'VARARGS' or 'CONCAT') or 'DOT') end,
        [','] = function(self) self:addToken('COMMA') end,
        [':'] = function(self) self:addToken('COLON') end,
        [';'] = function(self) self:addToken('SEMICOLON') end,
        ['<'] = function(self) self:addToken(self:match('=') and 'LESS_EQUAL' or 'LESS') end,
        ['>'] = function(self) self:addToken(self:match('=') and 'GREATER_EQUAL' or 'GREATER') end,
        ['='] = function(self) self:addToken(self:match('=') and 'DOUBLE_EQUALS' or 'EQUALS') end,
        ['~'] = function(self) self:addToken(self:match('=') and 'NOT_EQUAL' or 'TILDA') end,
        ['#'] = function(self) self:addToken('HASHTAG') end,
        ['{'] = function(self) self:addToken('OPEN_BRACE') end,
        ['}'] = function(self) self:addToken('CLOSE_BRACE') end,
        ['('] = function(self) self:addToken('OPEN_PAREN') end,
        [')'] = function(self) self:addToken('CLOSE_PAREN') end,
        ['['] = function(self) if self:match('[', '=') then self:scanBigString() else self:addToken('OPEN_SQUARE') end end,
        [']'] = function(self) self:addToken('CLOSE_SQUARE') end,
        ["'"] = function(self) self:scanString("'") end,
        ['"'] = function(self) self:scanString('"') end
    },

    reserved_words = {
        ["if"] = true,
        ["then"] = true,
        ["else"] = true,
        ["elseif"] = true,
        ["local"] = true,
        ["repeat"] = true,
        ["until"] = true,
        ["end"] = true,
        ["function"] = true,
        ["for"] = true,
        ["return"] = true,
        ["break"] = true,
        ["in"] = true,
        ["do"] = true,
        ["while"] = true,
        ["static"] = true,
        ["field"] = true,
        ["class"] = true,
        ["nil"] = true,
        ["and"] = true,
        ["or"] = true,
        ["not"] = true,
        ["true"] = true,
        ["false"] = true,
        ["debugdmpenvstack"] = true
    },

    escaped_chars = {
        ['t'] = '\t',
        ['n'] = '\n',
        ['r'] = '\r',
        ['a'] = '\a',
        ['f'] = '\f',
        ['z'] = '\z',
        ['v'] = '\v',
        ['b'] = '\b',
        ['"'] = "\"",
        ["'"] = "'",
        ['\\'] = '\\'
    }
}


---Scans the string input and returns a list of tokens
---@param input string
---@return table "Array table of tokens"
function m:scan(input)
    self.current = 1
    self.line = 1
    self.source = input
    self.tokens = {}

    while self:available() do
        self.start = self.current
        self:scanToken()
    end

    self:addToken("EOF")

    return self.tokens
end




function m:scanToken()
    local c = self:advance()
    
    if self.character_switch[c] then
        self.character_switch[c](self)    
    elseif c:match("[\r\t ]") then
        return
    elseif c == '\n' then
        self.line = self.line + 1
    elseif self:isAlpha(c) then
        self:scanIdentifier()
    elseif self:isDigit(c) then
        self:scanNumber()
    else
        error("[Line " .. self.line .. "] Unexpected character '" .. c .. "'")
    end
end

---Adds a token to the array
---@param token_type string
---@param literal any
function m:addToken(token_type, literal)
    self.tokens[#self.tokens+1] = {
        type = token_type,
        line = self.line,
        literal = literal,
        lexeme = self.source:sub(self.start, self.current-1)
    }
end



function m:scanIdentifier()
    while self:isAlphaNumeric(self:peek()) and self:available() do
        self.current = self.current + 1
    end

    local lexeme = self.source:sub(self.start, self.current-1)
    local token_type = self.reserved_words[lexeme] and lexeme or "identifier"

    self:addToken(token_type, lexeme)
end

function m:scanNumber()
    -- check if hex
    if self:prev() == '0' and self:match('x', 'X') then
        self:scanHexNumber()
        return
    end

    while self:isDigit(self:peek()) and self:available() do
        self.current = self.current + 1
    end

    if self:match('.') then
        while self:isDigit(self:peek()) and self:available() do
            self.current = self.current + 1
        end
    end

    if self:match('e', 'E') then
        self:match('+', '-')
        while self:isDigit(self:peek()) and self:available() do
            self.current = self.current + 1
        end
    end

    local lexeme = self.source:sub(self.start, self.current-1)
    local num = tonumber(lexeme)

    if not num then
        error("[Line " .. self.line .. "] Failed to parse number '" .. lexeme .. "'")
    end

    self:addToken("number", num)
end

function m:scanHexNumber()
    while self:isHexDigit(self:peek()) and self:available() do
        self.current = self.current + 1
    end

    if self:match('.') then
        while self:isHexDigit(self:peek()) and self:available() do
            self.current = self.current + 1
        end
    end

    if self:match('p', 'P') then
        self:match('+', '-')
        while self:isDigit(self:peek()) and self:available() do
            self.current = self.current + 1
        end
    end

    local lexeme = self.source:sub(self.start, self.current-1)
    local num = tonumber(lexeme)

    if not num then
        error("[Line " .. self.line .. "] Failed to parse number '" .. lexeme .. "'")
    end

    self:addToken("number", num)
end

function m:scanString(closing_char)
    while self:peek() ~= closing_char and self:available() do
        if self:peek() == '\n' then
            error("[Line " .. self.line .. "] New lines aren't allowed in strings")
        end
        if self:peek() == "\\" then
            self.current = self.current + 1
        end
        self.current = self.current + 1
    end

    if not self:available() then
        error("[Line " .. self.line .. "] Unterminated string")
    end

    -- consume closing char
    self.current = self.current + 1
    local lexeme = self.source:sub(self.start+1, self.current-2)

    lexeme = lexeme:gsub("\\[0-9][0-9]?[0-9]?", function(str)
        return string.char(str:sub(2))
    end)

    lexeme = lexeme:gsub("\\.", function(str)
        local c = str:sub(2, 2)
        if self.escaped_chars[c] then
            return self.escaped_chars[c]
        else
            return str
        end
    end)

    self:addToken("string", lexeme)
end

function m:scanBigString()
    local equals = self:prev() == '=' and 1 or 0
    
    while self:match('=') do
        equals = equals + 1
    end

    if equals ~= 0 then
        self:consume('[', "Expected [ to start multiline string")
    end

    while self:peek() ~= ']' and self:available() do
        if self:peek() == "\\" then
            self.current = self.current + 1
        end
        self.current = self.current + 1
    end

    self:advance() -- consume closing ]

    for _=1, equals do
        self:consume('=', "Expected same number of = in the multiline string")
    end

    self:consume(']', "Expected ']' to close multiline string")

    local lexeme = self.source:sub(self.start+2+equals, self.current-(3+equals))
    self:addToken("string", lexeme)
end

function m:isDigit(c)
    return c:match("[0-9]")
end

function m:isHexDigit(c)
    return c:match("[0-9a-fA-F]")
end

function m:isAlpha(c)
    return c:match("[a-zA-Z_]")
end

function m:isAlphaNumeric(c)
    return c:match("[a-zA-Z_0-9]")
end

function m:peek()
    if not self:available() then return '\0' end
    return self.source:sub(self.current, self.current)
end

function m:prev()
    return self.source:sub(self.current-1, self.current-1)
end

function m:consume(c, err)
    if self:peek() == c then return self:advance() end
    error(err)
end

function m:match(...)
    local chars = {...}
    for _, c in ipairs(chars) do
        if self:peek() == c then
            self.current = self.current + 1
            return true
        end
    end
    
    return false
end


function m:available()
    return self.current <= #self.source
end


function m:advance()
    local c = self.source:sub(self.current, self.current)
    self.current = self.current + 1
    return c
end

return m