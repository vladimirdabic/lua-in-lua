
-- classes are defined in the global scope
-- also the syntax highlighter doesn't know what to do with this LOL
local class Test
    field a
    field b = "XD"

    function constructor(self)
        self.a = 20
    end

    static function say(msg)
        print("Msg: ".. msg)
    end

    function add(self, x, y)
        return x + y
    end

    static class Values
        static field msg = "Hello World"
    end
end


print(Test.Values.msg)

local class_inst = Test()
print(class_inst.a)
print(class_inst.b)

Test.say("Lol")
print(class_inst:add(2, 2))

-- Stuff we really need in Lua :^)
local num = 20
print(num)
num += 2
print(num)
num -= 5
print(num)