-- <root> [client]: actual header owners, native faults, exact batch restoration.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    if arg[3] then
        local loadFile = h.world.LoadFile
        function h.world:LoadFile(path, addon, namespace)
            local file = io.open(arg[3] .. "/" .. path:match("[^/]+$"), "rb")
            if not file then return loadFile(self, path, addon, namespace) end
            local source = file:read("*a")
            file:close()
            local chunk = assert(loadstring(source, "@" .. path))
            setfenv(chunk, self.env)
            return pcall(chunk, addon, namespace)
        end
    end
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local GF, UF = h.GF, h.UF
local conf = GF.GetConf("raid")
conf.enabled = true
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if name == nil then break end
    end
    error("missing upvalue " .. wanted)
end
local function State()
    return Upvalue(GF.BeginHeaderLayoutRebind, "headerLayoutRebindHeader"),
        Upvalue(GF.BeginHeaderLayoutRebind, "headerLayoutRebindDepth")
end
local reports, expectedHeader, expectedDepth = 0, nil, 0
local throwing = false
h.env.geterrorhandler = function() return function(message)
    local header, depth = State()
    assert(header == expectedHeader and depth == expectedDepth, "reporter saw leaked layout batch")
    reports = reports + 1
    assert(message:find("injected layout", 1, true), message)
    if throwing then error("injected reporter") end
end end
local function Restored()
    local header, depth = State()
    assert(header == expectedHeader and depth == expectedDepth, "layout batch leaked")
end
local cases = 0
for _, route in ipairs({ "flat", "priority", "preserved" }) do
    conf.preserveRaidGroups = route == "preserved"
    local priorityConf = GF.GetPriorityConf()
    local function Setup()
        if route == "priority" then return GF.SetupPriorityHeader("raid", h.env.UnitName("raid1"), 1) end
        return GF.SetupHeader("raid", "raid")
    end
    local header = assert(Setup())
    if not header:IsShown() then
        header:Show()
        GF.ScanHeader("raid", "raid")
    end
    for _, stage in ipairs(route == "flat" and { "Show", "GetWidth", "SetAttribute" } or { "Show" }) do
        for _, nesting in ipairs({ "none", "same", "other" }) do
            for _, raises in ipairs({ false, true }) do
                -- A different layout forces ConfigureHeader to hide the existing header.
                conf.spacing = conf.spacing == 2 and 3 or 2
                priorityConf.spacing = priorityConf.spacing == 2 and 3 or 2
                local child = assert(header:GetAttribute("child1"), route .. " has no native child")
                local visual = child._msufVisualFrame or child
                local outer = nesting == "same" and header or h.env.CreateFrame("Frame")
                if nesting ~= "none" then
                    assert(GF.BeginHeaderLayoutRebind(outer))
                    assert(GF.BeginHeaderLayoutRebind(outer))
                    expectedHeader, expectedDepth = outer, 2
                end
                local native, hit = header[stage], false
                header[stage] = function(self, ...)
                    local active = GF.IsHeaderLayoutRebindActive(child)
                    if (active or nesting == "other") and (stage ~= "SetAttribute" or (...) == "_msufLayoutNonce") then
                        hit = true
                        if stage == "Show" then native(self, ...) end
                        error("injected layout " .. stage)
                    end
                    return native(self, ...)
                end
                local before = reports
                throwing = raises
                local ok, message = pcall(Setup)
                header[stage], throwing = native, false
                Restored()
                assert(hit and reports > before, route .. "/" .. stage .. " fault was bypassed")
                if raises then assert(not ok and tostring(message):find("injected reporter", 1, true)) end
                if nesting ~= "none" then
                    GF.EndHeaderLayoutRebind(outer)
                    GF.EndHeaderLayoutRebind(outer)
                    expectedHeader, expectedDepth = nil, 0
                end
                Restored()
                -- A later ordinary batch must end at zero and flush deferred OnShow.
                conf.spacing = conf.spacing == 2 and 3 or 2
                priorityConf.spacing = priorityConf.spacing == 2 and 3 or 2
                assert(Setup())
                Restored()
                if route == "preserved" then GF.ScanHeader("raid", "raid") end
                assert(visual._msufGFHeaderOnShowDeferred == nil, "normal batch did not flush deferred OnShow")
                cases = cases + 1
            end
        end
    end
end
assert(cases > 0 and #h.violations == 0, "missing cases or protected writes")
print("PASS uf_header_layout_transaction " .. flavor .. ": " .. cases .. " real layout faults/reporter/nesting/recovery cases")
