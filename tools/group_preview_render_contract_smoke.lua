local function Noop() end
local F = {
    Nil = function() end, False = function() return false end, Empty = function() return "" end,
    Status = function() return "Status" end, QuestionIcon = function() return 134400 end,
    WhiteRGB = function() return 1, 1, 1 end, Round = function(v) return math.floor((tonumber(v) or 0) + 0.5) end,
    Noop = Noop, HealthRGB = function() return 0, 1, 0 end,
}
local M = { Fallbacks = F }
local MSUF = { MSUF2 = M, UF = { Layers = {} } }
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua"))(nil, MSUF)

local Render = assert(M.GroupPreviewRender, "renderer module missing")
for _, name in ipairs({ "Plan", "Auras", "Finalize" }) do
    assert(type(Render.Components[name]) == "function", "missing render component: " .. name)
end
assert(table.concat(Render.ComponentOrder, ",") == "Plan,FrameAndText,Auras,Indicators,Finalize",
    "component order changed")

local conf = {
    auras = {
        buff = { enabled = true, max = 4 },
        debuff = { enabled = true, max = 4 },
    },
    spellIndicators = { enabled = true },
    showName = true,
    showHPText = true,
}
local H = {
    CurrentScope = function() return "party" end,
    PreviewScopeLabel = function() return "Party" end,
    Conf = function() return conf end,
    PreviewFocusForPage = function() return "health" end,
}
local runtimeSpec = {
    showName = true, showHealthText = true, showPowerText = true,
    auras = { enabled = true },
    status = {},
    spellIndicators = {
        enabled = true,
        items = {
            { specKey = "spec", auraName = "Spell", placed = { type = "icon" }, frame = { type = "glow", priority = 3 } },
            { placed = { type = "bar" }, frame = { type = "border", priority = 5 } },
        },
    },
}
local S = {
    H = H, M = M, MSUF = {}, ctx = { key = "group" }, mock = {}, statusSpecs = {},
    CompiledSpec = function() return runtimeSpec end,
    CompiledAuraLane = function(_, lane, fallback)
        fallback.enabled = lane ~= "trackedBuff"
        fallback.max = fallback.max or 4
        return fallback
    end,
    CurrentStatusSpec = function() end,
    CurrentSpellConfig = function() return { placed = { type = "icon" } } end,
    CurrentSpellInfo = function() return nil, "spec", "Spell" end,
    PreviewAllSpecSpellIcons = function() return false end,
    CurrentSpellPlaced = function() return { type = "icon" } end,
    RuntimeStatusConfig = function() end,
    StatusSpecEnabled = function() return false end,
    StatusSpecInMode = function() return false end,
}
local box = { _msufGFRenderState = S, _textHandles = {} }
local scene = Render.Components.Plan(box, "CONTRACT")
assert(scene.kind == "party" and scene.label == "Party", "scope plan mismatch")
assert(scene.layerAvailable.buff and scene.layerAvailable.debuff, "aura lanes disappeared")
assert(scene.layerAvailable.si, "spell indicators disappeared")
assert(scene.selectedSpellEffect and scene.selectedSpellEffect.type == "glow", "selected spell effect plan mismatch")

M.gfPreviewLayerVisible = { buff = false }
scene = Render.Components.Plan(box, "HIDDEN_LAYER")
assert(scene.layerVisible.buff == false, "hidden group preview layer was not preserved")

M.gfPreviewLayerVisible = "invalid"
scene = Render.Components.Plan(box, "INVALID_LAYER_STATE")
assert(type(scene.layerVisible) == "table", "invalid layer visibility state was not contained")

local file = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua", "rb"))
local source = file:read("*a")
file:close()
local contracts = {
    "showCooldownSwipe", "cooldownSwipeReverse", "showDurationBar", "durationBarDirection",
    "dispelBorderMode", "readyCheckIcon", "resurrectIcon",
    "healthtint", "namecolor", "ApplyRounded", "FrameStrata", "healthLeftHidePercentSymbol",
    "powerRightHidePercentSymbol", "HideUnusedSpellIndicatorHandles", "ApplyTextFocus", "ResolveNameColor",
}
for _, token in ipairs(contracts) do assert(source:find(token, 1, true), "missing render contract: " .. token) end
assert(not source:match("function box:Refresh.-local function LayoutAuraGroup"),
    "aura component was folded back into Refresh")

local nativeFile = assert(io.open("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua", "rb"))
local nativeSource = nativeFile:read("*a")
nativeFile:close()
assert(nativeSource:find("PreviewHelpers.CreateLayerButton", 1, true),
    "group preview layers no longer use the shared layer button design")
assert(not nativeSource:find("MakePreviewSectionButton", 1, true),
    "legacy group-only layer button design returned")

print("group preview render contract smoke: ok")
