-- NAMERIGHT status text may reserve frame space, but must not reduce the
-- configured name-shortening character cap a second time.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function()
    error("cold name layout must not inspect secret values", 2)
end

local function FontString(parent)
    local fs = { parent = parent, shown = false, text = "" }
    function fs:GetParent() return self.parent end
    function fs:SetParent(value) self.parent = value end
    function fs:ClearAllPoints() self.points = nil end
    function fs:SetPoint(...) self.points = { ... } end
    function fs:SetJustifyH(value) self.justify = value end
    function fs:SetWordWrap(value) self.wordWrap = value end
    function fs:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
    function fs:SetWidth(value) self.width = value end
    function fs:SetText(value) self.text = value or "" end
    function fs:GetStringWidth() return #self.text * 7 end
    function fs:GetFont() return "Fonts\\FRIZQT__.TTF", 14, "OUTLINE" end
    function fs:SetFont() end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    return fs
end

local function ClipFrame(parent)
    local clip = { parent = parent, shown = false }
    function clip:GetParent() return self.parent end
    function clip:EnableMouse() end
    function clip:SetClipsChildren(value) self.clipsChildren = value == true end
    function clip:SetFrameLevel(value) self.frameLevel = value end
    function clip:SetSize(width, height) self.width, self.height = width, height end
    function clip:ClearAllPoints() self.points = nil end
    function clip:SetPoint(...) self.points = { ... } end
    function clip:Show() self.shown = true end
    function clip:Hide() self.shown = false end
    return clip
end

_G.UIParent = {
    CreateFontString = function(parent)
        return FontString(parent or _G.UIParent)
    end,
}

local Text = {
    CreateFrame = function(_, _, parent) return ClipFrame(parent) end,
    UF = { Layers = {}, elements = {} },
    tonumber = tonumber,
    floor = math.floor,
    max = math.max,
    EMPTY_EVENTS = {},
    DrawSubLayer = function(layer, fallback) return tonumber(layer) or fallback end,
    ClampFrameLayer = function(layer, fallback) return tonumber(layer) or fallback end,
    GetLayerBaseLevel = function() return 0 end,
    SetFrameLevelCached = function(frame, level) frame:SetFrameLevel(level) end,
}
local MSUF = { UF = Text.UF, UFText = Text }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local applyNameClip
for index = 1, 100 do
    local name, value = debug.getupvalue(Text.Apply, index)
    if not name then break end
    if name == "ApplyNameClip" then
        applyNameClip = value
        break
    end
end
Check(type(applyNameClip) == "function", "ApplyNameClip cold-path upvalue missing")

local function ClipWidth(withLevel)
    local frame = { unit = "target" }
    frame.MSUFNameTextLayer = frame
    frame.nameText = FontString(frame)
    function frame:GetWidth() return 280 end
    function frame:GetFrameLevel() return 1 end

    local spec = {
        width = 280,
        nameFontSize = 14,
        status = withLevel and {
            level = { enabled = true, anchor = "NAMERIGHT" },
        } or {},
    }
    local text = {
        nameAnchor = "LEFT",
        nameX = 30,
        nameY = -4,
        nameLayer = 20,
        nameShorten = true,
        nameShortenMax = 10,
        nameShortenSide = "RIGHT",
        nameShortenDots = false,
    }
    applyNameClip(frame, spec, text)
    Check(frame._msufNameClipFrame and frame._msufNameClipFrame.clipsChildren,
        "no-ellipsis shortening did not create its clip frame")
    return frame._msufNameClipFrame.width
end

local withoutLevel = ClipWidth(false)
local withLevel = ClipWidth(true)
Check(withoutLevel == 70, "10-character baseline width changed: " .. tostring(withoutLevel))
Check(withLevel == withoutLevel,
    "NAMERIGHT level reduced 10-character name width: " .. tostring(withLevel))

print("PASS name shortening level reservation: character cap stays independent and secret-safe")
