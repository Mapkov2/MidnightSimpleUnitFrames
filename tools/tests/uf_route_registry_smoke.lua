local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local world = dofile(root .. "/tools/tests/client_world.lua").New(root, flavor)
world:Boot()
assert(not world:FirstFailure(), "client boot failed")
local UF, env = world.core.UF, world.env
assert(type(UF.RegisterRoute) == "function", "route registry missing")
assert(UF.EventElementAllowed("BossNumberIndicator") ~= true, "boss number added an event route")
assert(UF.identityElements.BossNumberIndicator ~= true, "boss number added an identity route")
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame.MSUFUnitKey = "player"
UF.AttachFrame(frame)
UF.SetFrameSpec(frame, { unit = "player", enabled = true })
local calls, compiles = 0, 0
local update = function() calls = calls + 1 end
local element = { Update = update, events = { "UNIT_TEST_ROUTE" }, Routes = { basic = true, identity = true } }
assert(UF.RegisterElement("CustomRouteConsumer", element))
assert(UF.RegisterRoute("custom-route", function(_, event, list)
    if event == "UNIT_TEST_ROUTE" then
        compiles = compiles + 1
        assert(list[1] == update and list[2] == false, "declared handler missing")
        return update
    end
end))
UF.ApplyElementsToFrame(frame, { "CustomRouteConsumer" })
assert(compiles == 1 and frame.UNIT_TEST_ROUTE == update, "route plugin was not compiled")
for _ = 1, 10 do frame:UpdateAllElements("MSUF_FORCE_UPDATE") end
assert(calls == 10 and compiles == 1, "runtime rebuilt the cold route")
-- A targeted Text transaction resolves value requirements before installing
-- Health's updater, without a call from Text.Apply into the Health owner.
local health = UF.elements.Health
local probe = { MSUFUnitKey = "player", MSUFSpec = { scope = "single" },
    _msufActiveElements = { Health = true } }
local cases = {
    { "percent", { healthSlotCount = 1, healthNeedsPercent = true }, health.UpdateValueSinglePercent },
    { "current", { healthSlotCount = 1, healthNeedsCurrent = true }, health.UpdateValueSingleCurrent },
    { "absolute", { healthSlotCount = 1, healthNeedsCurrent = true, healthNeedsMax = true }, health.UpdateValueSingleAbsolute },
    { "current-percent", { healthSlotCount = 1, healthNeedsCurrent = true, healthNeedsPercent = true }, health.UpdateValueSinglePercent },
    { "hidden", { healthSlotCount = 0, healthNeedsCurrent = true, healthNeedsMax = true }, health.UpdateValueSinglePercent },
    { "color", { healthSlotCount = 1, healthNeedsCurrent = true, healthColorByHealth = true }, health.UpdateValueSinglePercent },
}
for _, case in ipairs(cases) do
    probe._msufTextApplySignature, probe._msufTextRuntime = case[1], case[2]
    UF.OptimizeFrameHotpaths(probe)
    assert(probe[UF._updateKeys.Health] == case[3], "wrong compiled value plan: " .. case[1])
end
local rt = probe._msufTextRuntime
probe._msufTextApplySignature = "failed-compile"
rt.healthSlotCount = {}
assert(not pcall(UF.OptimizeFrameHotpaths, probe), "malformed needs unexpectedly compiled")
rt.healthSlotCount, rt.healthNeedsCurrent, rt.healthNeedsMax, rt.healthColorByHealth = 1, true, true, false
UF.OptimizeFrameHotpaths(probe)
assert(probe[UF._updateKeys.Health] == health.UpdateValueSingleAbsolute, "failed needs compile pinned a stale plan")
probe._msufTextRuntime = nil
UF.OptimizeFrameHotpaths(probe)
assert(probe[UF._updateKeys.Health] == health.UpdateValueSinglePercent, "disabled consumer retained its value plan")
local source = assert(io.open(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua", "rb")):read("*a")
for _, name in ipairs({ "elements.Health", "elements.Power", "elements.LoadConditions", "elements.Borders",
    "elements.Prediction", "elements.GroupVisuals", "MSUF_Auras3", "MSUF_DispelOverlayPreviewMode" }) do
    assert(not source:find(name, 1, true), "generic core knows " .. name)
end
-- The identity adapter preserves the host's function-only boundary guards.
local previousAuras = world.core.MSUF_Auras3
local identityFrame = { _msufActiveElements = { Auras = true } }
for _, sentinel in ipairs({ false, {} }) do
    world.core.MSUF_Auras3 = { OnFrameUnitChanged = sentinel }
    assert(pcall(UF.RouteCompiler.OnUnitChanged, identityFrame, "player", "target"),
        "non-function identity hook must be skipped")
end
local identityCalls = {}
local function IdentityCall() identityCalls[#identityCalls + 1] = "identity" end
local function BeginCall() identityCalls[#identityCalls + 1] = "begin" end
local function EndCall() identityCalls[#identityCalls + 1] = "end" end
for _, batch in ipairs({ { false, EndCall }, { BeginCall, {} }, { BeginCall, EndCall } }) do
    identityCalls = {}
    world.core.MSUF_Auras3 = { OnFrameUnitChanged = IdentityCall,
        BeginTopologyBatch = batch[1], EndTopologyBatch = batch[2] }
    UF.RouteCompiler.OnUnitChanged(identityFrame, "player", "target")
    local expected = type(batch[1]) == "function" and type(batch[2]) == "function"
        and "begin,identity,end" or "identity"
    assert(table.concat(identityCalls, ",") == expected, "identity batch guard or order changed")
end
world.core.MSUF_Auras3 = previousAuras
print("uf_route_registry_smoke: ok (" .. flavor .. ")")
