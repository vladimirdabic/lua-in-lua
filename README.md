## This branch is for adding stuff to Lua
Basically, we add random stuff and fun stuff into the interpreter here :D

```lua
-- also the syntax highlighter doesn't know what to do with this LOL
local class ExampleClass
    field number -- initialized from the constructor
    static field message = "Hello World"

    function constructor(self, number)
        self.number = number
    end

    function add(self, x)
        return self.number + x
    end
end

-- Static field
print(ExampleClass.message)

local test = ExampleClass(20)
print(test:add(2))
```

```lua
-- Stuff we really need in Lua :^)
local num = 20
print(num)
num += 2
print(num)
num -= 5
print(num)
```
