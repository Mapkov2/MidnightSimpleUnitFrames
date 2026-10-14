-- Resolver registration uses the type captured before any late global replacement.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = dofile(root .. "/tools/tests/client_world.lua")
local w = World.New(root, flavor)
local originalSetter
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    local ok, diagnostic = load(self, path, addon, namespace)
    if ok and path:find("/MSUF_UF_Text_Runtime.lua", 1, true) then
        originalSetter = namespace.UFText.SetDisplayNameResolver
    end
    return ok, diagnostic
end
w:Boot()
assert(not w:FirstFailure(), flavor .. ": graph failed to boot")
-- Follow produced closures, including nested upvalues, across every moved owner.
local capturedType, seen, adapters = w.env.type, {}, {}
local function CheckCaptures(fn)
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == "type" then
            assert(value == capturedType, "callable boundary reads mutable global type")
            adapters[debug.getinfo(fn, "S").source:match("([^/]+)$")] = true
        end
        if name == "IsCallable" then
            local boundName, boundType = debug.getupvalue(value, 1)
            assert(boundName == "type" and boundType == capturedType, "callable adapter reads mutable global type")
            adapters[debug.getinfo(value, "S").source:match("([^/]+)$")] = true
        end
        if type(value) == "function" then CheckCaptures(value) end
    end
end
for _, owner in ipairs({ w.core.UFText, w.core.UFStatusRuntime, w.core.UF.Factory }) do
    for _, value in pairs(owner) do CheckCaptures(value) end
end
CheckCaptures(assert(originalSetter, "real Text Runtime setter missing"))
if w.core.UFModuleFactories then
    for _, file in ipairs({ "MSUF_UF_Elements_Status.lua", "MSUF_UF_Text_Runtime.lua", "MSUF_UF_Factory.lua" }) do
        assert(adapters[file], "callable capture was not exercised: " .. file)
    end
end
local text = w.core.UFText
local calls = 0
local resolver = function() calls = calls + 1; return "name" end
w.env.type = function() error("mutable global type reached") end
assert(select("#", originalSetter(resolver)) == 0, "original setter return arity changed")
assert(select("#", text.SetDisplayNameResolver(resolver)) == 0, "resolver setter return arity changed")
assert(calls == 0, "registration invoked the callback")
for _, invalid in ipairs({ false, 17, "invalid", {}, setmetatable({}, { __call = resolver }) }) do
    assert(select("#", text.SetDisplayNameResolver(invalid)) == 0, "invalid resolver return arity changed")
end
assert(select("#", text.SetDisplayNameResolver(nil)) == 0, "nil resolver return arity changed")
assert(calls == 0, "rejected resolver was invoked")
-- Foreign native methods remain mutable and retain the original function-only gate.
local target, region = {}, {}
local factory = w.core.UF.Factory
region.GetNumPoints = function() return 0 end
region.GetParent = function() return nil end
assert(factory.AnchorDependsOn(region, target) == false, "empty foreign chain changed")
region.GetParent = function(self) assert(self == region); return target end
assert(factory.AnchorDependsOn(region, target) == true, "late parent method was captured early")
region.GetParent = nil
region.GetNumPoints = function() return 1 end
region.GetPoint = function(self, index) assert(self == region and index == 1); return "CENTER", target end
assert(factory.AnchorDependsOn(region, target) == true, "point method receiver/return changed")
region.GetPoint = setmetatable({}, { __call = function() error("non-function method invoked") end })
assert(factory.AnchorDependsOn(region, target) == false, "callable-table method was accepted")
region.IsForbidden = function(self) assert(self == region); return true end
assert(factory.AnchorDependsOn(region, target) == true, "forbidden foreign frame was accepted")
print("text_resolver_type_capture_smoke: ok (" .. flavor .. ": captured type, callback and return arity)")
