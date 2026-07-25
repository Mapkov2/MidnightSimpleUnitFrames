-- Regression: Frame Outline consumes the cold-compiled 0..30 Layer beside
-- FrameStrata without SavedVariables work in its event-driven runtime element.
local root = arg and arg[1] or "."

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local Frame = {}
Frame.__index = Frame
function Frame:SetAllPoints(target) self.allPoints = target or true end
function Frame:EnableMouse(value) self.mouseEnabled = value end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameLevel(value) self.frameLevel = value end
function Frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
function Frame:SetFrameStrata(value) self.frameStrata = value end
function Frame:CreateTexture()
    return setmetatable({ parent = self, shown = true }, Frame)
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function Frame:SetHeight(value) self.height = value end
function Frame:SetWidth(value) self.width = value end
function Frame:SetColorTexture(...) self.colorTexture = { ... } end
function Frame:SetVertexColor(...) self.vertexColor = { ... } end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end

local function NewFrame(parent)
    return setmetatable({ parent = parent, frameLevel = parent and parent.frameLevel or 0, frameStrata = "MEDIUM", shown = true }, Frame)
end

_G.CreateFrame = function(_, _, parent) return NewFrame(parent) end
_G.issecretvalue = function() return false end

local registered = {}
local UF = {
    RegisterElement = function(name, element) registered[name] = element end,
}
local MSUF = {
    UF = UF,
    UFVisuals = {
        UF = UF,
        CreateFrame = _G.CreateFrame,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        IsNil = function(value) return value == nil end,
        NotSecretValue = function() return true end,
        EMPTY_EVENTS = {},
        BORDER_THREAT_EVENTS = {},
        SetShown = function(region, shown) if shown then region:Show() else region:Hide() end end,
    },
}
_G.MSUF_NS = MSUF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local Borders = assert(registered.Borders, "Borders element did not register")
local parent = NewFrame(nil)
parent.frameLevel = 20

local function ApplyLayer(layer, strata)
    Borders.Apply(parent, { border = {
        enabled = true, thickness = 2, layer = layer, strata = strata or "AUTO",
        r = 0.1, g = 0.2, b = 0.3, a = 1,
        aggro = false, dispel = false, purge = false, bossTarget = false,
    } })
    return assert(parent.MSUFBorderOverlay, "Frame Outline overlay missing")
end

local Layers = assert(UF.Layers)
local overlay = ApplyLayer(0, "AUTO")
Equal(overlay.frameLevel, parent.frameLevel + Layers.FRAME_BORDER_NORMAL_OFFSET,
    "Layer 0 changed the legacy Frame Outline level")
Equal(overlay.frameStrata, parent.frameStrata, "AUTO Frame Outline did not inherit strata")

overlay = ApplyLayer(13, "HIGH")
Equal(overlay.frameLevel, parent.frameLevel + Layers.FRAME_BORDER_NORMAL_OFFSET + 13,
    "Frame Outline ignored compiled Layer 13")
Equal(overlay.frameStrata, "HIGH", "Frame Outline ignored explicit FrameStrata")

overlay = ApplyLayer(30, "LOW")
Equal(overlay.frameLevel, parent.frameLevel + Layers.FRAME_BORDER_NORMAL_OFFSET + 30,
    "Frame Outline ignored Layer 30")

print("layer_strata_runtime_smoke: ok (Frame Outline Layer 0/13/30 + legacy FrameStrata compatibility)")
