-- The shared mock aura painter only paints the regions it is handed. It creates no frame,
-- registers no event or unit watch, sets no secure attribute and binds no click or script,
-- and its geometry, text, bar and sample-state helpers keep their documented contracts.
-- Plain Lua 5.1: lua aura_mock_painter_contract_smoke.lua <repo root>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local PAINTER = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_MockAuraPainter.lua"

local function Read(path)
    local file = assert(io.open(path, "rb"), path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

---------------------------------------------------------------------------
-- 1. The painter source stays inert: no frame creation, events, unit watch,
--    secure attributes, scripts, hooks, protected calls or unit queries.
---------------------------------------------------------------------------
local source = Read(PAINTER)
for _, token in ipairs({ "CreateFrame", "RegisterEvent", "RegisterUnitEvent", "RegisterUnitWatch", "RegisterStateDriver",
    "SetAttribute", "SecureActionButton", "SecureUnitButton", "SecureHandler", "RegisterForClicks", "RegisterForDrag",
    "SetScript", "HookScript", "hooksecurefunc", "pcall", "xpcall", "InCombatLockdown", "UnitExists", "UnitGUID", "C_Timer",
    "EnableMouse", "SetParent", "CreateFontString", "CreateAnimationGroup" }) do
    assert(not source:find(token, 1, true), "the shared painter must not use " .. token)
end

---------------------------------------------------------------------------
-- 2. Recording regions that implement only the plain texture / text methods.
--    A secure, event or script method is simply absent, so any call errors.
---------------------------------------------------------------------------
local log = {}
local function Log(region, method, ...)
    log[#log + 1] = { region = region.name, method = method, ... }
end
local PLAIN = { "ClearAllPoints", "SetPoint", "SetWidth", "SetHeight", "SetTexture", "SetVertexColor", "SetTexCoord",
    "Show", "Hide", "SetShown", "SetAtlas", "SetJustifyH", "SetJustifyV" }
local function Region(name)
    local region = { name = name, points = {} }
    for _, method in ipairs(PLAIN) do
        region[method] = function(self, ...)
            Log(self, method, ...)
            if method == "ClearAllPoints" then self.points = {} end
            if method == "SetPoint" then self.points[#self.points + 1] = { ... } end
            if method == "SetWidth" then self.width = (...) end
            if method == "SetHeight" then self.height = (...) end
            if method == "SetVertexColor" then self.color = { ... } end
            if method == "Show" then self.shown = true end
            if method == "Hide" then self.shown = false end
        end
    end
    region.CreateTexture = function(self, ...)
        Log(self, "CreateTexture", ...)
        return Region(name .. "/child")
    end
    return region
end
local function Calls(region, method)
    local found = {}
    for _, entry in ipairs(log) do
        if entry.region == region.name and entry.method == method then found[#found + 1] = entry end
    end
    return found
end
local function Reset() log = {} end

local ANIMATION_CALLS = {}
local animationState = { stacks = "2", text = "7", remainingFrac = 0.5, elapsedFrac = 0.5 }
local staticBuilt, animatedBuilt = 0, 0
local namespace = {
    PreviewAnimation = {
        BuildAuraState = function(kind, index, scratch, options, elapsed)
            animatedBuilt = animatedBuilt + 1
            ANIMATION_CALLS[#ANIMATION_CALLS + 1] = { kind = kind, index = index, scratch = scratch, options = options, elapsed = elapsed }
            return animationState
        end,
    },
}
local A3 = {
    GetDurationBarColor = function() return 0.1, 0.2, 0.3 end,
    IconShape = { IconTexCoords = function() return 0, 1, 0, 1 end },
    ApplyAuraIconShape = function(_, shape) return shape end,
    ApplyIconStylePreview = function() end,
    ApplyAuraDispelPreview = function() return false end,
    PreviewDispelTypeForIndex = function() return "Magic" end,
    NativeAuraDispelBorderPadding = function(size) return size / 8 end,
}
namespace.MSUF_Auras3 = A3
namespace.Require = function(name)
    assert(name == "MSUF_PixelLayoutRegion", "the painter requires only the pixel layout wrapper, not " .. tostring(name))
    return function(region) return region end
end
_G.MSUF_GetPreviewAnimationAuraState = function(kind, index, scratch, options)
    staticBuilt = staticBuilt + 1
    ANIMATION_CALLS[#ANIMATION_CALLS + 1] = { kind = kind, index = index, scratch = scratch, options = options, static = true }
    return animationState
end
assert(loadfile(PAINTER))("MidnightSimpleUnitFrames", namespace)
local Painter = assert(A3.MockAuraPainter, "the painter publishes itself on the Auras3 namespace")

local icon = Region("icon")
local function Near(a, b) return math.abs(a - b) < 1e-9 end

-- Region creation reuses the caller's constructors and layers.
local swipe = Painter.NewSwipe(icon)
assert(Calls(icon, "CreateTexture")[1][1] == nil and Calls(icon, "CreateTexture")[1][2] == "ARTWORK"
    and Calls(icon, "CreateTexture")[1][4] == 1, "the swipe is an ARTWORK sublevel 1 texture")
assert(swipe.shown == false and Near(swipe.color[4], 0.58), "a new swipe is hidden and translucent black")
local anchored = Painter.NewSwipe(icon, -1, -1, 1)
assert(#anchored.points == 2 and anchored.points[1][1] == "TOPLEFT" and anchored.points[1][5] == -1
    and anchored.points[2][1] == "BOTTOMRIGHT" and anchored.points[2][4] == -1 and anchored.points[2][5] == 1,
    "initial swipe anchors are applied only when supplied")
local bar = Painter.NewDurationBar(icon)
assert(bar.shown == false and Near(bar.color[1], 0.1) and Near(bar.color[4], 0.92), "a new duration bar takes the live color")

-- Swipe: the remaining share is clamped to 8-92 %, from the right edge or the left when reversed.
local swipeRegion = Region("swipe")
Painter.Swipe(swipeRegion, icon, 24, 18, nil, false)
assert(swipeRegion.width == math.floor(24 * 0.48 + 0.5) and swipeRegion.height == 18, "default share is 48 %")
assert(swipeRegion.points[1][1] == "TOPRIGHT" and swipeRegion.points[2][1] == "BOTTOMRIGHT", "swipe grows from the right edge")
Painter.Swipe(swipeRegion, icon, 24, 18, 0.01, true)
assert(swipeRegion.width == math.floor(24 * 0.08 + 0.5) and swipeRegion.points[1][1] == "TOPLEFT"
    and swipeRegion.points[2][1] == "BOTTOMLEFT", "a reversed swipe is clamped at 8 % and grows from the left")
Painter.Swipe(swipeRegion, icon, 24, 0, 5, false)
assert(swipeRegion.width == math.floor(24 * 0.92 + 0.5) and swipeRegion.height == 1, "92 % cap and a one pixel minimum height")
Painter.TopSwipe(swipeRegion, icon, 30, 0.42)
assert(#swipeRegion.points == 2 and Near(swipeRegion.points[2][5], 30 * 0.42) and swipeRegion.shown == true
    and Near(swipeRegion.color[4], 0.58), "the core group swipe is a static opaque top share")

-- Duration bars: the menu and Edit Mode bar fills a share; the core group bar is full width and opaque.
local barRegion = Region("bar")
Painter.LayoutDurationBar(barRegion, icon, "TOP", 2, 1, 24, 0.5)
assert(barRegion.height == 2 and barRegion.width == math.floor((24 - 2) * 0.5 + 0.5) and #barRegion.points == 1
    and barRegion.points[1][1] == "TOPLEFT" and Near(barRegion.color[4], 0.92) and barRegion.shown == true,
    "a fill share covers that part of the inner width from the left")
Painter.LayoutDurationBar(barRegion, icon, "BOTTOM", 3, 2, 24, nil)
assert(#barRegion.points == 2 and barRegion.points[1][1] == "BOTTOMLEFT" and barRegion.points[2][1] == "BOTTOMRIGHT",
    "without a share the bar spans the inner width")
Reset()
local groupBar = Region("groupBar")
Painter.GroupDurationBar(groupBar, icon, "BOTTOM", 4)
local order = {}
for _, entry in ipairs(log) do order[#order + 1] = entry.method end
assert(table.concat(order, ",") == "ClearAllPoints,SetPoint,SetPoint,SetHeight,SetTexture,SetVertexColor,Show",
    "core group bars anchor before they take their height: " .. table.concat(order, ","))
assert(Near(groupBar.color[4], 1) and Near(groupBar.color[3], 0.3), "core group bars are opaque in the live color")
local stateBar = Region("stateBar")
Painter.DurationBar(stateBar, icon, { durationBarHeight = 2.5, durationBarPosition = "TOP", durationBarDirection = "ELAPSED" },
    32, 20, { elapsedFrac = 0.25, remainingFrac = 0.75 })
assert(stateBar.height == 3 and stateBar.width == math.floor((32 - 2) * 0.25 + 0.5), "the sample elapsed share drives an elapsed bar")
Painter.DurationBar(stateBar, icon, { durationBarHeight = 2 }, 32, 20, nil)
assert(#stateBar.points == 2, "without an aura state the bar spans the icon")

-- Text placement: three modes of one routine.
local text = Region("text")
Painter.PlaceText(text, icon, "BOTTOMRIGHT", 3, -4)
assert(text.points[1][1] == "BOTTOMRIGHT" and text.points[1][4] == 3 and Calls(text, "SetJustifyH")[1][1] == "RIGHT"
    and Calls(text, "SetJustifyV")[1][1] == "BOTTOM", "lane text takes the justification of its anchor")
Painter.PlaceText(text, icon, "NOPE", 1, 2)
assert(text.points[1][1] == "CENTER", "an unknown lane anchor falls back to the center")
Painter.PlaceText(text, icon, "topleft", "5", "x", "WORKBENCH")
assert(text.points[1][1] == "TOPLEFT" and text.points[1][4] == 5 and text.points[1][5] == 0, "the workbench accepts lowercase anchors and string offsets")
Painter.PlaceText(text, icon, "BOGUS", 0, 0, "WORKBENCH")
assert(text.points[1][1] == "BOGUS", "the workbench keeps an unknown point as typed")
Reset()
Painter.PlaceText(text, icon, "Left", 7, 8, "POINT_ONLY")
assert(text.points[1][1] == "LEFT" and #Calls(text, "SetJustifyH") == 0 and #Calls(text, "SetJustifyV") == 0,
    "core group text leaves its justification alone")

-- Dispel borders: OFF hides, a shaped painter wins, and the atlas fallback pads by the native rule.
local border = Region("border")
Painter.DispelBorder(border, icon, 24, "OFF", "RECTANGLE", 1)
assert(border.shown == false, "an OFF border is hidden")
A3.ApplyAuraDispelPreview = function(...) return true end
Reset()
Painter.DispelBorder(border, icon, 24, "BORDER", "CIRCLE", 1)
assert(#Calls(border, "SetAtlas") == 0, "a shaped border painted by the live helper needs no atlas")
A3.ApplyAuraDispelPreview = function() return false end
border.SetAtlas = function(self, atlas) self.atlas = atlas end
Painter.DispelBorder(border, icon, 24, "SYMBOL", "RECTANGLE", 1)
assert(border.atlas == "ui-debuff-border-magic-icon" and border.points[1][4] == -3 and border.shown == true,
    "the atlas fallback uses the native border padding")

-- Art routes zoom, shape, visibility and style through the live owners.
local art = { texture = Region("art"), background = Region("bg"), edge = Region("edge") }
local styleCalls = {}
A3.ApplyIconStylePreview = function(_, style, size, shape) styleCalls[#styleCalls + 1] = { style, size, shape } end
art.texture.SetShown = function(self, shown) self.visible = shown end
art.background.SetShown = function(self, shown) self.visible = shown end
local shape = Painter.Art(icon, art.texture, art.background, swipeRegion, 12345, 150, 24, 18, "CIRCLE", true, "STYLE", 24, art.edge)
assert(shape == "CIRCLE" and art.texture.visible == false and art.background.visible == false, "a bar-only lane hides the icon art")
assert(styleCalls[1][1] == "STYLE" and styleCalls[1][2] == 24 and styleCalls[1][3] == "CIRCLE", "the icon style follows the resolved shape")
assert(Near(art.edge.color[4], 0), "the preview edge is cleared")

---------------------------------------------------------------------------
-- 3. Sample state: scratch and options live on the icon, a static read and an
--    animated read use their own sources, and target-dot options never leak.
---------------------------------------------------------------------------
local holder = {}
local first = Painter.AuraState(holder, "buff", 2, { cooldownDecimalSeconds = 5 })
assert(first == animationState and staticBuilt == 1 and animatedBuilt == 0, "no clock reads the shared static sample")
local call = ANIMATION_CALLS[#ANIMATION_CALLS]
assert(call.static and call.kind == "buff" and call.index == 2 and call.options.decimalThreshold == 5, "decimal threshold follows the lane config")
local scratch, options = holder._msufAuraScratch, holder._msufAuraOptions
assert(scratch == call.scratch and options == call.options, "the scratch and options are the ones kept on the icon")
Painter.AuraState(holder, "debuff", 2, nil, 1.5, 18, true, 0.30)
call = ANIMATION_CALLS[#ANIMATION_CALLS]
assert(not call.static and call.elapsed == 1.5 and animatedBuilt == 1, "a clock reads the animation builder")
assert(call.options.duration == 18 and call.options.oneShot == true and call.options.pandemicThreshold == 0.30
    and call.options.decimalThreshold == 3, "a target-dot lane passes its one-shot window")
Painter.AuraState(holder, "debuff", 2, nil, 2.5)
call = ANIMATION_CALLS[#ANIMATION_CALLS]
assert(call.options.duration == nil and call.options.oneShot == nil and call.options.pandemicThreshold == nil,
    "the next plain read does not inherit the one-shot window")
assert(holder._msufAuraScratch == scratch and holder._msufAuraOptions == options and call.scratch == scratch,
    "repeated reads reuse one scratch and one options table")
namespace.PreviewAnimation = nil
_G.MSUF_BuildPreviewAnimationAuraState = function() return "global-build" end
assert(Painter.AuraState(holder, "buff", 1, nil, 0) == "global-build", "without the animation owner the exported builder answers")
_G.MSUF_BuildPreviewAnimationAuraState, _G.MSUF_GetPreviewAnimationAuraState = nil, nil
assert(Painter.AuraState(holder, "buff", 1, nil, 0) == nil and Painter.AuraState(holder, "buff", 1) == nil,
    "without any sample source the icon shows its fallback text")

---------------------------------------------------------------------------
-- 4. The consumers keep no private copy of what the painter owns.
---------------------------------------------------------------------------
local CONSUMERS = {
    "MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_Preview.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Preview.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua",
}
local COPIES = { "local function PlaceStackText", "local function PlaceCooldownText", "local function PlacePreviewText",
    "local function PlaceAuraText", "local function PlaceAuraPreviewText", "local function LayoutPreviewDispelBorder",
    "local function ApplyIconZoom", "local function ApplyAuraPreviewIconZoom", "local function AuraDurationBarColor",
    "local function PreviewAuraState", "local function GroupPreviewAuraState", "AURA_TEXT_JUSTIFY = {",
    "H.PaintPreviewAuraSwipe", "H.PaintPreviewDurationBar", "A3.LayoutPreviewDurationBar", "function A3.LayoutPreviewDurationBar" }
for _, path in ipairs(CONSUMERS) do
    local body = Read(root .. "/" .. path)
    for _, copy in ipairs(COPIES) do
        assert(not body:find(copy, 1, true), path .. " keeps a private copy again: " .. copy)
    end
end
for _, path in ipairs({ CONSUMERS[1], CONSUMERS[2], CONSUMERS[3], CONSUMERS[4], CONSUMERS[5] }) do
    if path == CONSUMERS[3] then
        local stage = Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
        assert(stage:find(":Unit(key)", 1, true) and Read(root .. "/" .. CONSUMERS[2]):find("MockAuraPainter", 1, true),
            "Options no longer delegates its aura body through the engine scene and shared painter")
        assert(not Read(root .. "/" .. path):find("CreateTexture", 1, true), "Options retained a duplicate aura painter")
    else
        assert(Read(root .. "/" .. path):find("MockAuraPainter", 1, true), path .. " no longer paints through the shared painter")
    end
end

print("PASS aura mock painter contract: inert source, plain regions only, geometry, text, bars and sample state")
