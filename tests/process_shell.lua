local command = assert(arg[1], "missing command")
local marker = assert(arg[2], "missing marker")

local pipe = assert(io.popen(command, "r"))
local output = pipe:read("*a")
pipe:close()

assert(output:find(marker, 1, true), "hidden process shell output was missing")
print("Hidden process shell tests passed")
