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
    function fs:GetText() return self.text end
    function fs:SetAlpha(value) self.alpha = value end
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
    function clip:SetAllPoints(value) self.allPoints = value end
    function clip:SetSize(width, height) self.width, self.height = width, height end
    function clip:ClearAllPoints() self.points = nil end
    function clip:SetPoint(...) self.points = { ... } end
    function clip:Show() self.shown = true end
    function clip:Hide() self.shown = false end
    function clip:CreateFontString() return FontString(self) end
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
    SetShownCached = function(region, shown)
        if shown then region:Show() else region:Hide() end
        region._msufShown = shown == true
    end,
    SetTextCached = function(region, value) region:SetText(value) end,
    SetFont = function() return true end,
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

local proxyFrame = {
    hpBar = {},
    _msufNameRelativeStatus = true,
}
proxyFrame.nameText = FontString(proxyFrame)
proxyFrame.nameText:SetText("Astral Warden")
local proxySpec = {
    showName = true,
    nameFontSize = 14,
    text = {
        anchorToBars = true,
        nameAnchor = "LEFT",
        nameX = 4,
        nameY = 1,
        nameLayer = 5,
    },
}
Check(Text.EnsureNameAnchorProxy(proxyFrame, proxySpec) == true,
    "bar-anchored name proxy was not created")
local proxy = proxyFrame._msufNameAnchorText
Check(proxyFrame._msufNameAnchorTextActive == true and proxy and proxy.shown,
    "bar-anchored name proxy was not activated")
Check(proxy.text == "Astral Warden" and proxy.width == 0 and proxy.alpha == 0,
    "bar-anchored name proxy did not mirror an invisible auto-sized name")
Check(proxy.points and proxy.points[1] == "LEFT" and proxy.points[2] == proxyFrame.hpBar
    and proxy.points[3] == "LEFT" and proxy.points[4] == 7 and proxy.points[5] == 1,
    "bar-anchored name proxy did not mirror the visible name origin")
Check(Text.EnsureNameAnchorProxy(proxyFrame, proxySpec) == false,
    "unchanged bar-name proxy repeated lifecycle work")
proxySpec.text.nameShorten = true
proxySpec.text.nameShortenMax = 10
Check(Text.EnsureNameAnchorProxy(proxyFrame, proxySpec) == true,
    "shortened name did not deactivate the full-name proxy")
Check(proxyFrame._msufNameAnchorTextActive == nil and proxy.shown == false and proxy.text == "",
    "inactive full-name proxy retained visible or stale state")

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

local function Read(path)
    local handle = assert(io.open(path, "r"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local configSource = Read(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Config.lua")
Check(not configSource:find('if unit == "player" and not %(conf', 1),
    "runtime config still suppresses Shared name shortening for Player")

local fontsSource = Read(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua")
Check(fontsSource:find('{ "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }', 1, true),
    "Shared name-shortening apply does not include Player")
Check(not fontsSource:find('nameScope ~= "player"', 1, true),
    "Player scope still hides the Name Shortening controls")
Check(not fontsSource:find("except Player", 1, true),
    "Name Shortening UI still describes Player as excluded")

local modelNamespace = {
    MSUF2 = {
        KeySetFromWords = function(words)
            local out = {}
            for word in words:gmatch("%S+") do out[word] = true end
            return out
        end,
        WordList = function(words)
            local out = {}
            for word in words:gmatch("%S+") do out[#out + 1] = word end
            return unpack(out)
        end,
        AssignNamedValues = function(target, names, ...)
            local index = 0
            for name in names:gmatch("%S+") do
                index = index + 1
                target[name] = select(index, ...)
            end
        end,
    },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Model.lua"))(
    "MidnightSimpleUnitFrames", modelNamespace)
local shortenPreviewName = assert(modelNamespace.UFPreview and modelNamespace.UFPreview.Model
    and modelNamespace.UFPreview.Model.ShortenPreviewName, "preview name-shortening resolver missing")

local oldDB = _G.MSUF_DB
_G.MSUF_DB = {
    shortenNames = true,
    general = {
        shortenNameMaxChars = 5,
        shortenNameClipSide = "RIGHT",
        shortenNameShowDots = true,
    },
    player = { fontOverride = false },
}
Check(shortenPreviewName("MarcoLong", "player", { nameTextAnchor = "LEFT" }) == "Marco...",
    "Player preview does not inherit Shared name shortening")

_G.MSUF_DB.player = { fontOverride = true, shortenNames = false }
Check(shortenPreviewName("MarcoLong", "player", { nameTextAnchor = "LEFT" }) == "MarcoLong",
    "Player preview ignores a disabled scoped override")

_G.MSUF_DB.player = {
    fontOverride = true,
    shortenNames = true,
    shortenNameMaxChars = 4,
    shortenNameClipSide = "LEFT",
    shortenNameShowDots = false,
}
Check(shortenPreviewName("MarcoLong", "player", { nameTextAnchor = "LEFT" }) == "Long",
    "Player preview does not apply its scoped shortening values")
_G.MSUF_DB = oldDB

print("PASS name shortening: Player scope, preview, character cap, and secret-safe layout")
