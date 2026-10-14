-- Independent ordered client-frame receipt; never used for heap/VM sampling.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local harness = (arg[3] or root):gsub("\\", "/")
loadfile = dofile(harness .. "/tools/tests/responsibility_route_loader.lua")
local World = dofile(harness .. "/tools/tests/health_tick_world.lua")
local Routes = dofile(harness .. "/tools/tests/responsibility_route_paths.lua")
local _, options = Routes.New(World, root, flavor, harness)
for _, selected in ipairs(options) do
    local w, cases = Routes.New(World, root, flavor, harness)
    local case
    for _, candidate in ipairs(cases) do if candidate.name == selected.name then case = candidate end end
    local capture, rows, identities = false, {}, {}
    local nextIdentity = 0
    local function Encode(value)
        if w.Secrets.IsSecret(value) then return "<secret>" end
        local kind = type(value)
        if kind == "table" then
            local id = identities[value]
            if not id then nextIdentity = nextIdentity + 1; id = nextIdentity; identities[value] = id end
            return "object/" .. id
        end
        if kind == "function" then return "<function>" end
        return tostring(value)
    end
    -- Capture ordered frame/texture/font operations and every argument, with
    -- graph-local object identities rather than process memory addresses.
    for name, fn in pairs(w.h.widgets.Methods) do
        if type(fn) == "function" then
            w.h.widgets.Methods[name] = function(self, ...)
                if capture then
                    local row = { name, Encode(self) }
                    for i = 1, select("#", ...) do row[#row + 1] = Encode(select(i, ...)) end
                    rows[#rows + 1] = table.concat(row, "|")
                end
                return fn(self, ...)
            end
        end
    end
    case.prepare()
    case.run()
    capture = true
    case.run()
    capture = false
    print("CASE", flavor, case.name)
    for _, row in ipairs(rows) do print("FRAME", row) end
    -- Return arity and scalar output are separately retained by the behavior
    -- contracts. Strict secret objects reach these sinks without inspection.
end
print("responsibility_route_native_order: complete", flavor, #options)
