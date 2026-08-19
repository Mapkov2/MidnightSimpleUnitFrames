-- Regression for GitHub #123: a Full-Frame Aura effect rendered over the Name
-- text on live Group Frames while the menu preview drew it correctly below.
--
-- Both paths compute the same level through Layers.AuraEffectLevel, so the
-- formula was never the defect. The live effect root is a child of a native
-- AuraSlot button inside a SHARED AuraContainer whose own level is rewritten on
-- every geometry sync, and the client moves every descendant with its parent --
-- so the absolute level stamped in initializeFrame drifted by that delta and
-- nothing put it back. This models that propagation (including the client's
-- clamp at zero, which ratchets a down/up cycle upwards) and pins:
--   1. the live renderer and the options preview produce one identical level,
--   2. Runtime.RefreshFrameEffects restores it after the container moved,
--   3. the fixed-slot base is not written while a flow lane owns the level,
--   4. the resulting level still orders correctly against every other 0..30
--      surface (aura icons, spell icons, text, status, dispel).

_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = { "MidnightSimpleUnitFrames/" .. relative, relative }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "rb")
        if handle then
            handle:close()
            return candidates[i]
        end
    end
    error("cannot locate " .. relative)
end

local function Read(relative)
    local handle = assert(io.open(ResolvePath(relative), "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

_G.issecretvalue = function() return false end

-- Frame model with the one client behaviour this bug lives on: SetFrameLevel on
-- a parent shifts its whole subtree by the same delta, and no level goes below
-- zero. A down-shift that clamps therefore cannot be undone by the matching
-- up-shift, which is exactly how a 142 effect ended up above a 268 name.
local Widget
Widget = function(parent, level)
    local widget = {
        parent = parent,
        children = {},
        frameLevel = level or ((parent and parent.frameLevel or 0) + 1),
        frameStrata = parent and parent.frameStrata or "MEDIUM",
        shown = false,
    }
    if parent and parent.children then parent.children[#parent.children + 1] = widget end
    function widget:GetParent() return self.parent end
    function widget:GetFrameLevel() return self.frameLevel end
    function widget:GetFrameStrata() return self.frameStrata end
    function widget:SetFrameStrata(value) self.frameStrata = value end
    function widget:SetFrameLevel(value)
        value = value < 0 and 0 or value
        local delta = value - self.frameLevel
        self.frameLevel = value
        if delta ~= 0 then
            for i = 1, #self.children do
                local child = self.children[i]
                child:SetFrameLevel(child.frameLevel + delta)
            end
        end
    end
    function widget:SetAlpha(value) self.alpha = value end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown == true end
    function widget:CreateTexture() return Widget(self) end
    function widget:CreateFontString() return Widget(self) end
    function widget:GetStatusBarTexture() return self.statusTexture end
    function widget:GetFont() return "font.ttf", 12, "" end
    function widget:GetText() return "Vermithor" end
    local noops = {
        "EnableMouse", "SetMouseMotionEnabled", "ClearAllPoints", "SetAllPoints",
        "SetPoint", "SetSize", "SetTexture", "SetTexCoord", "SetVertexColor",
        "SetText", "SetTextColor", "SetBlendMode", "SetJustifyH", "SetJustifyV",
        "SetShadowColor", "SetShadowOffset", "SetFont", "SetWidth", "SetHeight",
    }
    for i = 1, #noops do widget[noops[i]] = function() end end
    return widget
end

_G.CreateFrame = function(_, _, parent) return Widget(parent) end

local MSUF = { UF = {}, MSUF_Auras3 = {} }
_G.MSUF_NS = MSUF
assert(loadfile(ResolvePath("Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")))(
    "MidnightSimpleUnitFrames", MSUF)
local Layers = assert(MSUF.UF.Layers)
assert(loadfile(ResolvePath("Auras3/MSUF_Auras3_SpellIndicators.lua")))(
    "MidnightSimpleUnitFrames", MSUF)
local Runtime = assert(MSUF.MSUF_Auras3.SpellIndicators)

--- One Group Frame: health bar at the frame base, Name text on its own overlay
--- at the shared default Layer 5, role icon on the status holder at Layer 1.
local function GroupFrame()
    local frame = Widget(nil, 1)
    local health = Widget(frame, Layers.HealthLevel(frame:GetFrameLevel()))
    health.statusTexture = health:CreateTexture()
    frame.hpBar = health
    frame.Health = health
    local nameLayer = Widget(frame, Layers.TextLevel(frame, 5, 5))
    frame.nameText = nameLayer:CreateFontString()
    frame.nameText.parent = nameLayer
    frame.nameText.GetParent = function(self) return self.parent end
    frame.roleHolder = Widget(frame, Layers.StatusLevel(frame, 1, 7))
    return frame
end

local EFFECT = {
    type = "healthtint",
    color = { 0.86, 0.67, 0.02, 0.8 },
    priority = 1,
    tintAlpha = 0.8,
    thickness = 2,
    layer = 1,
    strata = "AUTO",
}

local live = GroupFrame()
local expected = Layers.AuraEffectLevel(EFFECT.layer, EFFECT.priority, live.hpBar)
Equal(expected, Layers.ElementLevel(1, 0, 10), "effect band moved off the shared 0..30 scale")

-- The live surface hangs under a native AuraSlot button inside the shared
-- container, which the group-slot sync parks on the flowing lane's band.
local flowLevel = Layers.ElementLevel(6, 1, 0)
local container = Widget(live, live:GetFrameLevel() + 1)
local button = Widget(container, Layers.ELEMENT_LEVEL_BASE - 1)
local owner = Widget(button, button:GetFrameLevel())

assert(Runtime.ApplyPreviewFrameEffect(owner, EFFECT, live) == true,
    "the live Full-Frame renderer refused a valid health tint")
local root = assert(owner._msufA3SpellIndicatorEffectRoot, "no effect surface was created")
Equal(root:GetFrameLevel(), expected, "the applied effect ignored its configured Layer")

-- Every geometry sync writes the container level twice: the fixed-slot base
-- first, the flowing lane's band second. Without the guard the descendants ride
-- along and the clamp turns the round trip into a one-way ratchet.
container:SetFrameLevel(live:GetFrameLevel())
container:SetFrameLevel(flowLevel)
assert(root:GetFrameLevel() ~= expected,
    "the frame model no longer reproduces container level propagation")
assert(root:GetFrameLevel() > Layers.TextLevel(live, 5, 5),
    "the drifted effect no longer reproduces the reported Name overlap")

assert(Runtime.RefreshFrameEffects(live) == true,
    "RefreshFrameEffects did not re-stamp a live effect surface")
Equal(root:GetFrameLevel(), expected, "the effect surface was not restored to its configured Layer")
assert(root:GetFrameLevel() < Layers.TextLevel(live, 5, 5),
    "the restored effect still covers the default Name text")

-- A sealed AuraButton descendant must be left where it is. PTR 7 refuses the
-- write outright ("Attempt to access forbidden object"), so the repair pass has
-- to ask first instead of erroring once per visible frame.
local sealed = GroupFrame()
local sealedContainer = Widget(sealed, sealed:GetFrameLevel() + 1)
local sealedButton = Widget(sealedContainer, Layers.ELEMENT_LEVEL_BASE - 1)
local sealedOwner = Widget(sealedButton, sealedButton:GetFrameLevel())
assert(Runtime.ApplyPreviewFrameEffect(sealedOwner, EFFECT, sealed) == true,
    "the live renderer refused the effect on the sealed-button model")
local sealedRoot = assert(sealedOwner._msufA3SpellIndicatorEffectRoot)
sealedContainer:SetFrameLevel(flowLevel)
local driftedLevel = sealedRoot:GetFrameLevel()
sealedRoot.CanBeAccessedInContext = function() return false end
sealedRoot.SetFrameLevel = function() error("wrote to a sealed effect surface") end
Equal(Runtime.RefreshFrameEffects(sealed), false,
    "the refresh wrote to a surface the client had sealed")
Equal(sealedRoot:GetFrameLevel(), driftedLevel, "a sealed effect surface was moved anyway")

-- Preview parity: the options preview owns a surface on the preview frame and
-- must land on the very same absolute level as the live one.
local preview = GroupFrame()
local previewOwner = Widget(preview, preview:GetFrameLevel() + 1)
assert(Runtime.ApplyPreviewFrameEffect(previewOwner, EFFECT, preview) == true,
    "the preview adapter refused the same effect the live path accepted")
local previewRoot = assert(previewOwner._msufA3SpellIndicatorEffectRoot,
    "the preview created no effect surface")
Equal(previewRoot:GetFrameLevel(), root:GetFrameLevel(),
    "preview and runtime disagree on the Full-Frame effect level")

-- A cleared effect must leave nothing behind for the re-stamp to resurrect.
assert(Runtime.HidePreviewFrameEffect(previewOwner) == true, "the preview surface was not retired")
Equal(previewOwner._msufA3FrameEffectApplied, nil,
    "a retired effect still carries its applied configuration")

-- Ordering against every other surface on the shared scale. At Layer 0 the
-- strongest effect stays inside the bar-local band; the user's 0..30 Layer is
-- what lifts it, and it lifts it against all of them equally.
local baseEffect = Layers.AuraEffectLevel(0, 1, live.hpBar)
assert(baseEffect < Layers.TextLevel(live, 5, 5), "default effect covers the default Name text")
assert(baseEffect < Layers.StatusLevel(live, 7, 7), "default effect covers default status icons")
assert(baseEffect > Layers.ElementLevel(0, 1, 0), "default effect sank below the Layer 0 aura lane")
assert(Layers.AuraEffectLevel(6, 1, live.hpBar) > Layers.TextLevel(live, 5, 5),
    "an explicitly raised effect Layer can no longer outrank text")
assert(Layers.AuraEffectLevel(0, 1, live.hpBar) < Layers.ElementLevel(0, 0, 12),
    "the Dispel overlay no longer sits above the strongest Spell effect")
assert(Layers.AuraEffectLevel(0, 10, live.hpBar) < Layers.AuraEffectLevel(0, 1, live.hpBar),
    "effect priority stopped ordering inside its own Layer")

-- Source contracts for the two writers this fix depends on.
local spellSource = Read("Auras3/MSUF_Auras3_SpellIndicators.lua")
assert(spellSource:find("sharedLevelOwner", 1, true)
    and spellSource:find("if container.SetFrameLevel and sharedLevelOwner ~= true then", 1, true),
    "Spell Indicator SyncGeometry writes the container level even for a shared owner")
-- Prevention outranks repair: a sealed surface can no longer be put back, so
-- the container it hangs under must not move once it owns native buttons.
assert(spellSource:find("if current ~= level and not HasLiveNativeButton(container) then", 1, true),
    "a container with live native AuraButtons can be re-levelled again")
assert(spellSource:find("local function CanWriteEffectSurface(root)", 1, true)
    and spellSource:find("and CanWriteEffectSurface(root) then", 1, true),
    "the effect refresh no longer probes access before writing")

local unitSource = Read("Auras3/MSUF_Auras3_UnitFrames.lua")
local groupSyncStart = assert(unitSource:find("local function SyncGroupSlotsGeometry", 1, true))
local groupSyncEnd = assert(unitSource:find("local function CreateManagedGroupSlots", groupSyncStart, true))
local groupSync = unitSource:sub(groupSyncStart, groupSyncEnd)
local sharedFlagAt = groupSync:find("flowLane ~= nil) and ok", 1, true)
local flowWriteAt = groupSync:find("SyncContainerGeometry(container, flowLane", 1, true)
local restampAt = groupSync:find("SpellIndicatorsRuntime.RefreshFrameEffects(parentFrame)", 1, true)
assert(sharedFlagAt and flowWriteAt and restampAt
    and sharedFlagAt < flowWriteAt and flowWriteAt < restampAt,
    "group slots do not re-stamp their Full-Frame effects after the last container level write")

-- One renderer for all three surfaces. Every reintroduced local copy is a
-- preview that can drift away from the frames again.
local previewSource = Read("UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
assert(previewSource:find("runtime.ApplyPreviewFrameEffect(EnsureSpellFrameEffectOwner(visual, frame)", 1, true)
    and previewSource:find("runtime.HidePreviewFrameEffect(owner)", 1, true)
    and not previewSource:find("_frameEffectRoot", 1, true),
    "the Group preview draws Full-Frame effects with its own renderer again")

local editModeSource = Read("Auras3/MSUF_Auras3_EditMode.lua")
assert(editModeSource:find("runtime.ApplyPreviewFrameEffect(owner, effect, frame)", 1, true)
    and not editModeSource:find("root.edges[i]:SetVertexColor", 1, true),
    "Edit Mode draws Custom Aura Full-Frame effects with its own renderer again")

print("aura_frame_effect_level_smoke: ok (container drift + preview parity + layer order)")
