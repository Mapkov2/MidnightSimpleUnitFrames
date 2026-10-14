-- Share the original hook-free sampler and its two independent heap samples.
local root = (arg[3] or assert(arg[1])):gsub("\\", "/")
local file = assert(io.open(root .. "/tools/tests/responsibility_route_heap_smoke.lua", "rb"))
local source = file:read("*a")
file:close()
source = source:gsub("responsibility_route_paths.lua", "responsibility_adapter_paths.lua")
source = source:gsub("responsibility_route_costs.tsv", "responsibility_adapter_costs.tsv")
assert(loadstring(source, "@" .. root .. "/tools/tests/responsibility_adapter_heap_smoke.lua"))()
