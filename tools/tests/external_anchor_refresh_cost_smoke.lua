-- Measure the complete exported refresh, including real foreign-anchor work.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local harness = arg[3] or root
local World = dofile(harness .. "/tools/tests/health_tick_world.lua")
local errors = {}
for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "CustomAnchor" }) do
    -- The unit-frame files bind these two providers when they load: the counting stand-ins go in
    -- after the real owner exported and before the first consumer loads.
    local anchor
    local lookups, sizes = 0, 0
    local function Standins(env)
        env.MSUF_GetEffectiveCooldownFrame = function() lookups = lookups + 1; return anchor end
        env.MSUF_GetUsableCooldownAnchorSize = function() sizes = sizes + 1; return anchor:GetWidth(), anchor:GetHeight() end
    end
    local w = World.New(root, flavor, { beforeFile = function(path, env)
        if path:find("Elements/MSUF_UF_Elements_Power.lua", 1, true) or path:find("Engine/MSUF_UF_Factory.lua", 1, true) then
            Standins(env)
        end
    end })
    local env, uf = w.env, w.UF
    env.UnitName = function() return "Player" end
    anchor = env.CreateFrame("Frame", nil, env.UIParent)
    anchor:SetPoint("CENTER", env.UIParent, "CENTER", 0, 0)
    env.CustomAnchor = anchor
    Standins(env)
    w.single.MSUFSpec.anchorFrameName = name
    uf.spawned, uf.unitOrder, uf.frames = true, { "target" }, { target = w.single }
    local function Run()
        for i = 1, 100 do uf.Factory.RefreshExternalAnchor(name) end
    end
    Run()
    local work = 0
    lookups, sizes = 0, 0
    w:StartCounting()
    debug.sethook(function()
        if debug.getinfo(2, "S").source:find("/MidnightSimpleUnitFrames/", 1, true) then work = work + 1 end
    end, "", 1)
    Run()
    debug.sethook()
    local calls, natives = w:StopCounting(), lookups + sizes
    for _, count in pairs(calls) do natives = natives + count end
    local allocated = {}
    local capacity = {}
    for i = 1, 192 do capacity[i] = false end
    local function Allocate(...)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        Run()
        local delta = collectgarbage("count") - before
        collectgarbage("restart")
        return delta
    end
    for sample = 1, 2 do allocated[sample] = Allocate(unpack(capacity)) end
    local minimum = math.min(unpack(allocated))
    print(name, work, natives, minimum)
    if name ~= "CustomAnchor" and (flavor == "Mainline" or flavor == "Forever") then
        assert(w.single._msufUnitExternalAnchorProxy, "refresh did not attach the foreign-anchor proxy")
        local cap = name == "EssentialCooldownViewer" and 97300 or 95800
        if work > cap or natives ~= 800 or minimum > 37.5 then
            errors[#errors + 1] = name .. ": " .. work .. " VM, " .. natives .. " natives, " .. minimum .. " KiB"
        end
    end
end
assert(#errors == 0, flavor .. ": complete anchor refresh regression:\n" .. table.concat(errors, "\n"))
print("external_anchor_refresh_cost_smoke: ok (" .. flavor .. ")")
