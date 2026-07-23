local command = assert(arg[1], "missing command")
local marker = assert(arg[2], "missing marker")

local pipe = assert(io.popen(command, "r"))
local output = pipe:read("*a")
pipe:close()

assert(output:find(marker, 1, true), "hidden process shell output was missing")
if arg[3] == "emit" then
    io.write(output)
else
    print("Hidden process shell tests passed")
end
