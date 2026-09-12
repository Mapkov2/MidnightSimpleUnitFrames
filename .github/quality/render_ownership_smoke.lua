local F = {
    Nil = function() end, Noop = function() end, False = function() return false end,
    One = function() return 1 end, Empty = function() return "" end,
}
local ns = { MSUF2 = { Fallbacks = F, PickFallbackTable = function(deps, fallbacks, names)
    local out = {}
    for name in names:gmatch("%S+") do out[name] = deps[name] or fallbacks[name] end
    return out
end } }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"))("MSUF", ns)
local one, two = {}, {}
local function Dependencies(value)
    return { ApplyPreviewFont = F.Noop, PowerColor = function() return value, 0, 0 end, PreviewInCombat = F.False }
end
ns.UFPreviewRender.Install(one, Dependencies(0.2))
ns.UFPreviewRender.Install(two, Dependencies(0.8))
local function Upvalue(fn, wanted)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
end
local stages = Upvalue(one.Refresh, "Stage")
assert(stages == Upvalue(two.Refresh, "Stage"), "Install recreated the render pipeline")
assert(one.RefreshDeps._RenderState ~= two.RefreshDeps._RenderState, "independent preview state was shared")
assert(one.RefreshDeps._RenderState.PowerColor() == 0.2 and two.RefreshDeps._RenderState.PowerColor() == 0.8)
local order = {}
for name in pairs(stages) do
    local stageName = name
    stages[name] = function(state, preview)
        assert(state.D == one.RefreshDeps, "refresh read another preview's dependencies")
        if stageName == "MeasureTextFootprint" or stageName == "RenderAurasAndStatus" then
            assert(preview == one, "selection owner was not passed explicitly")
        end
        order[#order + 1] = stageName
    end
end
one.Refresh({ IsShown = function() return true end })
assert(table.concat(order, ",") == "ResolveInputs,ResolveFrameGeometry,ResolvePowerGeometry,MeasureTextFootprint,MeasureLayerFootprint,ResolveScaleAndLevels,RenderHealth,RenderPowerBar,RenderClassPower,RenderDetachedPower,RenderFrameChrome,ApplyTextStyle,RenderTextContent,LayoutTextSlots,RenderPortrait,RenderCastbar,RenderAurasAndStatus,FinalizeLayersAndHandles", "render stage order changed")
print("render_ownership_smoke: OK (shared pipeline, isolated state, stage order and selection owner)")
