local m = {}

local function lines(s)
    if s:sub(-1)~="\n" then s=s.."\n" end
    return s:gmatch("(.-)\n")
end

function m:process(str)
    self.once = {}

    return self:processStr(str, 'main')
end


function m:processStr(str, ctx)
    local new = ""
    for line in lines(str) do
        if line:sub(1, 9) == '#include ' then
            local fname = line:sub(10)
            if not self.once[fname] then
                local f = io.open(fname .. '.xlua', 'r')
                local code = f:read('*a')
                f:close()
                new = new .. self:processStr(code, fname) .. '\n'
            end
        elseif line:sub(1, 5) == '#once' then
            self.once[ctx] = true
        else
            new = new .. line .. '\n'
        end
    end

    return new
end


return m